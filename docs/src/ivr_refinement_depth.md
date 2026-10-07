# Refinement depth on retained KKT systems

## Question and predeclared scope

The [residual-magnitude study](ivr_kkt_residuals.md) retained seven failures of
the mixed criterion with absolute allowance ``10^{-12}`` after two external
refinement steps. Do additional corrections resolve them, or has the computed
direction reached a rounding limit? This experiment keeps the stored matrix,
right-hand side, factorization and pivot policy fixed along each trajectory.
It does not change Ipopt's production refinement settings.

The four source systems are precisely those implicated in the seven failures:

| Source system | Original selected failures |
|:---|:---|
| Explicit currents, powers-only, iteration 0, call 0 | Automatic preprocessing, native RHS, both row conventions |
| Explicit currents, broad observations, iteration 22, call 0 | Supplied-order/unscaled preprocessing: native RHS in both conventions; manufactured RHS in unit-row coordinates |
| Explicit currents, broad observations, iteration 22, call 1 | Supplied-order/unscaled preprocessing, manufactured RHS in unit-row coordinates |
| Eliminated currents, broad observations, iteration 0, call 0 | Supplied-order/unscaled preprocessing, native RHS in unit-row coordinates |

For each source system the full earlier control design is retained: two
preprocessing regimes, two row conventions and two RHSs. This gives 16 fresh
factorizations and 32 RHS trajectories. Stages 0 through 8 are all recorded,
giving 288 vectors. Selection is informed by previous failures, not an independent
sample. The powers-only row-convention pair is an identity, and the two broad
iteration-22 calls repeat a matrix for their manufactured RHSs. These entries
remain explicit and must not be counted as independent evidence.

## Correction arithmetic and acceptance criteria

Let ``\mathcal F^{-1}`` denote a triangular solve using the one retained MUMPS
factorization, rather than an exact matrix inverse. Each correction performs

```math
r_k=b-Kq_k\quad\text{(256-bit accumulation)},\qquad
d_k=\mathcal F^{-1}\operatorname{Float64}(r_k),\qquad
q_{k+1}=\operatorname{Float64}(q_k+d_k).
```

The factorization and correction solve use Float64. Updates use ordinary
Float64 addition, without compensation. Stage 0 is the initial solution, stage 2
is the earlier baseline, and stage 8 is the predeclared endpoint. There is no
early stopping or retrospective choice of a best stage. MUMPS internal refinement
remains disabled and its pivot threshold remains ``10^{-6}``. Supplied-order
pairs reuse the original automatic effective order; their effective orders and
disabled scaling are checked.

The strict componentwise criterion remains ``\eta\le10^{-10}``. The complete
mixed grid retains absolute allowances
``a\in\{0,10^{-16},10^{-14},10^{-12},10^{-10}\}`` in reference KKT row units.
Weights are one in original coordinates and ``T_{ii}`` after the retained
congruence ``\widehat K=TKT``. These are neither SI feasibility tolerances nor
production acceptance settings. The previously failing results are preserved.

All stage-0/1/2 metrics and stage-2 directions must reproduce the previous study
exactly. Later update sizes are evaluated after mapping directions back to
original coordinates, with componentwise normalization by
``\max(1,|q_{k,i}|,|q_{k-1,i}|)``. Exact repeated vectors are recorded separately.
For manufactured RHSs, ``q_i^*=\sin(i)`` supplies a planted reference direction.
Since ``b^*=\operatorname{Float64}(Kq^*)`` is rounded, ``q^*`` need not be the exact
solution of the stored system. Its discrepancy includes RHS rounding and is not
a certified forward error. Changes in a native direction are not a forward-error
estimate either. The archived driver's field `manufactured_forward_gap` stores
this reference discrepancy; its legacy label must not be read as a certification.

## Executable tutorial

The diagnostic helper keeps two corrections as its default. Explicitly request
more stages and retained vectors for an experiment:

```@example refinement_depth
using LinearAlgebra
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_kkt_factor.jl"))
const Refine = IVRKKTOfflineFactor
A = [4.0 1 1; 1 -2 0.5; 1 0.5 3]
target = [1.0, -2, 0.5]
ij = [(i,j) for i in 1:3 for j in 1:i]
data = Dict("dimension"=>3, "rows"=>first.(ij), "columns"=>last.(ij),
    "values"=>[A[i,j] for (i,j) in ij], "rhs"=>A*target,
    "coordinate_map"=>ones(3))
z = Refine.input(data)
summary = mktempdir() do dir
    bridge = Refine.bridge(dir)
    baseline = Refine.factor_solve(bridge, z, z.a, [z.b])
    extended = Refine.factor_solve(bridge, z, z.a, [z.b];
        refinement_steps=8, record_solutions=true)
    @assert baseline.passed && extended.passed
    @assert extended.rhs[1].stages[3].solution == baseline.rhs[1].solution
    @assert extended.rhs[1].solution ≈ target
    (baseline_stage=2, final_stage=8, retained_vectors=length(extended.rhs[1].stages))
end
summary
```

