"""Read a restricted Ipopt 3.14.19 native augmented-system printout.

Supports dense/homogeneous vectors and the standard four-block KKT layout.
Repeated triplet positions are contributions to be summed, never overwritten.
This is diagnostic output before linear-solver scaling/pivoting, not a factor.
"""
import math
import re
from ivr_refinement_trace import NUMBER


def number(s):
    v=float(s)
    if not math.isfinite(v): raise ValueError('nonfinite value')
    return v


def vector(text,name):
    header=rf'DenseVector "{re.escape(name)}" with (\d+) elements:'
    found=list(re.finditer(header,text))
    if len(found)!=1: raise ValueError('missing/duplicate vector '+name)
    n=int(found[0][1]);tail=text[found[0].end():]
    # Stop at the next vector/matrix header or compound component.
    tail=re.split(r'\n\s*(?:DenseVector |Component |Term \d|\w*Matrix )',tail,maxsplit=1)[0]
    homogeneous=re.findall(rf'Homogeneous vector, all elements have value\s+({NUMBER})',tail)
    entries=re.findall(rf'^\s*{re.escape(name)}\[\s*(\d+)\]=\s*({NUMBER})\s*$',tail,re.M)
    if homogeneous:
        if len(homogeneous)!=1 or entries: raise ValueError('ambiguous homogeneous vector')
        return [number(homogeneous[0])]*n
    if [int(i) for i,_ in entries]!=list(range(1,n+1)):
        raise ValueError('incomplete/out-of-order vector '+name)
    return [number(v) for _,v in entries]


def triplet(text,name,symmetric=False,allow_uninitialized=False):
    label=re.escape(name)
    if symmetric:
        header=rf'SymTMatrix "{label}" of dimension (\d+) with (\d+) nonzero elements:'
    else:
        header=rf'GenTMatrix "{label}" of dimension (\d+) by (\d+) with (\d+) nonzero elements:'
    m=re.search(header,text)
    if not m: raise ValueError('unsupported/missing triplet '+name)
    nr=int(m[1]);nc=nr if symmetric else int(m[2]);nnz=int(m[2] if symmetric else m[3])
    entries=re.findall(rf'^\s*{label}\[\s*(\d+),\s*(\d+)\]=\s*({NUMBER})\s+\((\d+)\)\s*$',text,re.M)
    if 'Uninitialized!' in text:
        if not allow_uninitialized or entries: raise ValueError('uninitialized nonzero term')
        return dict(shape=[nr,nc],rows=[],columns=[],values=[])
    if [int(e[3]) for e in entries]!=list(range(nnz)): raise ValueError('incomplete triplet '+name)
    rows=[];cols=[];vals=[]
    for i,j,v,_ in entries:
        i,j=int(i),int(j)
        if not(1<=i<=nr and 1<=j<=nc): raise ValueError('invalid triplet index')
        if symmetric: i,j=max(i,j),min(i,j)
        rows.append(i);cols.append(j);vals.append(number(v))
    return dict(shape=[nr,nc],rows=rows,columns=cols,values=vals)


def matrix(text):
    if text.count('CompoundSymMatrix "KKT" with 4 rows and columns components:')!=1:
        raise ValueError('one standard KKT required')
    parts=re.split(r'Component for row (\d) and column (\d):',text)
    keys=[(int(parts[k]),int(parts[k+1])) for k in range(1,len(parts),3)]
    if keys!=[(i,j) for i in range(4) for j in range(i+1)]:
        raise ValueError('incomplete/out-of-order KKT blocks')
    blocks={key:parts[3*k+3] for k,key in enumerate(keys)}
    for key in ((1,0),(2,1),(3,2)):
        if blocks[key].strip()!='This component has not been set.': raise ValueError('unexpected coupling block')
    h=blocks[0,0];terms=re.split(rf'Term (\d+) with factor\s+({NUMBER}) and the following matrix:',h)
    if len(terms)!=7 or terms[1]!='0' or terms[4]!='1': raise ValueError('unsupported Hessian sum')
    wf,df=number(terms[2]),number(terms[5])
    W=triplet(terms[3],'Term: 0',True,allow_uninitialized=wf==0)
    dx=vector(terms[6],'Term: 1')
    ds=vector(blocks[1,1],'KKT[1][1]');dc=vector(blocks[2,2],'KKT[2][2]');dd=vector(blocks[3,3],'KKT[3][3]')
    jc=jacobian_block(blocks[2,0],'KKT[2][0]');jd=jacobian_block(blocks[3,0],'KKT[3][0]')
    identity=re.search(rf'IdentityMatrix "KKT\[3\]\[1\]" with (\d+) rows and columns and the factor\s+({NUMBER})\.',blocks[3,1])
    if not identity or number(identity[2])!=-1: raise ValueError('unsupported slack identity')
    nx,ns,nc,nd=len(dx),len(ds),len(dc),len(dd)
    if W['shape']!=[nx,nx] or jc['shape']!=[nc,nx] or jd['shape']!=[nd,nx] or ns!=nd or int(identity[1])!=ns:
        raise ValueError('inconsistent block dimensions')
    return dict(dimensions=[nx,ns,nc,nd],W=W,W_factor=wf,x_diagonal=[df*v for v in dx],
        s_diagonal=ds,c_diagonal=dc,d_diagonal=dd,J_c=jc,J_d=jd)


