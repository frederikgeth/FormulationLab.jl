# Optional multiwinding coil-current elimination

`device_elimination=:all_transformer_currents` extends the existing ordinary
transformer pass with an optional local elimination of multiwinding coil
currents. The [non-star correspondence study](ivr_nwinding_nonstar.md) supplies
the physical test cases. The new pass removes 12 complex current coordinates
in each four-winding case, preserves physical recovery and all bounds, and
retains the explicit formulation when a numerical or structural guard fails.
It is not a new default. The subsequent [isolated lifted timing study](ivr_nwinding_timing.md)
finds a modest average benefit with material capped-case regressions.

## Algebra and implementation contract

After earlier coordinate and line transformations, partition a device's
recorded ampere-turn and leakage equations as

```math
A j+B x=0.
```

Here ``j`` contains all retained coil-current coordinates for that device, and
``x`` contains all other coordinates appearing in those equations. If ``A`` is
nonsingular, substitution ``j=Xx``, with ``X=-A^{-1}B``, gives an equivalent
feasible set in exact arithmetic. The implementation uses an LU solve, not an
explicit inverse. It does not fit a star, use a pseudoinverse, regularize leakage,
truncate small coefficients or infer coil circulation from terminal currents.

The assembly records the exact equation indices and coil-current observations
before adding winding-ground equations. A candidate requires a complete square
record, unique surviving current coordinates with unit signed coefficients,
and no equation consumed by an earlier pass. It then uses the existing local
block solver on the actual composed equations. Each device is atomic: a failed
guard retains all of its current coordinates and equations.

The numerical gates are conservative implementation choices, not proofs of
universal solver robustness:

1. Scale each equation by its largest current-block coefficient. Every row scale
   must be positive and finite; all composed data and solve coefficients must
   remain finite.
2. Require the equilibrated block's two-norm condition number to be at most
   ``10^8``. Solve for ``X`` without rank truncation.
3. Require a relative residual at most ``10^{-12}``, using elementwise maximum
   norms of the scaled arrays and denominator
   ``\max(1,\|A\|_{\max}\|X\|_{\max},\|B\|_{\max})``.
4. Require ``\max_i\sum_k|X_{ik}|\le10^8`` in the current solver coordinates.
   Row equilibration alone can hide a tiny independent leakage direction whose
   voltage-to-current reconstruction has enormous gain. This last guard retains
   such a block; it does not replace its coefficients with zeros. Its outcome
   can depend on numerical units, while the retained physical model is unchanged.

The original electrical model remains available for validation. Every KCL row,
coil and terminal current, power observation, current cap, apparent-power cap
and objective is evaluated through the reconstruction map. Explicit excitation
and finite-ground contributions are added exactly as before. Projection onto
retained coordinates and reconstruction satisfy the left-inverse identity on
the represented subspace, up to floating-point arithmetic. Reconstruction
residuals and independent SI checks remain necessary.

Zero or singular leakage keeps the original representation, including any
undetermined delta circulation. A two-/three-winding or ordinary transformer is
not converted into a four-winding approximation. The existing
`:transformer_currents` mode continues to eliminate only ordinary from-side
currents through unit pivots; `:off` remains the default. The new mode applies
both the old ordinary pass and the additional multiwinding block pass.

## Power-cost diagnostic panel

The panel repeats the preceding 112 physical/base cases: YYYY and both rolls
of YDYY/YYYD/DYYY, forward/reverse flow, absent/active winding caps, absent/present
winding-4 excitation, and 1/100 kVA assembly bases. Inputs and linear power-cost
objectives are identical to the prior study. All models use per-unit coordinates,
nominal transformer scaling, composed rows, 500 VA power auxiliaries and aligned
BMOPFTools nameplates. Three lifting choices and two elimination modes give
**672 solve attempts**.

