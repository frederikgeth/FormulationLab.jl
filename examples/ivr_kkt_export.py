"""Canonical lower-triangle export for independent native KKT factorization."""
import math
from ivr_native_kkt import entries, multiply, relative_gap
from ivr_kkt_row_units import coordinate_map


def canonical(call):
    k = call['matrix']
    nx, ns, nc, nd = k['dimensions']
    if ns != nd or min(nx, ns, nc, nd) < 0:
        raise ValueError('invalid block dimensions')
    n = nx+ns+nc+nd
    if not 0 < n < 2**31:
        raise ValueError('32-bit matrix dimension required')
    values = {}
    def add(i, j, value):
        if not 1 <= j <= i <= n or not math.isfinite(value):
            raise ValueError('invalid lower-triangle entry')
        values[i,j] = values.get((i,j), 0.) + value
        if not math.isfinite(values[i,j]):
            raise ValueError('nonfinite sum')
    for (i,j), value in entries(k['W']).items():
        add(i,j,k['W_factor']*value)
    for offset,key in [(nx+ns,'J_c'),(nx+ns+nc,'J_d')]:
        for (i,j),value in entries(k[key]).items():
            add(offset+i,j,value)
    for offset,key in zip([0,nx,nx+ns,nx+ns+nc],
                          ['x_diagonal','s_diagonal','c_diagonal','d_diagonal']):
        for i,value in enumerate(k[key],1):
            add(offset+i,offset+i,value)
    for i in range(1,ns+1):
        add(nx+ns+nc+i,nx+i,-1.)
    keys=sorted(values)
    out=dict(schema='FormulationLab.native_kkt_factor_input.v1',dimension=n,
             rows=[i for i,j in keys],columns=[j for i,j in keys],
             values=[values[key] for key in keys],rhs=list(call['rhs']),
             native_solution=call['solution'],coordinate_map=coordinate_map(k,[1.]*nc,[1.]*nd))
    for key in ('rhs','native_solution'):
        v=out[key]
        if v is not None and (len(v)!=n or any(not math.isfinite(x) for x in v)):
            raise ValueError('invalid '+key)
    gaps=[]
    for probe in range(3):
        x=[math.sin((i+1)*(probe+1)) for i in range(n)]
        y=[0.]*n
        for (i,j),a in values.items():
            y[i-1]+=a*x[j-1]
            if i!=j:y[j-1]+=a*x[i-1]
        gaps.append(relative_gap(y,multiply(k,x)))
    if max(gaps)>1e-9:
        raise ValueError('canonical matrix action differs')
    out['canonical_action_gap']=max(gaps)
    return out