def jacobian_block(text,name):
    if f'ScaledMatrix "{name}"' not in text:
        a=triplet(text,name);a['row_scaling']=[1.]*a['shape'][0];return a
    if '_column_scaling' in text:raise ValueError('NLP column scaling unsupported')
    scale=vector(text,name+'_row_scaling')
    a=triplet(text,name+'_unscaled_matrix')
    if len(scale)!=a['shape'][0] or any(not math.isfinite(v) or v<=0 for v in scale):raise ValueError('invalid NLP row scaling')
    a['values']=[scale[i-1]*v for i,v in zip(a['rows'],a['values'])];a['row_scaling']=scale
    return a


def multiply(k,x):
    """Independent sparse block multiplication, summing repeated contributions."""
    nx,ns,nc,nd=k['dimensions'];offsets=[0,nx,nx+ns,nx+ns+nc];n=sum(k['dimensions'])
    if len(x)!=n: raise ValueError('vector dimension differs')
    y=[0.]*n
    def add(a,r,c,factor=1.,symmetric=False):
        for i,j,v in zip(a['rows'],a['columns'],a['values']):
            i=r+i-1;j=c+j-1;v*=factor;y[i]+=v*x[j]
            if symmetric and i!=j:y[j]+=v*x[i]
    add(k['W'],0,0,k['W_factor'],True)
    add(k['J_c'],offsets[2],0,symmetric=True);add(k['J_d'],offsets[3],0,symmetric=True)
    for offset,key in zip(offsets,('x_diagonal','s_diagonal','c_diagonal','d_diagonal')):
        for i,v in enumerate(k[key]):y[offset+i]+=v*x[offset+i]
    for i in range(ns):y[offsets[1]+i]-=x[offsets[3]+i];y[offsets[3]+i]-=x[offsets[1]+i]
    return y


def calls(text):
    """Read native matrix/RHS/solution triples inside one direction block.

Failed factorizations retain their matrix and RHS with solution=None. The caller
must independently check iteration coverage and native refinement events.
"""
    markers=list(re.finditer(r'CompoundVector "RHS\[ 0\]" with 4 components:',text))
    chunks=re.split(r'CompoundVector "RHS\[ 0\]" with 4 components:',text)[1:]
    regularizations=list(re.finditer(rf'Solving system with delta_x=({NUMBER}) delta_s=({NUMBER})\s+'
        rf'delta_c=({NUMBER}) delta_d=({NUMBER})',text))
    result=[]
    for rhs_marker,chunk in zip(markers,chunks):
        start=chunk.find('CompoundSymMatrix "KKT"')
        # Level 10 prints the compound RHS; the additional flat RHS report only
        # appears at higher verbosity. A MUMPS wrapper call also ends the matrix.
        endings=[m.start() for m in re.finditer(r'^Right hand side 0 in TSymLinearSolver:|^Calling MUMPS-[123] for ',chunk,re.M) if m.start()>start]
        end=min(endings) if endings else -1
        if start<0 or end<start: raise ValueError('missing KKT or native RHS delimiter')
        k=matrix(chunk[start:end]);rhs=[]
        for i,n in enumerate(k['dimensions']):
            v=vector(chunk[:start],f'RHS[ 0][{i}]')
            if len(v)!=n: raise ValueError('RHS block dimensions differ')
            rhs.extend(v)
        marker='CompoundVector "SOL[ 0]" with 4 components:'
        count=chunk.count(marker)
        if count>1: raise ValueError('multiple solutions per matrix')
        sol=None;residual=None
        if count:
            sol=[];tail=chunk.split(marker)[1]
            for i,n in enumerate(k['dimensions']):
                v=vector(tail,f'SOL[ 0][{i}]')
                if len(v)!=n: raise ValueError('solution block dimensions differ')
                sol.extend(v)
            residual=max((abs(a-b) for a,b in zip(multiply(k,sol),rhs)),default=0.)
        elif 'Factorization failed with retval =' not in chunk:
            raise ValueError('missing solution without explicit factorization failure')
        previous=[m for m in regularizations if m.start()<rhs_marker.start()]
        reg=[number(v) for v in previous[-1].groups()] if previous else None
        result.append(dict(matrix=k,rhs=rhs,solution=sol,residual_max=residual,regularization=reg))
    if not result: raise ValueError('no native augmented systems')
    return result


