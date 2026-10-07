# Joint zero-load, lifting and transformer-current effects

The [selective observation study](ivr_zero_load_observations.md) found a clear
broad-lifting benefit on the zero-reduced 333-bus tracking case, while an earlier
unreduced campaign favoured powers-only. Comparing those separate campaigns
cannot isolate the interaction. The implemented protocol crosses all three choices in
the **same balanced timing block**. Physical validation and diagnostic collection
are complete; isolated timing is deferred:

| Factor | Level 0 | Level 1 |
|:---|:---|:---|
| Certified zero-load elimination | Disabled | Enabled |
| Observation lifting | Powers-only | Broad bounded observations |
| Ordinary transformer currents | Explicit | Eliminated |

All eight combinations use existing options. No library equation, default,
physical bound or canonical result field changes. Compilation and model-build
costs have no role in the speed assessment.

## Scope and estimands

The input is the unchanged `32_MVFeeder3323` declared external DER scenario:
333 buses and 16 ordinary delta–wye transformers, with the previously declared
static generators, IBRs and voltage-dependent parallel loads. Its zero-load
certificate removes 1,471 complex load-current coordinates when enabled. This
is a focused follow-up on a previously selected case, not held-out validation.
Preflight covers cost and tracking; the repeated-timing protocol covers
**exchange tracking only**. Units, power bases, physical starts, objective terms and strict Ipopt/MUMPS
settings are fixed across arms and unchanged from the earlier study.

Let ``T_{m,z,l}`` be the median Ipopt optimizer-call wall time in one batch, where
``m`` indexes ordinary-current elimination, ``z`` zero-load elimination and
``l`` broad rather than powers-only lifting. Define

```math
R_{m,z}=\frac{T_{m,z,1}}{T_{m,z,0}},\qquad
\Gamma_m=\frac{R_{m,1}}{R_{m,0}},\qquad
\Xi=\frac{\Gamma_1}{\Gamma_0}.
```

``R<1`` favours broad lifting at fixed current and zero-load choices.
``\Gamma_m<1`` means zero-load elimination improves the *relative* broad-lifting
benefit. ``\Xi`` measures how that interaction changes with the ordinary-current
representation. It is not the speedup of a single formulation. Conditional
zero-load and ordinary-current ratios are also retained, because averaging them
can conceal interactions. Ratios are invariant to seconds versus milliseconds.

The primary contrasts use each arm's median. The same contrasts are also computed
within every complete sweep to expose sensitivity to repeat variation. Batches
remain separate; no outlier removal, pooling or significance claim is used.
Balanced comparisons strengthen attribution to the controlled formulation
choices, but do not identify a numerical mechanism or establish a population-wide
effect. The deterministic schedule is a balanced crossover, not random sampling.

## Reproducible design

`examples/benchmark_ivr_joint_reductions.jl` supplies the eight arms, balanced
orders, interaction calculations and a timing driver. Sixteen eight-arm sweeps
per batch put each arm in each position twice, and each ordered within-sweep
predecessor pair occurs twice. Between-sweep transitions are not balanced.
Each batch has eight excluded warmups and 128 measured solves. Confirmation runs
in a fresh Julia process and reverses the complete sweep order.

First run `examples/benchmark_ivr_zero_loads.jl` on the declared input to produce
the sixteen-solve preflight and canonical SI exports. The timing driver refuses
a nonempty output directory, requires an accepted preflight, checks its input
hashes and saves pending/completed state. Its local ranking remains provisional
until the external whole-campaign admission audit passes:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test \
  --startup-file=no examples/benchmark_ivr_joint_reductions.jl \
  /path/to/accepted-preflight /path/to/new-exploration exploration
```

Use a separate process and a new directory for `confirmation`. A monitor must
exclude the whole campaign if competing Julia work is observed; it must never
terminate unrelated work. Timing admission also requires every physical audit,
own/full-model and reverse-anchor check, SI objective check, balanced order and
frozen source/input digest to pass. Only optimizer-call wall time is ranked.

This executable example constructs independent multiplicative factor effects.
All three interactions must be one; the helper must not mistake an ordinary
zero-load speedup for an interaction:

```@example joint_reduction_contrasts
include(joinpath(@__DIR__, "..", "..", "examples",
    "benchmark_ivr_joint_reductions.jl"))
J = IVRJointReductionStudy
times = Dict(J.arm(m,l,z) => (m == :off ? 1.0 : 0.9) *
    (l == :powers ? 1.0 : 1.2) * (z ? 0.8 : 1.0)
    for m in (:off, :transformer_currents)
    for l in (:powers, :bounded_observations) for z in (false, true))
