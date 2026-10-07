# Observation lifting after zero-load elimination

The [certified zero-load reduction](ivr_zero_loads.md) removes a substantial
number of current coordinates in the three declared external DER scenarios.
That change also shortens composed observations. This study asks whether the
best observation-lifting choice changes after the reduction. It compares existing
options; it adds no electrical approximation or default policy.

## Hypothesis and controlled factors

For an original physical observation row ``a``, let ``T`` denote the exact
reconstruction from retained coordinates ``z``. A voltage or current observation
is the affine expression ``aTz``. Lifting introduces an auxiliary ``y=aTz``.
Power lifting instead introduces ``s=(a_VTz)\overline{(a_ITz)}``. All five arms
keep the same power-lifting policy; they differ only in which qualifying affine
observations receive additional auxiliaries:

| Arm | Additional eligible observations |
|:---|:---|
| `powers` | None |
| `coil_voltages` | Original transformer coil voltages |
| `coil_currents` | Original transformer coil currents |
| `coils` | Both original transformer coil quantities |
| `all` | All qualifying bounded observations |

The existing support threshold and signed sharing remain fixed. Selection uses
the original physical coil rows before affine sharing. An eligible row need not
create an auxiliary: its composed support can be below the threshold, or a
permitted shared definition can already exist. These are exact extended
formulations; dimensions and iteration counts alone do not predict runtime.

Every arm enables `zero_load_elimination=true`. Ordinary transformer currents
are either retained or eliminated in separate experimental cells. The full
design crosses three external scenarios, two power objectives and these two
current representations, giving twelve cells. It does not re-estimate the
benefit of zero-load elimination against an unreduced control.

The scenarios, 17/110/333 buses with 1/7/16 ordinary delta–wye transformers, are
the unchanged inputs from the [external transfer study](ivr_external_observations.md).
They contain declared added DERs and voltage-dependent parallel loads, rather
than observations of installed DER equipment. No native multiwinding transformer
is present. The quadratic cost and exchange-tracking objectives, source/LV
current bases, generator/lifted-power bases, starts, operating limits and strict
Ipopt settings are unchanged. All runs use per-unit coordinates.

## An inactive simplification opportunity

The existing power-lifting routine checks whether a product is identically zero
after requesting its factor observations. A future exact short-circuit could
avoid an unnecessary voltage auxiliary when its current factor is already zero.
However, instrumenting all twelve broad-observation builds here found **zero**
calls with an identically zero raw voltage or current factor. These eliminated
load channels are not selected by the present power objectives or equipment
power bounds. Consequently, this optimization cannot explain or improve this
panel, and no library change was made on its behalf.

This is a scope-specific negative finding. It does not say that zero-power
observations are impossible in other objectives or bound configurations. The
screen preserves the original method body with read-only logging, performs no
optimization, and remains separate from the frozen timing processes.

## Effective choices and duplicate-model controls

All transformer coil currents in this panel have composed support of exactly
two real variables, including after ordinary current elimination. With the
fixed threshold of two, none qualifies for an additional observation auxiliary.
Delta-side coil voltages have support four and wye-side coil voltages support
two. The five option names therefore represent only **three distinct emitted
models** in every cell:

- `powers` and `coil_currents` have identical complete JuMP model text.
- `coil_voltages` and `coils` have identical complete JuMP model text.
- `all` additionally lifts qualifying observations outside the transformer coils.

SHA-256 checks of the full, untruncated model text agree for both duplicate pairs
in all twelve cells. This is a stronger check than matching dimensions, though
it is not a measurement of numerical factorization structure. The structural
screen runs separately from timing. Both names are retained in the predeclared
five-arm schedule as negative controls for timing variability. Small runtime
differences between these duplicate models cannot be attributed to a different
mathematical formulation.

| Buses | Added real variables: coil voltages / coils | Added real variables: all |
|---:|---:|---:|
| 17 | 6 | 280 |
| 110 | 42 | 2,200 |
| 333 | 96 | 6,890 |

These increments relative to powers-only are the same under both objectives and
both current representations. On tracking, the selective choices keep the
powers-only iteration counts of 8/22/33. Broad lifting gives 8/24/36. These
descriptive findings motivate the timing comparison; they do not prove its outcome.

## Reproduction and admission

