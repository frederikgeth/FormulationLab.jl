# Selective transformer-coil observation lifting

## Motivation

Eliminating transformer currents can reduce state dimension while making their
recovered affine expressions denser. Broad bounded-observation lifting can
reduce nonlinear coupling, but introduces auxiliaries for many other voltage
and current observations. The opt-in `observation_selection` controls which
original rows are eligible for those affine auxiliaries. It leaves power
lifting, electrical elimination, original bounds and physical outputs intact.

| Selection | Eligible original observation rows |
|:--|:--|
| `:all` | All requested observations; unchanged default |
| `:coil_voltages` | Rows matching stamped transformer coil voltages |
| `:coil_currents` | Rows matching stamped transformer coil currents |
| `:coils` | Union of coil voltage and coil current rows |

Selection applies only with `lifting=:bounded_observations`. It has no effect
for `:off` or `:powers`. The existing support threshold and observation-sharing
policies remain independent controls. No transformation option is removed.

## Provenance and exact graph extension

Eligible rows come from the electrical assembly's ordinary-transformer
`:transformer_coil_from` and `:transformer_coil_to` observations and multiwinding
`:transformer_coil` observations. Selection compares original row keys, before
coordinate composition, using their recorded coefficients and indices. It does
not identify a coil by an approximate coefficient match or a variable name.
For multiwinding devices, the stamped coil current is the series current;
terminal excitation and ground-current observations remain distinct.

Eligibility belongs to a **row**, not to a particular bound's label. A bus
voltage bound or power objective requesting the exact same original row is also
eligible. Conversely, a different original row that happens to compose to the
same affine expression is not selected merely because an auxiliary exists.
Selection occurs before affine-sharing lookup. Sharing can reuse definitions
only among requests that passed selection and the support threshold.

For an eligible requested observation ``u=aRy``, the threshold counts distinct
real native variables after composition. A count strictly greater than
`observation_support_threshold` creates a complex auxiliary ``w`` with

```math
\Re w=\Re(aRy),\qquad \Im w=\Im(aRy).
```

Otherwise the original affine expression remains direct. Identically zero
channels never acquire an auxiliary. Power lifting still defines exactly the
same complex power from its voltage and current, regardless of which factors
are explicit. Every original magnitude, current and power rating is enforced.

These equalities uniquely determine the new variables for each native state.
Projection removes them, and extension reconstructs them; neither operation
changes physical feasibility. Existing start and physical-point encoders
evaluate the auxiliary definitions in dependency order. Electrical coordinate
maps, omitted electrical rows and recovered SI variables do not change with
the selector. In particular, a coil-current auxiliary used in a nonlinear bound
does not reintroduce that current into retained KCL equations.

## Tutorial and profiling

```julia
using FormulationLab, Ipopt
options = IVRNLPOptions(
    lifting = :bounded_observations,
    observation_selection = :coils,
    observation_support_threshold = 2,
    observation_sharing = :signed,
    device_elimination = :all_transformer_currents,
    transformer_scaling = :nominal_multiwinding,
    row_scaling = :composed,
    kcl_row_max_base = 1000.0,
)
build = build_opf(network, IVRNLP(options); optimizer=Ipopt.Optimizer)
build.numerical_diagnostics[:observation_selection]
build.numerical_diagnostics[:observation_selected_row_count]
```

`observation_selected_row_count` counts distinct candidate original row keys,
including any empty key; it is `nothing` for unrestricted/inactive selection.
It is not the number of created auxiliaries. Only requested observations above
the threshold are lifted, and exact sharing can reduce the number further.

The reproducible study helper provides both support profiling and the five
experimental arms:

```julia
include("examples/benchmark_ivr_coil_observations.jl")
O = IVRCoilObservationStudy
O.supports(build)
O.run(output_directory) # Correctness/structure preflight; no timing ranking.
```

`supports` examines original coil observations in the native coordinates before
introducing affine auxiliaries. These counts can motivate a candidate, but are
not factorization fill or conditioning estimates. On the 24-unit fixture, 288
of 294 coil-current observations exceed the default threshold after full
transformer-current elimination; none do when multiwinding currents remain
explicit. Coil voltages have supports of two to four real variables, with only
30 of 294 exceeding the threshold. Some candidates have no requested bound or
objective use and therefore do not create auxiliaries.

## Controlled evidence, 7 October 2026

The 60-endpoint panel crosses 2/8/24 four-winding units, cost/tracking power
objectives, explicit/eliminated multiwinding currents and five lifting arms.
All use the same per-unit assembly, regional current and auxiliary power units,
nominal policy, KCL cap, physical start, solver settings and original bounds.
Among the four bounded-observation arms only the selector changes. The
powers-only control remains available separately.