def iteration_blocks(lines,selected):
    """Stream selected beginning-of-iteration through direction-end blocks."""
    active=None;buffer=[];seen=set()
    for line in lines:
        begin=re.search(r'^\*\*\* Beginning Iteration (\d+) from the following point:',line)
        if begin:
            if active is not None:raise ValueError('unfinished selected direction')
            i=int(begin[1]);active=i if i in selected else None
            if active is not None:
                if i in seen:raise ValueError('duplicate selected iteration')
                seen.add(i);buffer=[]
        if active is not None:
            buffer.append(line)
            end=re.search(r'^\*\*\* Finding Acceptable Trial Point for Iteration (\d+):',line)
            if end:
                if int(end[1])!=active:raise ValueError('direction index differs')
                yield active,''.join(buffer);active=None;buffer=[]
    if active is not None or seen!=set(selected):raise ValueError('incomplete selected iteration coverage')


def bound_diagonal(slack,multiplier,positions,dimension):
    """Scatter z/t into a primal block using an explicit bound-index map."""
    if len(slack)!=len(multiplier) or len(slack)!=len(positions) or len(set(positions))!=len(positions):
        raise ValueError('ambiguous bound mapping')
    result=[0.]*dimension
    for t,z,i in zip(slack,multiplier,positions):
        if not (math.isfinite(t) and t>0 and math.isfinite(z) and z>=0 and 0<=i<dimension):
            raise ValueError('invalid bound state')
        if not math.isfinite(z/t):raise ValueError('nonfinite bound diagonal')
        result[i]+=z/t
    return result


def barrier_diagonals(text,maps,dimensions):
    """Use native internal positive slacks, never g(x) gaps or mu/t^2."""
    result={}
    for kind,n,multiplier in [('x',dimensions[0],'z'),('s',dimensions[1],'v')]:
        result[kind]=[0.]*n
        for side in ('L','U'):
            t=vector(text,f'curr_slack_{kind}_{side}');z=vector(text,f'curr_{multiplier}_{side}')
            term=bound_diagonal(t,z,maps[f'{kind}_{side}'],n)
            result[kind]=[a+b for a,b in zip(result[kind],term)]
    return result


