"""Native Ipopt initial-state comparison under constraint-row scaling only.

Requires fixed objective/column scales, separately verified from callback arrays.
A passed comparison is coordinate equivalence within tolerance, not bitwise
identity, global convergence, or timing evidence.
"""
import math
import ivr_native_kkt as K

NAMES=['curr_x','curr_s','curr_y_c','curr_y_d']+[
    f'curr_{kind}_{side}' for kind in ['slack_x','z','slack_s','v'] for side in ['L','U']]


def read_initial(lines,layout):
    prefix=[];block=[];started=False;ended=False
    for line in lines:
        if line.startswith('*** Beginning Iteration 0 from the following point:'):started=True
        if started:
            if line.startswith('*** Solving the Primal Dual System for Iteration 0:'):
                ended=True;break
            block.append(line)
        else:prefix.append(line)
    if not started or not ended:raise ValueError('complete initial state unavailable')
    prefix=''.join(prefix).split('DenseVector "original ')[0]
    if 'No x scaling provided' not in prefix:raise ValueError('column scaling unsupported')
    maps=K.layout_maps(layout)
    scales={tag:([1.]*len(maps[key]) if f'No {tag} scaling provided' in prefix else K.vector(prefix,f'{tag} scaling vector'))
            for tag,key in [('c','equality'),('d','inequality')]}
    block=''.join(block)
    state={name:K.vector(block,name) for name in NAMES}
    result=dict(state=state,scales=scales,maps=maps)
    _validate(result)
    return result


def _validate(data):
    state=data['state'];scales=data['scales'];maps=data['maps']
    sizes=dict(curr_x=len(maps['free']),curr_s=len(maps['inequality']),
               curr_y_c=len(maps['equality']),curr_y_d=len(maps['inequality']))
    for tag,key in [('c','equality'),('d','inequality')]:
        if len(scales[tag])!=len(maps[key]) or any(not math.isfinite(v) or v<=0 for v in scales[tag]):
            raise ValueError('invalid row scales')
    for kind,mult in [('x','z'),('s','v')]:
        for side in ['L','U']:
            sizes[f'curr_slack_{kind}_{side}']=sizes[f'curr_{mult}_{side}']=len(maps[f'{kind}_{side}'])
            K.bound_diagonal(state[f'curr_slack_{kind}_{side}'],state[f'curr_{mult}_{side}'],
                             maps[f'{kind}_{side}'],sizes[f'curr_{kind}'])
    for name,size in sizes.items():
        if len(state[name])!=size or any(not math.isfinite(v) for v in state[name]):
            raise ValueError('invalid initial vector '+name)


def compare(original,target,*,atol=1e-10):
    """Map s by A=R_new/R_old, and y/v by inverse A; inspect native states."""
    if not math.isfinite(atol) or atol<0:raise ValueError('invalid tolerance')
    _validate(original);_validate(target)
    if original['maps']!=target['maps']:raise ValueError('layouts differ')
    maps=original['maps'];a=original['state'];b=target['state']
    ratios={k:[n/o for o,n in zip(original['scales'][k],target['scales'][k])] for k in ['c','d']}
    if any(not math.isfinite(r) or r<=0 for v in ratios.values() for r in v):raise ValueError('invalid scale ratio')
    expected={k:list(v) for k,v in a.items()}
    expected['curr_s']=[v*r for v,r in zip(a['curr_s'],ratios['d'])]
    for tag in ['c','d']:
        expected['curr_y_'+tag]=[v/r for v,r in zip(a['curr_y_'+tag],ratios[tag])]
    products={};curvature={}
    for side in ['L','U']:
        factors=[ratios['d'][i] for i in maps['s_'+side]]
        t='curr_slack_s_'+side;v='curr_v_'+side
        expected[t]=[x*r for x,r in zip(a[t],factors)]
        expected[v]=[x/r for x,r in zip(a[v],factors)]
        products[side]=K.relative_gap([x*y for x,y in zip(a[t],a[v])],[x*y for x,y in zip(b[t],b[v])])
        curvature[side]=K.relative_gap([z/t/r**2 for z,t,r in zip(a[v],a[t],factors)],
                                      [z/t for z,t in zip(b[v],b[t])])
    gaps={k:K.relative_gap(expected[k],b[k]) for k in NAMES}
    return dict(coordinate_equivalent=max([*gaps.values(),*products.values(),*curvature.values()])<=atol,
                state_gaps=gaps,complementarity_gaps=products,barrier_curvature_gaps=curvature,
                tolerance=atol,timing_eligible=False)
