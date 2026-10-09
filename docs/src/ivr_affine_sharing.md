# Exact affine observation sharing

Two original operating observations may become identical, opposite or proportional
after exact coordinate composition. Reusing one auxiliary can reduce an extended
formulation without deleting either original limit. The new optional modes
`observation_sharing=:signed` and `:proportional` extend coefficient-exact sharing;
all old options and defaults remain.

## Certificate and scope

The observations are complex affine functions of the same real solver variables.
Sharing requires a real scalar relation across **every real and imaginary
coefficient and both constants**. `:signed` accepts only factors ±1.
`:proportional` matches tuples normalized using exact binary-rational values of
the stored floating-point coefficients, then requires an exactly representable,
finite, nonzero `Float64` reconstruction factor. A rounded normalized floating
key would be insufficient: distinct rows could collide after division.

The first encountered representative keeps its original defining equation and
units. A later observation uses `factor * representative` in every bound and
native power expression. Both ratings remain, including distinct limits on
opposite line ends. This preserves a unique extension of every original feasible
point. The proof and signed-power example are in the [theory](ivr_theory.md);
[API details](ivr_nlp.md) describe diagnostics and composition.

Constants must scale with the variable coefficients. The real-only policies
introduce no free translation, complex rotation, conjugation, tolerance,
coefficient truncation, or matching
based only on feasible circuit solutions. Fixed variables are not substituted
during the certificate. Different floating-point construction histories can
prevent reuse; they retain separate exact definitions.

A proportional class may need multiple representatives. If `3u` was encountered
first, `u` cannot reuse it through a rounded factor `1/3`; it gets a new definition.
A later `2u` can use that second representative through the exact factor two.
Overflow, underflow to zero and nonrepresentable ratios likewise retain separate
definitions. This conservative algorithm does not claim maximal sharing or a
preferred numerical normalization. The first-representative choice can affect
both counts and conditioning.

`observation_support_threshold` still selects rows by composed real-variable
support. `lifting=:off` and `:powers` are unaffected by observation sharing.
Power auxiliaries and generator dispatch are not merged by these options.
Existing generator-definition reuse remains a separate policy. Point encoding
fills representative observations before dependent power auxiliaries, retaining
SI starts and outputs and supported CP/dispatch update semantics.

## Correctness evidence

The original real-sharing focused suite passed **1972 assertions**. Direct affine tests cover constants,
negative and non-unit factors, changed coefficients, conjugates, duplicate visits,
nonrepresentable ratios, overflow/underflow refusal and perturbed auxiliaries.
Arbitrary-coordinate evaluation checks the whole reconstructed observation, not
only values at an optimum. Separate representatives are tested when a class
cannot use a single exactly representable factor.

Physical tests cover single-phase, delta and four-wire circuits, charging,
reversed/permuted ports, power units and generator reuse. Native complex powers,
full/reverse membership, SI JSON round trips and live load/generator updates are
checked. Each tested nonzero interior phase/pair/neutral/sequence voltage family
has independent physical and encoded rejection witnesses. Original line current
and apparent-power limits remain. Independently constructed single-phase,
centre-tap, delta-wye and wye-delta transformer states exercise both winding
current limits under two power bases and reversed power directions.

The first run passed the algebraic and physical tests but failed the candidate
comparison test: independently copied objective-term objects were compared by
identity. Comparing their serialized values corrected that test. Original logs
are retained, and no physical tolerance was relaxed. These tests establish the
stated static domain; they are not an interval proof for arbitrary floating-point
solver arithmetic or a claim of full control-model coverage.

## Complex-proportional extension

`observation_sharing=:complex_proportional` admits a complex factor after
certifying the complete affine relation over exact complex binary rationals.
Both real and imaginary parts of the factor must be representable exactly as
finite `Float64` values. An unsafe ratio retains a separate definition. All
existing modes and the default `:off` remain available. This is an optional
correctness-qualified candidate; it has no established wall-time benefit.