All **60/60 endpoints** pass the unchanged physical, own/full-model,
reverse-anchor and independent winding-equation gates. The largest objective
spread is below ``2.436\times10^{-10}``. It passes the predeclared comparison
gate ``|f_1-f_2|\le\max(10^{-7},10^{-6}\max(|f_1|,|f_2|))``; the absolute
component governs the small tracking objectives. This does not establish
global optimality or identical optimizer paths. Eight archived default controls
reproduce their previous objective and iteration count exactly.

For 24 units, tracking objective and eliminated multiwinding currents:

| Lifting arm | Real variables | Unique Jacobian entries | Unique Hessian entries | Iterations |
|:--|--:|--:|--:|--:|
| Powers only | 5936 | 57368 | 16524 | 21 |
| Coil voltages | 5960 | 57464 | 16484 | 24 |
| Coil currents | 6224 | 58856 | 15084 | 21 |
| Both coil observations | 6248 | 58856 | 15044 | 21 |
| All bounded observations | 8384 | 63896 | 12032 | 20 |

Jacobian and Hessian counts are unique entries supplied through the backend
before Ipopt preprocessing. They are **not** KKT fill, factorization memory or
wall time. Selective coil lifting preserves much of the state-dimension saving
while recovering some of the Hessian sparsity lost through current elimination.
Broad lifting has more variables and Jacobian entries but the smallest Hessian
and one fewer iteration in this cell. Voltage-only lifting gives little
structural improvement and increases the iteration count here. All arms remain
available for subsequent experiments.

With explicit multiwinding currents, the current-only selector coincides with
the powers-only control on this panel: its coil currents have two-variable
support and do not exceed the threshold. This is an expected inactive control,
not independent evidence for a second formulation.

These structural observations motivate the isolated, repeated **Ipopt
optimizer-call wall-time** comparison below, with matched objectives and
physical gates. Compilation, model construction, extraction and audit costs
do not enter that ranking. The single-trial structural results alone do not
establish a fastest policy.

## Prospective wall-time comparison