`examples/benchmark_ivr_zero_load_observations.jl` reads an already-declared
scenario. It refuses to overwrite a nonempty evidence directory, saves pending
trial identifiers, retains failures, and exports all twenty physical solutions
per input. A single preflight never supplies a speed ranking:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test \
  --startup-file=no examples/benchmark_ivr_zero_load_observations.jl \
  /path/to/declared-scenario/INPUT.json /path/to/new-evidence-folder
```

The following executable example inspects the predeclared crossover schedule.
It verifies position balance without requiring the external data:

```@example zero_observation_schedule
include(joinpath(@__DIR__, "..", "..", "examples",
    "benchmark_ivr_zero_load_observations.jl"))
using .IVRZeroLoadObservationStudy
schedule = IVRZeroLoadObservationStudy.orders("exploration")
@assert length(schedule) == 10
@assert all(count(o -> o[position] == arm, schedule) == 2
    for position in 1:5 for arm in 1:5)
@assert IVRZeroLoadObservationStudy.orders("confirmation") == reverse(schedule)
schedule
```

Each timing batch uses ten five-arm Williams sweeps per cell, with one excluded
warmup per arm. Positions and immediate within-sweep predecessors occur twice;
between-sweep transitions are not balanced. Confirmation runs in a fresh Julia
process and reverses both cell and sweep order. Only the within-cell lifting
contrasts are balanced; comparisons between the separately scheduled current
representations are not a new controlled ranking of those representations.

Each duplicate arm is reported separately. Choosing the faster name within an
identical-model pair would turn timing variability into an apparent formulation
improvement. We therefore interpret a small selective-voltage effect cautiously
when its size is comparable to the duplicate-control differences. The batches
are kept separate; no outlier removal, post hoc pooling or statistical-significance
claim supplies a speed recommendation.

The primary metric is the median **Ipopt optimizer-call wall time**, excluding
compilation, model construction, recovery and audits. Admission requires frozen
source/input hashes, single Julia/BLAS threads, no observed competing Julia,
complete trial counts, original SI physics, both reduced/full endpoint membership,
reverse-anchor membership and objective agreement. Preflight exports additionally
pass both FormulationLab and BMOPFTools readers, with matching physical field
paths and exact recovery. Inventory equality checks emitted operating declarations;
it does not establish completeness of the input schema.

## Admitted evidence — 7 October 2026

All **60 external preflight solves** pass, with objective agreement across the
ten formulations per workload. Independent export checks reconcile **75,120
coil-power identities** and **1,440 transformer rated-port values and limits**.
Every arm retains identical physical leaf paths and exact zeros for the 39,
458 and 1,471 eliminated complex load currents. The inventory contains the
same **218/2,171/7,369 operating-limit and generator-definition declarations**
in every arm of each feeder. Omitted load laws keep their explicit provenance;
`complete_input_coverage` remains false.

All sixty result files also pass the native and BMOPFTools readers. The new
protocol regression passes 82 assertions, including twenty small-case solves,
exact zero exports, controlled option differences, balanced orders and refusal
to overwrite existing evidence.

All **1,200 measured solves and 120 excluded warmups** pass the frozen admission
protocol. All source and input hashes remain unchanged. The two-second monitor
records **731 snapshots** without observed competing Julia; this does not exclude
other system load or shorter jobs. Every trial and outlier is retained. Raw
inputs, exports, inventories, model-text hashes, support counts, complete repeats,
analysis scripts and admission records remain outside Git in
`ZERO_LOAD_OBSERVATION_20261007`.

### Confirmation medians

Times below are milliseconds of Ipopt optimizer-call wall time. `Explicit` and
`Eliminated` refer to ordinary transformer currents; zero-load elimination is
always enabled. The table preserves both names of each identical-model pair.
Current representations occupy separate cells, so their absolute times are not
an independently balanced comparison in this campaign.

| Buses | Objective | Currents | Powers | Coil V | Coil I | Coils | All |
|---:|:---|:---|---:|---:|---:|---:|---:|
| 17 | Cost | Explicit | 4.856 | 4.861 | 4.787 | 4.824 | 5.571 |
| 17 | Cost | Eliminated | 4.817 | 4.852 | 4.955 | 4.964 | 5.602 |
| 17 | Tracking | Explicit | 6.555 | 6.714 | 6.705 | 6.597 | 7.542 |
| 17 | Tracking | Eliminated | 6.489 | 6.199 | 6.557 | 6.426 | 7.238 |
| 110 | Cost | Explicit | 170.844 | 175.273 | 169.295 | 177.864 | 203.092 |
| 110 | Cost | Eliminated | 147.565 | 145.991 | 148.314 | 144.289 | 166.164 |
| 110 | Tracking | Explicit | 169.241 | 168.400 | 169.376 | 167.802 | 169.046 |
| 110 | Tracking | Eliminated | 165.598 | 169.867 | 165.187 | 171.834 | 163.791 |
| 333 | Cost | Explicit | 679.322 | 678.823 | 668.356 | 683.796 | 678.751 |
| 333 | Cost | Eliminated | 675.123 | 675.860 | 670.637 | 677.327 | 680.789 |
| 333 | Tracking | Explicit | 834.638 | 835.384 | 827.006 | 843.660 | 743.624 |
| 333 | Tracking | Eliminated | 872.323 | 809.664 | 868.697 | 807.026 | 751.647 |

Across the six case/objective cells in each current representation, the geometric
mean ratios to powers-only are:

| Batch | Currents | Coil V / powers | Coil I / powers | Coils / powers | All / powers |
|:---|:---|---:|---:|---:|---:|
| Exploration | Explicit | 1.0068 | 1.0043 | 1.0036 | 1.0525 |
| Exploration | Eliminated | 0.9736 | 1.0058 | 0.9752 | 1.0265 |
| Confirmation | Explicit | 1.0076 | 0.9958 | 1.0082 | 1.0571 |
| Confirmation | Eliminated | 0.9839 | 1.0051 | 0.9934 | 1.0387 |

The fastest **emitted model class** repeats in all twelve cells: powers-only in
six, selective coil voltages in three and broad observations in three. This is
not twelve robust effect estimates. Duplicate-model median differences reach
**2.98% in exploration and 3.66% in confirmation**. Absolute control times also
move between batches, for example 142.1 to 170.8 ms for explicit-current medium
cost. The analysis therefore uses matched within-cell contrasts, retains both
batches separately and treats nearby rankings cautiously.

### Refined recommendations and limits

The clearest gain is **broad lifting on the 333-bus tracking workload**. Relative
to the named powers-only control, confirmation reductions are **10.9% with
explicit ordinary currents and 13.8% with eliminated currents**; exploration
gives 11.0% and 14.6%. Broad also beats both duplicate powers controls in both
batches. It adds 6,890 real variables and raises iterations from 33 to 36, yet
solves faster. Neither model size nor iteration count explains the runtime by
itself. Actual factorization reports are needed before attributing the gain to
linear algebra, sparsity or conditioning.

Selective coil-voltage lifting on the largest eliminated-current tracking cell
also improves relative to powers-only: 8.5% in exploration and 7.2% in confirmation,
with unchanged iterations. Broad remains faster there. On medium eliminated-current
cost, the voltage-only improvement changes from 9.6% to 1.1% between batches;
its identical `coils` arm changes from 8.9% to 2.2%. This instability prevents a
strong general recommendation from the selective average alone.

Broad is the named winner in medium eliminated-current tracking too, but its
confirmation advantage is only 1.1% over powers and 0.8% over the identical
current-only control. Keep that as a close alternative, not a demonstrated
material speed gain. Powers-only remains the economical starting candidate for
the panel overall: broad/powers geometric means are **1.057 and 1.039** in
confirmation for explicit and eliminated currents. Preserve both ordinary-current
representations and every lifting option. Profile the actual workload before
choosing the conditional exception for larger tracking cases.

The earlier unreduced external campaign favoured powers-only everywhere; this
reduced panel has a clear large-tracking exception. Because zero-load off/on and
lifting were not jointly randomized in the same timing block here, the difference
between campaigns is **not a measured causal interaction size**. The next focused
experiment should cross zero-load off/on, powers/broad lifting and ordinary-current
retention/elimination in one balanced block on that tracking case. Then extend
beyond these three scenarios and include changing zero/nonzero demand patterns.
No universal default, global-optimality result or additional input-schema coverage
is established by this study.

The subsequent [joint reduction experiment](ivr_joint_reductions.md) places all
eight combinations of zero-load, lifting and ordinary-current choices in the
same balanced-block protocol. Timing is deferred after two isolation failures.
Its completed diagnostic audit distinguishes dimensions, stored factors,
factorization counts and solve-call counts, including buffered capture spillover.