A motivating physical relation is an eliminated constant-impedance load,
``i=Yu``, with nonreal admittance ``Y``. If its voltage and current both qualify
for observation lifting and their stored coefficients pass the certificate,
one complex auxiliary can represent both. Real-only proportional sharing cannot
reuse this pair when ``\Im Y\ne0``. The original power remains
``s=u\overline{i}=\overline Y|u|^2``; the sign of reactive power must survive
the substitution. Other circuit elements can prevent this affine match even
when a relationship holds at a particular operating point.

The [equivalence argument](ivr_theory.md) gives the real rotation/scaling map
and the two-factor power formula. `test/ivr_complex_sharing_tests.jl` checks
arbitrary-coordinate recovery, sparse real/imaginary support exchange, constants,
conjugate refusal, representability failures, distinct ratings and separate
power definitions. Its manufactured circuit tests cover power cost/tracking,
common physical starts, bidirectional membership and SI result round trips.
The existing affine-sharing tests additionally exercise the new mode against
ordinary transformer winding bounds, interior terminal/sequence voltage bounds,
line limits and live CP/dispatch updates. Fixed-observation tests check that
inlining and its live dependencies retain precedence over sharing.

The numerical protocol and results below concern the historical real-only
portfolio. They do not establish performance or external-network transfer for
the complex extension. Different floating-point construction histories can
prevent exact matches; the mode does not approximate coefficients to create them.

## Historical numerical protocol

`examples/benchmark_ivr_affine_sharing.jl` supplies six candidates: `full_powers`,
`reduced_powers`, and reduced bounded-observation lifting with `off`, `exact`,
`signed` or `proportional` sharing. Within the four observation profiles only
sharing changes. All use threshold two, assembly and generator-dispatch units
10 kVA, power-lift units 1 kVA, no generator reuse, nominal transformer units,
composed rows, voltage-ground scaling and physical objective divisor one.
Reduced profiles use conductor regions, unrestricted passive blocks and
transformer-current elimination. The power-only controls retain power lifting.

Two manufactured 12-segment uncharged terminal-load chains exercise single-phase
and delta connections. BASE265 and URBAN1220 retain unchanged DER inputs and
addition manifests from the [hybrid transfer study](ivr_hybrid_transfer.md).
All four cases use economic cost and source P/Q tracking; active-power targets
are 1, 1.5, 37 and 134 kW respectively, with zero reactive target. This initial
panel does not include active-voltage or gradient-policy transfer. Four-wire,
charged and reversed-port fixtures remain correctness tests.

Preflight checks all 48 profile/workload combinations, physical/own/full/reverse
membership, SI export round trips and every cached observation at an arbitrary
coordinate point. Timings use one shared unloaded linear-circuit physical start,
MUMPS AMD, strict solver tolerances 1e-10, one Julia/BLAS thread and no automatic
Ipopt scaling. Each of eight cells has six excluded warm-ups and six randomized
cyclic sweeps. Exploration and complete confirmation run in fresh processes.
Positions are balanced; predecessor pairs are not. The declared total is 576
measured solves and 96 excluded warm-ups. Only Ipopt wall time ranks candidates;
construction, starts, extraction and audits are excluded. Tests, documentation
and other solver work do not overlap timing. Both batches and all tails remain.

## Results

All **576 measured solves, 96 warm-ups and 48 preflight SI exports** pass.
The independent audit verifies sources and DER additions, complete shared starts,
physical/own/full/reverse membership, physical export fields and all 96 matched
contrasts. Preflight checks **6544 cached observations** at arbitrary coordinate
points; the maximum reported relative reconstruction error is zero on these
samples. Maximum recovered-power objective discrepancy is below 2.86e-14 and
within-cell objective spread below 7.11e-15. Sharing reports agree between
preflight and every measured/warm-up build. These numerical samples supplement
the coefficient certificate; they are not its proof.

### Auxiliary counts and actual matches