The same helper now provides `O.run_timing(output_directory, batch)`, where
`batch` is `"exploration"` or `"confirmation"`. Each call requires an empty output
directory. The original one-argument command remains a single-trial preflight.
Run the two batches in separate Julia processes, under a whole-campaign
isolation monitor:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test --startup-file=no --compiled-modules=existing examples/benchmark_ivr_coil_observations.jl /path/to/empty/exploration exploration
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test --startup-file=no --compiled-modules=existing examples/benchmark_ivr_coil_observations.jl /path/to/empty/confirmation confirmation
```

These commands do not themselves establish isolation. The external monitor
must refuse an initially busy machine and exclude the entire campaign if
competing Julia work is observed, including previously completed cells. It may
interrupt its own benchmark session only. Source hashes must match before and
after both batches. Sampled process isolation does not certify absence of other
system load or competition shorter than the sampling interval.

Each batch contains the same twelve cells as the preflight. A cell has one
excluded warmup per arm, followed by ten five-arm Williams sweeps. The first
five orders are cyclic shifts of `[1,2,5,3,4]`; the next five reverse each of
those rows. Thus each arm appears twice in each position and each ordered pair
appears twice as an immediate predecessor **within** a sweep. Transitions
between sweeps and warmup positions are not balanced. Confirmation reverses
both cell order and sweep order without adapting to observed timings. The full
design has **1,200 measured solves and 120 excluded warmups**.

All arms start from the same unloaded physical point, encoded separately in
their own coordinates. Warmup endpoints provide membership anchors, never
optimizer starts. Admission requires an accepted warmup and all ten accepted
repetitions, together with the existing physical, own/full-model, reverse-anchor
and independent winding-equation checks. Objective comparison uses the gate
stated above. No outliers are trimmed and no failed solve is silently retried.
Cell medians use only `ipopt_wall_s`; compilation, model construction, extraction,
audit and checkpoint time remain outside the performance criterion.

Reports store a planned schedule and a chronological ledger. Before each solve,
an atomic checkpoint records `status="started"`; after a result returns, another
records `status="completed"` and retains the result even when rejected. A
surviving `started` entry means completion is unknown. Completed sweep orders
are recorded separately. An incomplete cell retains `complete=false` and no
ranking. Even complete cells retain `timing_eligible=false`: their provisional
rankings require the external isolation and full-campaign audit before any
performance interpretation. A later attempt must use new output directories;
partial campaigns cannot be pooled.

### Attempt disposition, 7 October 2026

The initial attempt was refused before launch because two Julia processes were
already running. A fresh attempt subsequently started from a quiet process
snapshot. Its monitor later detected competing Julia work and interrupted only
the new benchmark session. All of that attempt is excluded: **ten complete
cells, 55 returned warmups and 534 returned measured solves**. Every returned
endpoint was accepted, but physical acceptance cannot repair timing
contamination. A further ledger entry remains `started`, so that solve's
completion is unknown. Confirmation did not start. The monitor retained 128
process snapshots; no speed ranking is admitted.

The separate correctness-only integration panel completed 20 warmups and 200
measured-path calls on the two-unit fixture, all accepted. It verifies the live
runner and report contract under deliberately nonisolated conditions. Its
largest within-cell objective spread is below ``2.0\times10^{-13}``; its times
are also excluded. These records are in `COIL_OBSERVATION_TIMING_20261007` and
the separate interrupted attempt in `COIL_OBSERVATION_TIMING_20261007_RETRY1`,
outside Git. No defaults or fastest-profile recommendations change.

## Isolated confirmation — 7 October 2026

A subsequent fresh campaign completed both frozen batches. All **1,200 measured
solves and 120 excluded warmups** passed the physical, own/full-model,
reverse-anchor, independent winding-equation and objective gates. Source hashes
matched before and after. The two-second monitor retained **327 snapshots**
with no observed competing Julia process. This establishes admission under the
stated sampled-isolation protocol; it cannot exclude other system load or
shorter unobserved activity. Earlier refused and interrupted attempts remain
excluded in full and are not pooled with this campaign.

**All bounded observations won every cell in both batches (12/12 repeated
winners).** Confirmation geometric means of within-cell median optimizer-call
time ratios are below. Each column weights its six manufactured cells equally;
these are descriptive ratios, not an IID estimate over distribution networks.

| Observation lifting | Explicit multiwinding currents | Eliminated multiwinding currents |
|:--|--:|--:|
| Powers only | 1.000 | 1.000 |
| Coil voltages | 1.016 | 0.995 |
| Coil currents | 1.000 | 0.902 |
| Both coil observations | 1.014 | 0.886 |
| All bounded observations | 0.817 | 0.666 |

Broad observations reduce the geometric-mean time by **18.3%** with explicit
multiwinding currents and **33.4%** with eliminated currents. Current-only and
both-coil lifting help the eliminated representation on average, but neither
beats broad observations. Voltage-only lifting has little average benefit.
The inactive explicit-current control has ratio 1.0004; it is an equivalent
model and supplies repeatability evidence, not an independent transformation.

The individual confirmation median ratios for broad observations are:

| Units | Power objective | Explicit currents | Eliminated currents |
|--:|:--|--:|--:|
| 2 | Cost | 0.775 | 0.771 |
| 2 | Tracking | 0.800 | 0.541 |
| 8 | Cost | 0.864 | 0.797 |
| 8 | Tracking | 0.807 | 0.507 |
| 24 | Cost | 0.841 | 0.831 |
| 24 | Tracking | 0.815 | 0.621 |

This changes the best-evidence **candidate for this panel** to broad bounded
observations, holding the remaining coordinate, power-base, row-scaling and
reduction choices fixed. It does not change package defaults or remove any
selector. In a secondary cross-representation comparison, explicit currents
with broad observations lead all six confirmation cells; five repeat their
exploration ordering, while the two-unit tracking cell reverses. Thus broad
lifting is the more repeatable finding; multiwinding-current elimination is
still optional. The cross-representation contrast was not interleaved within
one Williams sweep and should not inherit its within-cell balance claim.
External-feeder transfer remains necessary. Compilation and preparation costs
are excluded throughout.

The complete audit, per-solve ledger, frozen sources and summaries are retained
outside Git in `COIL_OBSERVATION_TIMING_20261007_RETRY2`.

## Actual factorization reports

A separate diagnostic panel repeats the twenty 24-unit objective/current/arm
combinations with `print_level=7`, `mumps_print_level=2`, and
`print_timing_statistics="yes"`. All physical and model gates pass, and every
objective and iteration count exactly matches its uninstrumented confirmation
warmup. The verbose runs are **not timing evidence**. They use MUMPS 5.9.1.

The text parser `examples/ivr_mumps_factor_trace.py` retains each observed
numerical call (`JOB=2`), its input order and entry count, actual factor entries
(`INFOG(29)`), real/integer storage (`INFOG(9/10)`), maximum front, negative pivots
and delayed pivots. It also counts observed symbolic and solve calls. Estimates
and Ipopt's shorter storage summaries do not replace actual factor-entry data.
Factorizations need not correspond one-to-one to Ipopt iterations.

Selected results below are maxima over reported numerical factorizations:

| Objective | Multiwinding currents | Observations | Iterations | Factorizations | Factor entries | Real storage |
|:--|:--|:--|--:|--:|--:|--:|
| Cost | Explicit | Powers | 25 | 31 | 538,898 | 725,067 |
| Cost | Explicit | All | 25 | 31 | 642,263 | 858,771 |
| Cost | Eliminated | Powers | 25 | 31 | 588,090 | 762,511 |
| Cost | Eliminated | All | 25 | 31 | 631,047 | 832,218 |
| Tracking | Explicit | Powers | 20 | 21 | 533,734 | 715,643 |
| Tracking | Explicit | All | 20 | 21 | 614,672 | 827,327 |
| Tracking | Eliminated | Powers | 21 | 43 | 556,723 | 723,285 |
| Tracking | Eliminated | All | 20 | 28 | 608,300 | 804,796 |

The faster broad-observation arm stores more factor entries in all four
objective/current comparisons. It is therefore incorrect to explain its speed
advantage as smaller stored factors. In eliminated-current tracking, broad
observations reduce numerical factorizations from **43 to 28**, while iterations
change only from 21 to 20. Current-only and both-coil lifting retain 21 iterations
but reduce factorizations to 30 and 28, respectively. This exposes work hidden
by iteration counts; it does not prove which cost caused the wall-time change.
Derivative evaluation, factor arithmetic and repeated linear solves still need
separate attribution.

For an existing verbose log:

```sh
python3 examples/ivr_mumps_factor_trace.py solve.ipopt.log solve.factors.json
python3 -m unittest discover -s test -p 'test_ivr_mumps_factor_trace.py'
```

This diagnostic JSON is separate from canonical physical result exports. Each
factor-to-input entry ratio uses the `NNZ` supplied to MUMPS in that call, not
the JuMP Jacobian count. Its meaning depends on solver storage conventions;
it is not a count of new symbolic fill edges. Missing or negative/encoded
counters remain unavailable. Duplicate counters within a numerical call raise
an error. `complete_factor_reports` means that the observed calls have all
requested fields; it cannot prove that log capture itself was complete.
The parser is tied to observed text labels rather than a stable solver API.
A later [capture-attribution audit](ivr_joint_reductions.md) demonstrates that
buffered reports can cross per-model file boundaries. Historical per-file JOB=3
counts should therefore be read as observed capture counts unless reconciled
against independent wrapper counts across the complete capture set. That later
audit does not retrospectively validate model attribution in these older logs.

Seven parser regression tests cover actual versus estimated/storage counts,
changing matrix sizes, truncated reports, negative counters, zero denominators
and duplicate fields. An independent whole-file counter extraction agrees with
every parsed factor-entry sequence in the twenty live logs. Raw logs, scripts,
control comparisons and JSON are retained in `FACTORIZATION_DIAGNOSTICS_20261007`
outside Git. No solver tolerances, formulation options or physical exports change.

## Verification scope

Tests verify original-row selection before affine sharing, ordinary and
multiwinding coil provenance, inactive/default behavior, exact auxiliary
definitions, starts, full-model membership and violations of selected winding
and unselected line bounds. Single-phase WYE and SINGLE_PHASE fixtures optimize
an objective expressed directly in coil power, with an independent analytical
target and full-model membership check. SI result exports retain their original
physical variables. These manufactured cases do not establish external-feeder
performance transfer. The subsequent [external MV/LV study](ivr_external_observations.md)
tests ordinary transformers on three source-preserving feeder scenarios, with
separate admission and isolated-timing gates.

Twenty additional four-unit solves span both objectives, both current
representations and all five arms. Their SI exports pass the FormulationLab
and BMOPFTools readers. Independent exported-state audits check 80 non-star
winding blocks and 960 coil apparent-power/current-magnitude records. Physical
leaf paths agree across all arms, including exactly recovered device channels.
These checks validate the result contract, not a speed advantage.

The preflight reports, source snapshots, initial test-development failure,
export checks and complete validation logs are retained outside Git in
`COIL_OBSERVATION_SELECTION_20261007`. The initial row-equality test incorrectly
compared different assembly power units; the corrected control aligns those
units without changing physical data or relaxing any tolerance.