`refinement_steps=0` requests just the initial solve. Negative depths and
mismatched reference/RHS counts are refused. Retained stage vectors are independent
copies; they are not views of a mutable final solution. The 38 factor-helper
calibration assertions cover these controls and the existing dense, sparse,
inertia, ordering and malformed-input checks. The observation-elimination and
residual helpers retain their 27 and 16 passing assertions.

## Results

All 16 factorizations succeed. Every trajectory reproduces its original first
three stage metrics and stage-2 direction exactly. Factor reports and effective
orders also reproduce the earlier experiment. The identity row-convention
controls match at every stage.

| External corrections | Strict passes, all 32 | Mixed passes, ``a=10^{-16}`` | Mixed passes, ``a=10^{-12}`` | Selected seven passing at ``a=10^{-12}`` |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 2 | 0 |
| 1 | 11 | 16 | 19 | 0 |
| 2: prior baseline | 16 | 25 | 25 | 0 |
| 3 | 20 | 30 | 32 | 7 |
| 4 | 20 | 32 | 32 | 7 |
| 5 | 20 | 32 | 32 | 7 |
| 6 | 20 | 32 | 32 | 7 |
| 7 | 20 | 32 | 32 | 7 |
| 8: declared endpoint | 21 | 32 | 32 | 7 |

One additional correction resolves all seven selected ``10^{-12}`` mixed misses.
Four corrections suffice for every trajectory at each nonzero absolute allowance
in the declared grid. The original two-step failures remain unchanged in the
archive; these are new results at greater correction depth. At stage 8, 11 of 32
directions still fail the strict criterion. Four of the selected seven pass the
strict criterion from stage 3 onward, and three continue to fail it.

Selected mixed ratios at the baseline and next correction are:

| Selected trajectory | Stage 2 | Stage 3 |
|:---|---:|---:|
| Powers-only automatic native, either row convention | 1.0071 | ``5.59\times10^{-5}`` |
| Broad iteration 22, supplied order, original-row native | 8.5263 | 0.00503 |
| Broad iteration 22, supplied order, unit-row native | 7.8439 | 0.03138 |
| Broad iteration 22, supplied order, unit-row manufactured, either call | 1.2466 | 0.00346 |
| Eliminated-current broad iteration 0, supplied order, unit-row native | 3.2618 | 0.00776 |

Thus these misses were not an irreducible residual floor after two steps. More
corrections improve the numerical result without changing the factorization or
pivot policy. This does not establish that all systems would benefit similarly.

The two duplicated difficult manufactured controls have original-coordinate
reference discrepancy ``2.23\times10^{-7}`` at stage 2 and
``1.23\times10^{-12}`` at stage 8. Across all manufactured controls the maximum
discrepancy falls from ``2.23\times10^{-7}`` to ``1.20\times10^{-9}`` at stage 3,
then ``1.81\times10^{-11}`` at stage 4 and remains at that level at stage 8.
Different controls determine these maxima; they do not describe a single
trajectory. RHS rounding prevents interpreting the plateau as a pure solver
forward-error floor.

Sixteen of the 32 stage-8 vectors repeat an earlier vector exactly. None of the
seven selected trajectories repeats exactly within the recorded window, despite
their mixed-ratio plateaus. One non-selected native control exhibits an exact
two-cycle at stages 5–8. The largest normalized stage-8 update across the panel
is ``2.78\times10^{-17}``. No strict or ``10^{-12}`` mixed pass reverses to a fail
within the window, although one trajectory's mixed ratio increases at a later
stage. Residual maxima and threshold crossings alone therefore do not establish
monotone convergence or exact stagnation.

## Independent checks and implications

An independent 80-digit decimal audit verifies all 32 final vectors and every
stage of the seven originally failing trajectories: 88 vectors after removing
overlap. It checks full residual maxima, strict errors, all five grid failure
counts and reported worst-row values. Original row provenance remains attached
to the mixed worst rows at each stage. Source matrices, factor outputs, all 288
stage vectors, protocol, hashes and planning records remain outside Git in
`KKT_REFINEMENT_DEPTH_20261007`.

The two-correction baseline was insufficient for the selected mixed criterion.
This supports further investigation of residual evaluation and refinement policy,
but not changing production defaults from this diagnostic panel. Residuals here
use 256-bit accumulation outside Ipopt, and the acceptance criteria differ from
Ipopt's complete primal-dual refinement test. No nonlinear solves, physical-result
exports, condition estimates or timing evidence are produced. Timing remains
deferred and every formulation option is preserved.

The next useful control separates residual-accumulation precision from correction
depth on the same retained systems. Keep factorization and updates fixed, compare
Float64 and 256-bit residual accumulation, and independently assess both using
the same higher-precision residual criteria. Only then consider whether a
representable native Ipopt intervention merits nonlinear validation.

The [residual-precision control](ivr_residual_precision.md) now makes that
comparison within each factorization. Both accumulation modes reach all declared
nonzero mixed criteria by four corrections on this panel, although their later
updates and strict classifications differ. This narrows the case for a native
refinement-policy experiment without changing production settings.