The following table reports real solver variables for cost. Tracking has the
same counts in this panel. Labels `Off`, `Exact`, `Signed` and `Proportional`
refer to bounded-observation sharing, with power lifting retained in all columns.

| Case | Full powers | Reduced powers | Off | Exact | Signed | Proportional |
|:--|--:|--:|--:|--:|--:|--:|
| `wire2_terminal` | 158 | 68 | 114 | 114 | 114 | 114 |
| `wire3_terminal` | 330 | 196 | 382 | 338 | 336 | 336 |
| `BASE265` | 3880 | 3076 | 3256 | 3220 | 3154 | 3154 |
| `URBAN1220` | 16946 | 12778 | 14002 | 13782 | 13286 | 13286 |

The single-phase chain has no additional sharing, so the four observation-sharing
labels introduce the same number of definitions. The delta chain has 22 exact
reuses and 23 signed/proportional reuses, saving one further complex auxiliary.
BASE265 rises from 18 to 51 reuses, saving 66 real auxiliaries; URBAN1220 rises
from 110 to 358, saving 496. This leaves more variables than power-only lifting.

Signed and proportional profiles have identical representative/factor reports
and counts in every case/workload, and all applied factors are ±1. **No non-unit
proportional reuse activates in this timing panel.** Non-unit factors are verified
by the direct certificate tests, but these timings cannot establish their benefit.
Small signed/proportional timing differences must not be attributed to additional
proportional sharing. All modes are retained for future cases.

### Confirmation wall times

Times are median **Ipopt wall milliseconds**. Construction costs are excluded.
Batches remain separate; no tail is removed.

| Case | Workload | Full powers | Reduced powers | Off | Exact | Signed | Proportional |
|:--|:--|--:|--:|--:|--:|--:|--:|
| `wire2_terminal` | `quadratic_cost` | 3.694 | 3.388 | 3.447 | 3.457 | 3.435 | 3.469 |
| `wire2_terminal` | `exchange_tracking` | 1.921 | 1.715 | 1.738 | 1.758 | 1.758 | 1.765 |
| `wire3_terminal` | `quadratic_cost` | 7.999 | 6.762 | 6.820 | 6.612 | 6.314 | 6.343 |
| `wire3_terminal` | `exchange_tracking` | 5.592 | 4.806 | 4.856 | 5.430 | 4.484 | 4.464 |
| `BASE265` | `quadratic_cost` | 42.385 | 39.780 | 40.607 | 40.591 | 39.436 | 39.836 |
| `BASE265` | `exchange_tracking` | 25.148 | 23.429 | 23.876 | 23.775 | 23.404 | 23.382 |
| `URBAN1220` | `quadratic_cost` | 232.377 | 229.451 | 238.145 | 236.782 | 230.433 | 230.950 |
| `URBAN1220` | `exchange_tracking` | 115.274 | 111.790 | 115.731 | 115.323 | 111.971 | 111.859 |

### Matched signed-sharing contrasts

Each entry is the median of six same-sweep time ratios. Values below one favour
signed sharing. A median of paired ratios need not equal the quotient of the
profile medians above.

| Case | Workload | Signed/exact exploration | Signed/exact confirmation | Signed/power-only exploration | Signed/power-only confirmation |
|:--|:--|--:|--:|--:|--:|
| `wire2_terminal` | `quadratic_cost` | 1.0027 | 0.9966 | 1.0128 | 1.0164 |
| `wire2_terminal` | `exchange_tracking` | 1.0157 | 0.9957 | 1.0368 | 1.0226 |
| `wire3_terminal` | `quadratic_cost` | 0.9649 | 0.9538 | 0.9291 | 0.9200 |
| `wire3_terminal` | `exchange_tracking` | 0.8245 | 0.8255 | 0.9334 | 0.9359 |
| `BASE265` | `quadratic_cost` | 0.9820 | 0.9710 | 0.9926 | 0.9894 |
| `BASE265` | `exchange_tracking` | 0.9871 | 0.9825 | 1.0083 | 1.0006 |
| `URBAN1220` | `quadratic_cost` | 0.9756 | 0.9755 | 1.0064 | 1.0047 |
| `URBAN1220` | `exchange_tracking` | 0.9740 | 0.9661 | 1.0106 | 1.0031 |

