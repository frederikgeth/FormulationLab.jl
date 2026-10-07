# Residual-accumulation precision control

The subsequent [native refinement-policy calibration](ivr_native_refinement_policy.md)
verifies Ipopt's actual minimum-correction control and printed residual-ratio
conventions on a small nonlinear problem, before attempting OPF transfer.

## Question and scope

The [refinement-depth experiment](ivr_refinement_depth.md) resolved all seven
selected mixed-tolerance misses with one extra correction, but its correction
residuals used 256-bit accumulation. Can Float64 residual accumulation reproduce
that result when everything else is held fixed?

This control retains the same four source systems, both preprocessing regimes,
both row conventions and both RHSs. Each of the 16 factorization handles serves
four trajectories: native and manufactured RHSs with 256-bit residuals, followed
by the same RHSs with Float64 residuals. Both modes start with identical computed
directions. Eight corrections produce nine stored stages per trajectory:
64 trajectories and 576 vectors altogether.

The systems were selected because of previous failures. Powers-only row-unit
identity pairs and repeated manufactured systems remain explicit, rather than
being counted as independent networks. This is a control of one accumulation
order, not a reconstruction of Ipopt's internal primal-dual residual evaluation.

## The isolated intervention

Let ``\operatorname{mv}_p(K,q)`` accumulate a symmetric matrix-vector product in
the stored canonical lower-triangle triplet order, using precision ``p``. Every
off-diagonal coefficient contributes to both affected rows. The two correction
right-hand sides are

```math
\widehat r_{256}=\operatorname{Float64}\!\left(b-\operatorname{mv}_{256}(K,q)\right),
\qquad
\widehat r_{64}=\operatorname{fl}_{64}\!\left(b-\operatorname{mv}_{64}(K,q)\right).
```

The correction solves and updates remain Float64:

```math
d=\mathcal F^{-1}\widehat r_p,\qquad q^+=\operatorname{fl}_{64}(q+d).
```

The same MUMPS factorization ``\mathcal F`` serves both modes. Pivot threshold,
ordering/scaling choices, disabled internal refinement, RHSs and eight-correction
depth are unchanged. There is no compensated sum, sparse-BLAS reordering,
early stopping or best-stage selection. The high-precision arm must reproduce
every vector and metric from the previous depth experiment exactly.

Crucially, **both modes are assessed with the same 256-bit residual evaluation**.
Their strict componentwise threshold remains ``10^{-10}``, and the additional
absolute grid remains ``0,10^{-16},10^{-14},10^{-12},10^{-10}`` in reference KKT
row units. Under row congruence the absolute allowances use weights ``T_{ii}``.
A small Float64-computed correction residual is not itself an acceptance test.

Manufactured-reference discrepancies compare mapped directions with the planted
``q_i^*=\sin(i)``. Rounding the manufactured RHS means this reference need not
exactly solve the stored Float64 system. The discrepancy is not a certified
forward error, and a native direction change is not a forward-error estimate.

## Cancellation example and diagnostic API

This executable example uses the symmetric matrix action from the diagnostic
helper. Its first row accumulates ``10^{16}+1-10^{16}`` in that order. Float64
loses the middle contribution; 256-bit accumulation retains it.

```@example residual_precision
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_kkt_factor.jl"))
const Precision = IVRKKTOfflineFactor
rows = [1,2,2,3,3,3]; columns = [1,1,2,1,2,3]
values = [1e16,1.0,2.0,-1e16,0.0,3.0]
q = ones(3); b = zeros(3)
high = Precision.correction_residual(3,rows,columns,values,q,b)
low = Precision.correction_residual(3,rows,columns,values,q,b;precision=:float64)
@assert high[1] == -1.0 && low[1] == 0.0
@assert high == Precision.metrics(3,rows,columns,values,q,b).residual
(high_precision_first_residual=high[1], float64_first_residual=low[1])
```

For factorization experiments, `factor_solve` accepts a single
`residual_precision=:bigfloat` or `:float64`, or one symbol per RHS. For example,
`residual_precision=[:bigfloat,:float64]` with `[b,b]` compares both modes using
one factor handle. `:bigfloat` remains the default, with two corrections unless
`refinement_steps` is explicitly set. `record_solutions=true` retains all stage
vectors. Quality metrics always use 256-bit accumulation, even when corrections
use Float64. Unsupported modes or mismatched mode counts are refused.

The factor-helper and cancellation calibration has 56 passing assertions;
the observation-elimination and residual diagnostic regressions have 27 and 16.

## Results