Strict settings remain `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, `max_iter=500` and gradient-based NLP scaling. The first
accepted original-model endpoint supplies each case's objective and feasible-point
anchor. Objective agreement requires `atol=1e-7, rtol=1e-6`. Every candidate,
including one whose optimizer fails, is checked against that original feasible
point. Strict endpoints also require independent physical equations, own/full
membership, restriction witnesses and JSON reader round trip.

| Multiwinding representation | Lifting | Strict solves / all admissions |
|:--|:--|--:|
| Explicit currents | Off | 112/112 |
| Explicit currents | Powers | 112/112 |
| Explicit currents | Bounded observations | 112/112 |
| Eliminated currents | Off | 56/112 |
| Eliminated currents | Powers | 112/112 |
| Eliminated currents | Bounded observations | 112/112 |

All 56 unlifted failures occur with active winding caps: 55
`ALMOST_LOCALLY_SOLVED` and one `ITERATION_LIMIT`. None is admitted as strict
success, and none has a strict endpoint export. **Every failed candidate admits
the original feasible point.** All uncapped unlifted cases pass. Thus these
failures do not demonstrate a change in feasible set; they expose a numerical
robustness qualification. Both lifted variants pass every case under unchanged
settings, with maximum objective difference from the original anchor below
``1.234\times10^{-12}``.

The local equilibrated condition numbers are only 2.91–5.73, while maximum
absolute row sums of the reconstruction range from about 308 to 110,605.
Substitution expresses currents through differences of referred voltages and
can amplify cancellation in those differences. This is a plausible contributor
to the unlifted difficulty, not a demonstrated sole cause. The gain guard avoids
much more extreme substitutions but does not guarantee strict convergence on
the accepted blocks. Active caps, nonlinear observation structure and lifting
must remain separate experimental factors.

Each four-winding candidate removes 12 complex electrical coordinates and 12
complex circuit equations. Off/power lifting removes 24 real model variables.
Bounded-observation lifting removes only 12 or 24 real variables, because wider
composed observations can introduce additional auxiliaries. Primitive state
reduction alone therefore overstates the reduction of some final NLPs. These
runs are diagnostic, with no isolation or solver-time ranking.

## Recovery, bounds and exports

All **616 strict endpoints** pass the independent SI export audit, including
7,040 ungrounded KCL balances, 1,680 coil caps, 924 excitation contributions,
9,328 reconstructed terminal channels and 7,392 coil-power channels. All 560
individual cap-tightening and 616 pair-reactance-change certificates pass.
Physical export structures are identical across elimination modes, lifting,
flow directions and assembly bases within each connection/bound/excitation
case. All saved files pass a separate BMOPFTools reader comparison.

The audit also compares every strict endpoint with the **retained**
equality-treated BMOPFTools solution from the preceding study, after checking
identical physical inputs. These reference solves were not rerun. Maximum cost
gap is ``4.756\times10^{-11}``; maximum coil-current difference is
``4.670\times10^{-10}`` A. The 7,392 reference coil comparisons pass the unchanged
``2\times10^{-5}`` A absolute and ``10^{-6}`` relative tolerances. Maximum
independent KCL error is ``1.555\times10^{-11}`` A, leakage error
``1.963\times10^{-13}`` V and complex-loss identity error
``2.240\times10^{-9}`` VA. The SI audit thresholds are unchanged from the
preceding non-star audit.

Native JSON adds `device_elimination` and `device_elimination_report` metadata.
The report contains selected and retained device IDs, refusal reasons, consumed
rows, removed coordinate counts and accepted-block condition, residual and
reconstruction-gain diagnostics. Physical SI variables retain their existing
names and meanings; eliminated quantities are reconstructed, not omitted.

The **5,375 new regression assertions** cover arbitrary-coordinate algebraic
identities, atomic refusal, zero/singular/weak leakage, two-/three-winding cases,
fixed taps, finite grounding, load updates and unchanged ordinary-transformer
behavior. An independently constructed tapped delta/wye point tests every coil's
current and apparent-power bound individually. Strict regression solves use the
lifted variants; the optional panel retains the unlifted optimizer failures.

During development, a nonfinite preflight objective initially stopped JSON
serialization; it is now represented as null. The initial tests also exposed
the missing reconstruction-gain guard and incorrectly compared model-owned JuMP
variables across independent builds. Original scripts/logs and the corrections
remain in the external archive `NWINDING_ELIMINATION_20261006`; no physical or
solver acceptance threshold was relaxed.

## Use and next experiment

```julia
build = build_opf(input, IVRNLP(
    device_elimination=:all_transformer_currents,
    lifting=:powers,
    transformer_nameplate=:bmopftools);
    optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(
    print_level=0, tol=1e-10, constr_viol_tol=1e-10,
    acceptable_iter=0, bound_relax_factor=0.))
@assert result.solve.optimal && physical_residuals(input, result).passed
build.numerical_diagnostics[:device_elimination_report]
```

This opt-in is a candidate for testing with power lifting, not a replacement for
the explicit-current reference. Inspect retained-device reasons before assuming
a reduction occurred. Reproduce the regression and complete diagnostic panel:

```sh
julia --project=test test/ivr_nwinding_elimination_tests.jl
julia --project=test examples/benchmark_ivr_nwinding_elimination.jl /tmp/nwinding-elimination/report.json
```

The [subsequent timing assessment](ivr_nwinding_timing.md) compares accepted lifted
candidates by isolated Ipopt wall time, excluding compilation, and examines
Jacobian/Hessian growth and separate factorization diagnostics. Keep singular
fallbacks, unlifted failures and slower options. No speed recommendation follows
solely from the smaller electrical state.
