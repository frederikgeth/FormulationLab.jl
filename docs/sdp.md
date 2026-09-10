# Dense IVRSDP reference

Let z contain scaled terminal voltages and device channel currents. Current bases
are S_b/V_b, impedance bases V_b²/S_b. The first implementation uses one voltage
base, taken from the largest source magnitude, and a user-specified VA base.

Line equations, nodal current balance, constant-impedance current laws, and fixed
source phasor ratios are homogeneous linear equations A z = 0. Grounded voltage
coordinates are removed exactly. With an orthonormal nullspace basis N, z=N y.
The implementation lifts H=y yᴴ and drops only its rank-one requirement:

```math
H \succeq 0, \qquad
\widehat{(a z)\overline{(b z)}} = (aN)H(bN)^H.
```

One source squared magnitude is fixed. The source's other phasors are related to
that anchor by exact complex ratios in A. This avoids imposing a singular
multi-phase fixed-source block directly on the PSD cone.

A line uses v_f-v_t=Z i_series. Endpoint currents are
`i_from=i_series+Y_from*v_from` and `i_to=-i_series+Y_to*v_to`.
Both enter KCL at their declared terminals. Both endpoint currents and powers
receive declared limits, including linecode ratings when not overridden.

For a connection incidence D, channel voltages are D v and terminal currents
are Dᵀ i_channel. Wye loads with a trailing explicit neutral, delta loads, and
single-phase terminal-pair loads therefore retain their physical connections.
KCL is imposed at every non-grounded terminal, including floating neutrals.
Ideal ground connections supply unrestricted ground current; source-ground
current allocation and its ampacity are explicitly unsupported.

Constant-power loads fix the lifted channel power. Constant-impedance loads use
the linear current law i=conj(S_nom)/V_nom² * v, including at zero voltage.
Generator/source power boxes and costs are affine in lifted powers. Current
limits are affine in lifted squared current; apparent-power limits are SOCs.

The linear network equations are eliminated before lifting. This is a dense
current–voltage relaxation with that strengthening, not an assertion that every
voltage-only or branch-flow SDP is identical. Any exact feasible electrical state
in this subset maps to a rank-one feasible point. The reverse implication requires
rank-one recovery and verification, which this release does not certify.

`SDPBuild` exposes the reduced moment matrix, nullspace, terminal indices, and
lifted power expressions. `SDPResult.relaxed_powers` is in W+jvar and is distinct
from `voltage_candidate` (V), reconstructed from the dominant eigenvector and
aligned to the source. `rank_ratio` is the second-largest nonnegative eigenvalue
divided by the largest; it is a diagnostic, not a feasibility test. An auxiliary
current direction can affect this ratio independently of voltage recoverability.

`solver_objective_bound` is the solver's numerical report. Neither it nor the
primal objective is labeled rigorously certified. No upper bound or AC gap is
reported. Failed/non-publishable solves return NaN numerical fields.

The reference is verified against analytical loaded two-bus solutions, a floating
neutral with mutual impedance, a delta load, reversed branch orientation, a binding
generator capability limit, current-limit infeasibility, and impedance loads.
The same suite can run with Clarabel or optional MosekTools.