All 16 factorizations succeed. All 288 high-precision stage vectors and metrics
reproduce the preceding experiment exactly, and every precision pair has an
identical initial direction. The powers-only identity row-convention controls
match at every stage in both modes.

| Corrections | Strict passes: 256-bit | Strict passes: Float64 | Mixed passes at ``a=10^{-12}``: 256-bit | Mixed passes at ``a=10^{-12}``: Float64 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 2 | 2 |
| 1 | 11 | 9 | 19 | 17 |
| 2 | 16 | 16 | 25 | 27 |
| 3 | 20 | 20 | 32 | 32 |
| 4 | 20 | 20 | 32 | 32 |
| 5 | 20 | 20 | 32 | 32 |
| 6 | 20 | 20 | 32 | 32 |
| 7 | 20 | 20 | 32 | 32 |
| 8 | 21 | 20 | 32 | 32 |

Counts in each column refer to the same 32 trajectories. Both modes pass all seven
originally selected ``10^{-12}`` mixed misses by stage 3. Float64 already passes
the two duplicated powers-only entries at stage 2; this near-threshold difference
does not establish an overall precision ranking.

The complete absolute grid gives:

| Absolute allowance | Stage 2: 256-bit | Stage 2: Float64 | Stage 8: 256-bit | Stage 8: Float64 |
|---:|---:|---:|---:|---:|
| 0: strict criterion | 16 | 16 | 21 | 20 |
| ``10^{-16}`` | 25 | 25 | 32 | 32 |
| ``10^{-14}`` | 25 | 25 | 32 | 32 |
| ``10^{-12}`` | 25 | 27 | 32 | 32 |
| ``10^{-10}`` | 32 | 30 | 32 | 32 |

At stage 3 the grid counts are identical: ``(20,30,31,32,32)``. From stage 4
onward, both modes pass every nonzero allowance. Thus **256-bit correction
residuals are not required to reach the declared mixed criteria on these retained
systems at this depth**. That statement is limited to the tested accumulation
order, matrices and RHSs. It does not establish that Float64 suffices for other
systems, or that Ipopt uses this particular order.

Precision still affects the later trajectory. At stage 8, 16 high-precision
vectors exactly repeat an earlier vector; none of the Float64 vectors does.
All 32 Float64 trajectories have at least one increase in their ``10^{-12}`` mixed ratio,
compared with one high-precision trajectory. Neither mode has a strict or
``10^{-12}`` mixed pass-to-fail reversal in this window. The largest normalized
stage-8 update is ``2.78\times10^{-17}`` with high-precision residuals and
``1.80\times10^{-11}`` with Float64 residuals. Restricting to native RHSs, the
corresponding maxima are ``2.78\times10^{-17}`` and ``1.28\times10^{-12}``.
These differences indicate greater late-stage movement under this Float64
accumulation order, not a failure of the declared mixed acceptance tests.

The maximum manufactured-reference discrepancy at stage 8 is
``1.81\times10^{-11}`` with high precision and ``2.68\times10^{-11}`` with Float64.
Individual comparisons need not favor high precision: the duplicated difficult
manufactured controls reach about ``1.23\times10^{-12}`` and
``1.17\times10^{-12}``, respectively. The planted-reference/RHS-rounding
qualification applies to all these quantities.

The single additional strict pass at stage 8 under high precision belongs to
explicit-current broad iteration 22, call 1, supplied-order/unscaled preprocessing
and the original-row native RHS. Eleven strict failures remain under high
precision and twelve under Float64. The original classifications and every new
failure are retained; passing a mixed criterion does not relabel strict failures.

## Independent verification and next control

The independent 80-digit decimal audit checks all 64 endpoint vectors and every
stage of the seven selected failure entries in both modes, giving 176 vectors
after removing overlap. Checks include full residual maxima, strict errors,
all five mixed-grid failure counts and reported worst-row values. All 576 vectors,
matrix/RHS and prior-result hashes, provenance, the frozen protocol and planning
documents remain outside Git in `KKT_RESIDUAL_PRECISION_20261007`.

The earlier benefit from additional corrections does not depend on 256-bit
correction residuals for this panel. This motivates a **native refinement-policy
control**, rather than assuming that higher precision is necessary. First
calibrate the native residual convention and minimum-correction setting on a
small nonlinear problem. Any subsequent OPF comparison must retain per-unit
coordinates, physical/export gates, objective and initialization controls, and
count actual corrections and recovery events.

The present test neither reproduces native primal-dual refinement nor establishes
a nonlinear benefit. No production option, default or best-evidence formulation
recommendation changes. No new optimization solve, physical JSON export or timing
result is produced. Timing remains deferred; all formulation options stay available.