def layout_maps(layout):
    """Original TNLP to internal free-variable/equality/inequality order.

Restricted to make_parameter fixed-variable handling, scalar constraints, finite
declared bounds inside Ipopt's default infinity thresholds and no dependency
removal. Native dimensions and vectors must independently verify these maps.
"""
    variables=sorted(layout['variables'],key=lambda x:x['column'])
    constraints=sorted(layout['constraints'],key=lambda x:x['row'])
    if [v['column'] for v in variables]!=list(range(1,len(variables)+1)) or [c['row'] for c in constraints]!=list(range(1,len(constraints)+1)):
        raise ValueError('incomplete original layout')
    for q in variables+constraints:
        lo,hi=q['lower'],q['upper']
        if any(v is not None and (not math.isfinite(v) or abs(v)>=1e19) for v in (lo,hi)) or (lo is not None and hi is not None and lo>hi):
            raise ValueError('unsupported bounds')
    for v in variables:
        if v['fixed']!=(v['lower'] is not None and v['lower']==v['upper']):raise ValueError('ambiguous fixed variable')
    free=[v['column']-1 for v in variables if not v['fixed']]
    eq=[];ineq=[]
    for c in constraints:
        if c['lower'] is None and c['upper'] is None:raise ValueError('unbounded constraint')
        (eq if c['lower'] is not None and c['lower']==c['upper'] else ineq).append(c['row']-1)
    maps=dict(free=free,equality=eq,inequality=ineq)
    for side,key in [('L','lower'),('U','upper')]:
        maps['x_'+side]=[j for j,i in enumerate(free) if variables[i][key] is not None]
        maps['s_'+side]=[j for j,i in enumerate(ineq) if constraints[i][key] is not None]
    return maps


def relative_gap(a,b):
    if len(a)!=len(b):raise ValueError('vector lengths differ')
    if any(not math.isfinite(v) for v in a) or any(not math.isfinite(v) for v in b):raise ValueError('nonfinite comparison')
    return max((abs(x-y)/max(1.,abs(x),abs(y)) for x,y in zip(a,b)),default=0.)


def entries(a):
    if len(a['rows'])!=len(a['columns']) or len(a['rows'])!=len(a['values']):raise ValueError('incomplete sparse entries')
    result={}
    for i,j,v in zip(a['rows'],a['columns'],a['values']):
        if not (isinstance(i,int) and isinstance(j,int) and 1<=i<=a['shape'][0] and 1<=j<=a['shape'][1] and math.isfinite(v)):
            raise ValueError('invalid sparse entry')
        result[i,j]=result.get((i,j),0.)+v
        if not math.isfinite(result[i,j]):raise ValueError('nonfinite accumulated entry')
    return result


def dictionary_gap(a,b):
    return max((abs(a.get(k,0.)-b.get(k,0.))/max(1.,abs(a.get(k,0.)),abs(b.get(k,0.))) for k in a.keys()|b.keys()),default=0.)