effects = J.contrasts(times)
@assert all(x ≈ 1 for x in values(effects.zero_lifting_interaction))
@assert effects.three_way_interaction ≈ 1
effects
```

The regression additionally checks known nonzero interactions, scale invariance,
invalid/missing timing values, every position and predecessor count, the exact
three controlled option differences and refusal to overwrite evidence.

## Factorization diagnostics

Eight separate verbose solves retain actual MUMPS reports, using the same
physical starts and solver settings except for logging. They must match silent
controls in objective, iterations and model dimensions, and pass the same
physical/model gates. Their logging-heavy wall times are **ineligible** for speed
ranking. The existing `ivr_mumps_factor_trace.py` parser preserves every numerical
factorization, reports actual factor entries and storage, and leaves unavailable
counters missing.

Buffered Fortran reports can cross a per-model stdout capture boundary, even
when C stdout is explicitly flushed. A filename therefore does not establish the
model responsible for every report. In this experiment, eight per-arm captures
and the outer process capture together contain the complete observed reports.
Each arm has a distinct `(N, NNZ)` matrix signature. The parser's
`reconcile_captures(captures, models)` attributes JOB=2 and JOB=3 by that signature
and requires exact agreement with independently counted Ipopt wrapper calls.
It refuses ambiguous signatures, undeclared jobs, incomplete factor reports and
count mismatches. This is a check for this capture set; matrix dimensions are
not a general model identifier.

Eight solve reports crossed their primary capture boundaries. Reconciliation
corrected five per-arm solve totals; factorization counts and maximum stored
factor entries were unchanged. The original per-file analysis remains archived
as superseded evidence, alongside the corrected analysis and capture provenance.
Eleven parser tests include missing, duplicated, truncated and displaced reports.

Maximum stored entries, input matrix order and factorization counts describe
observed work. They do not establish symbolic fill-edge counts, conditioning,
backward error or causal runtime decomposition. Previously observed zero-valued
printed factorization timers remain unvalidated; no claim here relies on them.

### Reported MUMPS work

All eight diagnostic runs pass physical and full/reduced checks and match their
silent preflight controls in options, objective, iterations and dimensions.
MUMPS reports version 5.9.1. Entries below are the maximum reported stored factor
entries, **not bytes or symbolic fill edges**. Solve calls count observed JOB=3;
they need not correspond one-to-one with Ipopt iterations.

| Currents | Zero reduction | Lifting | Iterations | Factorizations | Solve calls | Max. factor entries |
|:---|:---|:---|---:|---:|---:|---:|
| Explicit | Off | Powers | 32 | 39 | 100 | 1,247,713 |
| Explicit | On | Powers | 33 | 38 | 118 | 1,030,460 |
| Explicit | Off | Broad | 36 | 42 | 111 | 1,491,074 |
| Explicit | On | Broad | 36 | 42 | 73 | 1,298,712 |
| Eliminated | Off | Powers | 32 | 40 | 86 | 1,229,692 |
| Eliminated | On | Powers | 33 | 40 | 126 | 1,021,333 |
| Eliminated | Off | Broad | 36 | 42 | 104 | 1,491,641 |
| Eliminated | On | Broad | 36 | 42 | 74 | 1,295,163 |

With zero-load elimination enabled, broad lifting increases both stored factor
entries and numerical-factorization counts relative to powers-only. Its observed
solve-call counts fall from 118 to 73 with explicit ordinary currents and from
126 to 74 with eliminated currents. Without zero-load elimination, broad lifting
instead increases these counts from 100 to 111 and from 86 to 104. The solve-call
pattern therefore changes with the combination of transformations. The subsequent
[refinement audit](ivr_refinement_diagnostics.md) accounts for the call difference
through residual corrections and recovery restarts, while leaving the underlying
conditioning and wall-time explanation open.

## Evidence status

All sixteen preflight solves (two objectives × eight arms) pass original SI
physics, own/full-model and reverse-anchor checks. Their canonical SI exports
pass both FormulationLab and BMOPFTools readers and share 134,735 physical leaf
paths. Independent checks cover 46,176 coil-power identities, 768 rated
transformer-port values and limits, and exact recovery of 1,471 complex zero-load
currents when elimination is enabled. The same 7,369 operating-bound and
generator-definition declarations and 4,470 load-law declarations are retained;
2,942 load-law constraints are omitted with elimination provenance. These audits
do not establish complete input-schema coverage.

The first timing attempt was excluded in full when the isolation monitor detected
another Julia process during confirmation. It retained 128 exploration and 48
confirmation measurements, plus sixteen warmups; the interrupted trial's outcome
is not assumed. Only the owned benchmark process group was stopped. A fresh
attempt after a quiet interval was also excluded when competing Julia work
restarted during startup, before any returned measurements. The user then
requested that timing be deferred. **Neither campaign is admitted, and no new
wall-time ranking or numerical timing-interaction estimate is reported.** A later
attempt must repeat both batches in full with a fresh source freeze.

The harness passes 282 targeted Julia assertions; the capture parser passes
11 Python tests. No library source changes, and the full library suite was not
rerun for this experiment. A subsequent reanalysis separates repeated linear solves and residual corrections;
see the [refinement audit](ivr_refinement_diagnostics.md) for its restricted scope.

Raw inputs, preflight exports, verbose reports, excluded timings and independent
audits are retained outside Git in `JOINT_ZERO_OBSERVATION_20261007`. The previous
best-evidence timing recommendation is unchanged. All options remain available.