## Interpretation

**The delta terminal chain supports signed sharing.** Its paired ratios against
power-only lifting are 0.9291/0.9200 for cost and 0.9334/0.9359 for tracking in
exploration/confirmation, approximately 6–8% lower time. Every paired signed/
power-only comparison favours signed sharing in both batches and objectives.
Against exact sharing, cost improves about 3.5–4.6% and tracking about 17.5%.
Only one additional complex auxiliary is removed. This shows that a small
structural change can matter, but does not identify the native solver mechanism
or establish transfer from this manufactured circuit.

**BASE265 cost has a small repeated gain; tracking is effectively tied.** Signed
sharing leads cost in both batches. Its signed/power-only paired medians are
0.9926 and 0.9894; confirmation profile medians are 39.436 versus 39.780 ms.
Individual ratios cross one, so retain this as an additional selected-case
candidate. Tracking's paired medians are 1.0083 and 1.0006 despite a slightly
smaller signed profile median in confirmation. There is no consistent tracking
advantage over power-only lifting.

**Urban sharing reduces lifting overhead but does not beat power-only lifting.**
Compared with exact sharing, signed cost ratios are 0.9756/0.9755 and tracking
ratios 0.9740/0.9661. Despite removing 496 real auxiliaries, it remains slightly
slower than power-only lifting in both batches and workloads: signed/power-only
medians are 1.0064/1.0047 for cost and 1.0106/1.0031 for tracking. Retain the
power-only control in the urban shortlist. The previous hybrid cap and generator-
reuse candidates are separate experiments and are not re-ranked here.

**The single-phase chain is an inactive sharing control.** No matching rows are
found beyond existing original-row caching. The observation profiles retain 114
real variables versus 68 for power-only lifting. Small winner-label changes in
tracking therefore do not demonstrate a sharing benefit. Signed/power-only
paired ratios exceed one in both batches and workloads.

Every profile has the same iteration count within each of the sixteen cells.
Thus changed iteration counts do not explain the differences. The study does
not separate derivative evaluation from linear-system work or establish a KKT
fill explanation. Slow tails remain: confirmation signed/power-only ratios
reach about 1.335 on BASE265 tracking and 1.334 on urban tracking; the latter's
signed/exact ratio spans 0.784–1.300. No run is discarded or selectively repeated.

These selected cases, six sweeps per cell and two batches do not establish
statistical significance, a global AC optimum or a universal fastest formulation.
Automatic solver scaling, active voltage limits, new feeders, mixed IBR/nonlinear
load objectives and non-unit proportional opportunities remain unmeasured
transfers. The tests cover a wider physical domain than this timing panel.
Defaults are unchanged; the new modes and every older option remain available.

## Reproduction and next work

[Tutorial section 43](tutorial_exact_ivr.md) demonstrates the public options and
matched physical acceptance checks. The new runner retains full and reduced
power-only controls and all four observation-sharing modes. Frozen source,
protocol, raw trials, SI exports, audit scripts and planning documents are stored
outside Git in `AFFINE_SHARING_20261006`.

The next useful experiment is an isolated combination of signed observation
sharing with the existing urban cap-four and generator-reuse candidates, keeping
all main-effect controls. Do not assume that separately useful changes add.
A distinct physical fixture that actually activates non-unit factors is needed
before assigning a performance benefit to proportional sharing. Broader mixed
IBR/nonlinear-load workloads and original-network reconstruction remain separate
roadmap work; none is implied complete by this exact graph extension.

The subsequent [structural factorial study](ivr_structural_interactions.md)
completes the sharing/cap/reuse interaction panel across both solver-scaling
policies and the declared voltage-constrained scenario. Its conditional findings
supplement this earlier isolated-sharing evidence.
