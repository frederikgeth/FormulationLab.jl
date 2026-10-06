# Coincident voltage limits as exact equalities

The [fixed-Q study](ivr_nwinding_equalities.md) identified opposing inequalities
as a source of nonunique multipliers and unreliable stopping accuracy. A source
audit found an analogous representation in native bus-voltage bounds. The new
opt-in `coincident_voltage_bounds=:equality` replaces an exactly coincident
positive lower/upper voltage pair with one magnitude equality. The default
`:separate` representation remains available and unchanged.

## Mathematical scope

For a complex voltage observation ``u=a^{\mathsf T}v`` and a positive declared
limit ``V``, the two inequalities

```math
\frac{|u|^2}{V^2}\geq1,\qquad\frac{|u|^2}{V^2}\leq1
```

have exactly the same feasible set as ``|u|^2/V^2=1``. Their opposing active
gradients permit a common offset in the two inequality multipliers without
changing stationarity. The equality removes that pair's redundancy. It adds
no voltage approximation, selects no phase angle and changes no engineering
limit, coordinate scale or physical recovery equation.

Matching requires the same bus, voltage family, channel, electrical observation
row and exactly equal finite positive bounds. Supported paired families are
phase-ground (`v`), phase-neutral (`vpn`), phase-phase (`vpp`) and positive-sequence
(`vpos`). A difference of even one floating-point step prevents matching. Proper
intervals and upper-only constraints retain their existing representation.

Zero limits retain the original real/imaginary component equalities: a squared
norm equality at zero has a vanishing gradient. Observations composed entirely
of explicitly fixed source coordinates retain their original inequalities;
adding a magnitude equality there would add a redundant fixed-source equation.
Diagnostics label such matched pairs `fixed_source_pair_retained` rather than
claiming a rewrite. No bound is dropped merely because it appears inactive.

This is a local representation option, not a general rank-revealing presolver.
Different voltage declarations can become identical after grounding; device
physics can also imply a fixed voltage. Those dependencies are not removed.
An equality representation can expose an overdetermined or otherwise dependent
system, so the separate-inequality control and strict admission tests remain
necessary. No universal regularity or global-optimality claim follows.

The subsequent [power-cost and dependency study](ivr_voltage_dependencies.md)
tests these limitations and adds `:guarded_equality`. That option shares identical
normalized affine observations and retains inequalities when single-unknown
circuit propagation certifies fixed coordinates. The results below describe the
original `:equality` experiment; they are not a general recommendation to replace
every coincident pair.

## Bound-representation audit

The review inspected the exact-IVR construction paths rather than assuming that
all fixed quantities use the same representation:

| Quantity | Current handling | Remaining qualification |
|:--|:--|:--|
| Generator P/Q boxes | Explicit dispatch-variable bounds; equal endpoints handled by Ipopt's fixed-variable treatment | Mutable boxes preserve the defining power equations |
| IBR and voltage-source P/Q boxes | Equal endpoints emit a power equality | Dependencies on other device equations remain possible |
| Coupled IBR DC active power | Equal endpoints emit a total-power equality | No general circuit-rank certificate |
| Grid-forming internal voltage | Magnitude equality; directly fixed source observations are checked separately | Other implied-voltage dependencies remain |
| Voltage-law load magnitude | Equal engineering bounds evaluate the law at a constant magnitude | Bus operating bounds still need enforcement |
| Positive coincident bus voltage | Separate inequalities by default; new optional equality | Local matching only |
| Zero voltage/current/apparent-power caps | Real and imaginary components constrained to zero | Product-law Jacobians can have other degeneracies |
| Positive current/apparent-power caps | Upper-only magnitude constraints | They can be redundant with other physical restrictions |
| Neutral, negative- and zero-sequence voltage caps | Upper-only magnitude constraints | No lower/upper pair to merge |

This inventory identifies representation choices, not a proof that every possible
input has independent constraints. It does not extend element coverage, infer
missing limits, change nameplate policy or substitute for the existing physical
bound and recovery audits.

## Manufactured experiment

The experiment uses the existing coupled π-line
[joint-boundary fixture](ivr_joint_boundaries.md), retaining both unequal endpoint
shunts. It fixes receiving voltage at 230 V phase-neutral in the two-wire case,
or ``\sqrt{3}\,230`` V phase-phase in the three-wire delta case. A cyclic
receiving-terminal permutation exercises positional current recovery. The line
rating is 250 A, inherited from the previously declared loose-current treatment.
These are manufactured physical scenarios, not modified external-feeder ratings.