def audit_state(text,record,derivatives,layout,*,initial_row_scaling=None):
    """Validate native blocks against model derivatives and native bound states.

    Requires a separately checked initialization report with no x NLP scaling.
    Positive row scaling is read explicitly from native Jacobian wrappers and
    checked against the captured dual transformation. This checks the augmented matrix
before linear-solver transformations; it does not reproduce MUMPS factors.
"""
    maps=layout_maps(layout);free,eq,ineq=(maps[k] for k in ('free','equality','inequality'))
    nx,ns,nc=len(free),len(ineq),len(eq);dimensions=[nx,ns,nc,ns]
    p=record['scaled'];u=record['unscaled']
    native=calls(text)
    rc=native[0]['matrix']['J_c']['row_scaling'];rd=native[0]['matrix']['J_d']['row_scaling']
    if initial_row_scaling is not None and (rc!=initial_row_scaling['c'] or rd!=initial_row_scaling['d']):
        raise ValueError('native Jacobian scales differ from initialization')
    row_scale=[0.]*len(p['lambda'])
    for indices,scales in ((eq,rc),(ineq,rd)):
        if len(indices)!=len(scales):raise ValueError('row scaling dimensions differ')
        for i,v in zip(indices,scales):row_scale[i]=v
    matches=[relative_gap(vector(text,'curr_x'),[p['x'][i] for i in free]),
        relative_gap(vector(text,'curr_y_c'),[p['lambda'][i] for i in eq]),
        relative_gap(vector(text,'curr_y_d'),[p['lambda'][i] for i in ineq])]
    for side in ('L','U'):
        matches.append(relative_gap(vector(text,'curr_z_'+side),[p['z_'+side][free[i]] for i in maps['x_'+side]]))
    # Bound multiplier scaling gives the objective scale without truncating its
    # native six-digit printed report. Refuse an unidentifiable zero-dual state.
    choices=[(abs(u[key][i]),p[key][i]/u[key][i]) for key in ('z_L','z_U') for i in free if u[key][i]!=0]
    choices.extend((abs(u['lambda'][i]),row_scale[i]*p['lambda'][i]/u['lambda'][i]) for i in range(len(row_scale)) if u['lambda'][i]!=0)
    if not choices:raise ValueError('objective scaling not identifiable')
    scale=max(choices)[1]
    if not math.isfinite(scale) or scale<=0:raise ValueError('invalid objective scaling')
    matches.append(relative_gap(p['x'],u['x']))
    for key in ('z_L','z_U'):matches.append(relative_gap(p[key],[scale*v for v in u[key]]))
    matches.append(relative_gap(p['lambda'],[scale*v/r for v,r in zip(u['lambda'],row_scale)]))
    if max(matches)>1e-10:raise ValueError('native/callback state or scaling differs')
    sigma=barrier_diagonals(text,maps,dimensions)
    xlookup={i:j+1 for j,i in enumerate(free)};clookup={i:j+1 for j,i in enumerate(eq)};dlookup={i:j+1 for j,i in enumerate(ineq)}
    expected_w={};expected_c={};expected_d={}
    for (i,j),v in entries(derivatives['hessian']).items():
        if i-1 in xlookup and j-1 in xlookup:
            a,b=xlookup[i-1],xlookup[j-1];expected_w[max(a,b),min(a,b)]=scale*v
    for (i,j),v in entries(derivatives['jacobian']).items():
        if j-1 not in xlookup:continue
        if i-1 in clookup:expected_c[clookup[i-1],xlookup[j-1]]=row_scale[i-1]*v
        elif i-1 in dlookup:expected_d[dlookup[i-1],xlookup[j-1]]=row_scale[i-1]*v
    checks=[]
    for call in native:
        k=call['matrix'];reg=call['regularization']
        if k['dimensions']!=dimensions or reg is None or k['W_factor']!=1:raise ValueError('unexpected native system')
        if k['J_c']['row_scaling']!=rc or k['J_d']['row_scaling']!=rd:raise ValueError('NLP row scaling changed within direction')
        gaps=dict(W=dictionary_gap(entries(k['W']),expected_w),J_c=dictionary_gap(entries(k['J_c']),expected_c),J_d=dictionary_gap(entries(k['J_d']),expected_d),
            x_diagonal=relative_gap(k['x_diagonal'],[v+reg[0] for v in sigma['x']]),
            s_diagonal=relative_gap(k['s_diagonal'],[v+reg[1] for v in sigma['s']]),
            c_diagonal=relative_gap(k['c_diagonal'],[-reg[2]]*nc),d_diagonal=relative_gap(k['d_diagonal'],[-reg[3]]*ns))
        # Direction deltas are printed with %e (seven significant digits), while
        # matrix entries carry sixteen. Keep raw gaps and an explicit conservative
        # rounding allowance; do not silently loosen the derivative checks.
        excess={name:gaps[name] for name in ('W','J_c','J_d')}
        for name,sig,delta in [('x_diagonal',sigma['x'],reg[0]),('s_diagonal',sigma['s'],reg[1]),
                               ('c_diagonal',[0.]*nc,-reg[2]),('d_diagonal',[0.]*ns,-reg[3])]:
            excess[name]=max((max(0.,abs(a-(b+delta))-5.1e-7*abs(delta))/max(1.,abs(a),abs(b+delta))
                for a,b in zip(k[name],sig)),default=0.)
        if max(excess.values())>1e-9:raise ValueError('native augmented-system reconstruction differs: '+str(excess))
        checks.append(dict(gaps=gaps,gaps_after_regularization_print_allowance=excess,regularization=reg,
            residual_max=call['residual_max'],solved=call['solution'] is not None))
    d_minus_s=relative_gap(vector(text,'curr_s'),[p['g'][i] for i in ineq])
    return dict(passed=True,timing_eligible=False,iteration=record['iteration'],dimensions=dimensions,
        objective_scale=scale,state_gap=max(matches),constraint_slack_relative_gap=d_minus_s,
        nlp_row_scaling=dict(equality_changed=sum(v!=1 for v in rc),inequality_changed=sum(v!=1 for v in rd),minimum=min(row_scale,default=1.),maximum=max(row_scale,default=1.)),
        sigma_x_max=max(sigma['x'],default=0.),sigma_s_max=max(sigma['s'],default=0.),calls=checks)