Two generators have opposite reactive-power targets of ±600 kvar per device
and zero active-power targets. Squared P/Q errors are divided by ``10^6``. Both
target directions, 1/100 kVA assembly bases, Ipopt `none`/`gradient-based` policies,
six retained full/reduced/lifted/reuse profiles and both voltage representations
give **192 solves**. Dispatch coordinates remain 10 kVA and other power lifts
1 kVA. All models use per-unit coordinates and the same encoded unloaded start.

Strict settings remain `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, MUMPS AMD and the existing iteration/time limits. The
first full equality model in each physical/base/scaling cell supplies the common
objective and physical-point anchor. Agreement requires `atol=1e-5, rtol=1e-8`.
Every row also checks independent physical residuals, own/full membership,
reverse membership of the anchor, reader round trip and rejection after moving
the fixed voltage both 0.1% down and 0.1% up.

| Representation | Strict solves | Model/physical/objective admissions | Also passes stricter export audit |
|:--|--:|--:|--:|
| Separate inequalities | 96/96 | 95/96 | 93/96 |
| Magnitude equality | 96/96 | 96/96 | 96/96 |

The excluded objective comparison is three-wire, positive target direction,
100 kVA, automatic NLP scaling off, with reduced generator reuse. Its objective
exceeds the full equality anchor by about 0.002456 in the declared squared-power
objective. The point remains physically feasible and has `LOCALLY_SOLVED` status.
The objective threshold is unchanged; a larger absolute difference in another
cell remains within its relative tolerance because the objective scale differs.

Maximum absolute row multipliers across the whole panel are approximately
``2.79\times10^{16}`` for separate inequalities and ``1.71\times10^7`` for
equalities. These are maxima over all non-bound constraint rows, in model units;
they are not identified voltage sensitivities. Equality multipliers need not be
small, and their magnitude alone is not a solver-quality test. The controlled
comparison supports eliminating this particular redundant representation,
without establishing that all conditioning problems are resolved.

## Validation and retained failures

The new regression suite passes **1,490 assertions**. It covers all four paired
voltage families, bounded-observation lifting, exact versus nearly equal bounds,
proper intervals, zero bounds and explicitly fixed source rows. Ninety-six
dispatch solves check physical correspondence and two-sided rejection. Equality
formulations also agree on objectives across the six profiles. Separate-form
objective discrepancies belong to the optional measurement report; they are not
hidden by relaxing a regression tolerance.

An independent Python reader checks all 192 SI exports, including the excluded
control. It reconstructs π-line currents and losses, 960 current margins,
864 ungrounded KCL balances, 384 fixed-voltage observations, native powers and
the objective. All 384 shifted-voltage rejection certificates pass. Physical
export structures agree across formulations, and all 192 files pass a separate
BMOPFTools reader comparison. Policy and pair-report fields are additive native
metadata; physical variables retain their original meanings.

Three separate-inequality endpoints exceed the reader's stricter ``10^{-5}`` VA
π-loss-identity threshold: two errors are about ``1.18\times10^{-5}`` VA and
one is ``2.19\times10^{-5}`` VA. Two had passed the runner's standard gates;
the third is the objective-discrepant control. These are additional post-solve
audit exclusions, reported separately in the table. The audit threshold is
retained. All equality endpoints pass this stricter audit. Initial test-fixture
and export-reader errors, their corrections and every measured endpoint remain
in the external archive `VOLTAGE_EQUALITIES_20261006`.

## Use and reproduction

```julia
build = build_opf(input, IVRNLP(
    coincident_voltage_bounds=:equality,
    lifting=:powers,
    specialization=:conductor_regions,
    linear_elimination=:passive_blocks);
    optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(
    print_level=0, tol=1e-10, constr_viol_tol=1e-10,
    acceptable_iter=0, bound_relax_factor=0.))
@assert result.solve.optimal && physical_residuals(input, result).passed
build.numerical_diagnostics[:coincident_voltage_bound_report]
```

The option does nothing to a proper voltage interval. Preserve declared input
bounds; do not make them coincide merely to activate the rewrite.

```sh
julia --project=test test/ivr_voltage_equality_tests.jl
julia --project=test examples/benchmark_ivr_voltage_equalities.jl /tmp/voltage-equality/report.json
```

The runner retains failed comparison rows. A successful exit confirms report
completion, not universal admission. These diagnostic solves can overlap other
correctness jobs, so they provide **no performance ranking**. The independent
single-phase timing attempt was also excluded after its process monitor detected
another Julia workload. The best-evidence speed shortlist remains unchanged;
all transformation options are retained.
