# Verification

## Physical non-unit transformer sharing — 6 October 2026

The full suite passes **83,907/83,907 assertions**, including **5143 new checks**.
Manufactured single-phase cascades activate exact winding factors −8 and −1/8,
including series leakage, reversed ports and active original winding ratings.
Tests cover both winding sides, interior neutral/phase-neutral voltage limits,
native powers, SI JSON fields/round trips, complete starts, full/reverse model
membership, independent analytical values and reusable load/generator updates.
No production equation, default or previous option changes.

All **1536 measured solves, 192 warm-ups and 96 preflight SI exports** pass.
All 384 tightened winding-current and 96 neutral-voltage witnesses reject
physically and algebraically. The independent audit verifies source preservation,
44,280 arbitrary-coordinate identities, named winding sharing, 192 paired timing
contrasts and identical threshold-two MOI algebra/maps in all twelve cells.
Objective discrepancy is below 3.34e-15; within-cell spread below 1.78e-15.
Only Ipopt wall time ranks; timing never overlaps tests/docs/other solver work.

At threshold zero, proportional sharing improves matched signed-sharing times
about 4.5–7.7%. Nevertheless, every proportional threshold-zero/two paired median
favours threshold two in both batches. Non-unit sharing is physically demonstrated,
but introducing extra lifting solely to activate it is not supported here.
Threshold-two sharing labels emit identical models; their winner changes are
timing variation. Both batches, all tails and all options remain available.

The analytical test setup was corrected to create benchmark profiles before
fixing dispatch; the existing dispatch-freedom guard remains. The evidence audit
explicitly accounts for the runner's empty provenance metadata addition without
excluding arbitrary input differences. Original logs remain. The existing
OpenDSS precompile fallback is nonfatal. See the
[scientific study](ivr_nonunit_transformers.md) and
[tutorial section 45](tutorial_exact_ivr.md).

## Structural reduction interactions — 6 October 2026

The full suite passes **78,764/78,764 assertions**, including **1028 new checks**
for the eight-arm blocks/cap-four × exact/signed sharing × generator-reuse
composition and two power-only controls. Tests verify isolated factors and
option ownership, single-phase/delta physical membership under both power
objectives and solver policies, complete starts, recovered objectives, actual
cap/reuse counts and rejection of tightened original voltage/current/power limits.
No production equation, default or previous formulation option changes.

All **2400 measured solves, 240 warm-ups and 120 preflight SI exports** pass.
All 60 capability and 20 original-voltage rejection witnesses pass; each
VOLTAGE265 cost preflight has one active upper-voltage limit. Independent audits
verify sources, physical export fields, common starts, own/full/reverse membership,
component graphs, sharing reports, 288 conditional contrasts, 144 pairwise
interactions and 240 power-only control comparisons. Maximum recovered-power
objective discrepancy is below 1.07e-14; within-cell spread below 2.14e-14.
Both batches and all slow tails remain. Only Ipopt wall time ranks candidates;
timing does not overlap tests, docs, other solver work or native diagnostics.

Reuse slows urban cost about 7–10% and raises iterations from 17 to 19, while
helping urban tracking. Urban cap-four cost effects reverse with reuse enabled.
Signed sharing plus reuse becomes an additional urban tracking candidate; its
best cap changes between batches. Combined signed/cap cost does not reliably
displace power-only lifting. Older power-only/reuse and power-base finalists are
not all in this panel, so no global ranking or default promotion follows.

The initial delta reuse-count expectation was corrected from one per device to
three native power channels; physical/bound checks already passed. Original logs
remain and no tolerance changed. The existing OpenDSS precompile fallback is
nonfatal. See the [complete study](ivr_structural_interactions.md) and
[tutorial section 44](tutorial_exact_ivr.md).

## Signed/proportional affine sharing — 6 October 2026

The full suite passes **77,736/77,736 assertions**, including **1972 new checks**
in `test/ivr_affine_sharing_tests.jl`. The opt-in `:signed` and `:proportional`
modes retain all previous options and defaults. Their coefficient certificates
include constants, preserve native power signs and require exactly representable
real reconstruction factors. Direct tests cover non-unit factors, changed rows,
nonrepresentable ratios, overflow/underflow refusal and arbitrary-coordinate
reconstruction. Physical tests cover single-phase/delta/four-wire circuits,
charging, reversed/permuted ports, transformer units and both winding limits,
interior voltage families, line ratings, live updates and SI JSON round trips.

All **576 measured solves, 96 warm-ups and 48 preflight SI exports** pass.
An independent audit verifies sources/additions, physical export fields, complete
starts, own/full/reverse membership and 96 paired contrasts. All **6544 cached
observations** pass the additional arbitrary-coordinate preflight checks.
Recovered-power objective discrepancy is below 2.86e-14 and within-cell spread
below 7.11e-15. Shared representative/factor reports match preflight throughout.
No timing overlaps tests, docs or other solver work; all tails and both batches
remain, ranked only by Ipopt wall time.

Signed sharing improves the tested delta chain about 6–8% against power-only
lifting and gives a small repeated BASE265 cost gain. Urban power-only lifting
still leads despite signed sharing saving 496 real auxiliaries versus exact
sharing. Every profile has identical iteration counts within each cell.
Proportional sharing adds no non-unit reuse in this timing panel, so its broader
matching rule has no demonstrated extra performance benefit here.

The first focused candidate-comparison test used object identity for copied
objective terms; serialized value comparison corrected it. Original logs remain;
no physical gate was relaxed. The existing OpenDSS precompile fallback is nonfatal.
See the [complete study](ivr_affine_sharing.md), [proof](ivr_theory.md),
[API](ivr_nlp.md) and [tutorial section 43](tutorial_exact_ivr.md).

## Hybrid transfer across objectives and scaling — 6 October 2026

Production code, tests and benchmark candidates are unchanged from the
75,764-assertion hybrid baseline. This stage adds numerical transfer evidence
and an executable tutorial comparison, without changing defaults or deleting
any formulation option. All **1176 measured solves, 168 warm-ups and 84
preflight SI exports** pass across BASE265, VOLTAGE265 and URBAN1220, both
power objectives and both Ipopt scaling policies. Every constrained cost
preflight has one active upper-voltage limit. All 42 tightened-capability and
14 tightened-voltage witnesses reject independently and algebraically.

An independent audit verifies unchanged inputs/addition manifests, physical
quantity fields, complete shared starts, own/full/reverse membership, graph
caps and 240 paired timing contrasts. Maximum recovered-power objective
discrepancy is below 1.07e-14; within-cell spread below 7.11e-15. A separate
untimed map audit confirms blocks equal cap eight and nonadjacent equals cap
one on all three scenarios. All profiles have the same iteration count within
each cell. Timings do not overlap tests, documentation or native diagnostics;
no slow trial or batch is removed.

Cap four repeats its urban cost ordering under both scaling policies, with
small magnitude: confirmation profile medians improve 1.65% without automatic
scaling and 0.17% with gradient scaling. Paired ratios are reported separately
and should not be confused with quotients of profile medians. Tracking and
the active-voltage scenario show no consistent benefit. These are selected
related scenarios, not independent feeder or active-urban-voltage validation.
See the [complete transfer results](ivr_hybrid_transfer.md) and
[tutorial section 42](tutorial_exact_ivr.md).

## Bounded hybrid condensation — 6 October 2026

The full suite passes **75,764/75,764 assertions**, including **5337 new checks**
in `test/ivr_hybrid_tests.jl`. The optional `:passive_hybrid` policy caps connected
groups of eliminated original buses while retaining the existing block
certificate, reconstruction and bound-support gates. No default or previous
transformation is removed. Independent graph traversal verifies the cap;
arbitrary-coordinate tests verify projection/reconstruction and eliminated
rows. Single-phase, delta and four-wire cases include charging, reversed and
permuted ports, singular blocks, support rollback and reusable updates.
Tightened original interior voltage and both line-end current/apparent-power
limits reject in physical and encoded checks. Additional endpoint witnesses
isolate the intended apparent-power violation.

All **1372 measured solves, 196 warm-ups and 98 preflight SI exports** pass.
Physical quantity fields agree across policies; recovered-power objective
agreement is below 9.01e-14 and within-cell objective spread below 7.11e-15.
The audit independently checks component graphs, source hashes, complete shared
starts, full/reverse membership, cyclic order and 280 conditional contrasts.
Only Ipopt wall time ranks candidates; timings do not overlap tests, docs or
native solver diagnostics. Both batches and all tails remain.

Caps regress on the manufactured terminal chains. Urban cost favours cap four
by about 1% in both batches, under unscaled Ipopt only. Cap eight has identical
projection/reconstruction maps to unrestricted blocks on both external feeders;
its narrow timing differences are not cap benefits. Every candidate has the same
iteration count within each case/batch/workload cell. These results justify an
additional urban-cost candidate, not a general default or a factorization claim.

The initial focused run was blocked by Julia-cache permissions. A subsequent
test compared whole coordinate containers, including model-specific JuMP
variables; it was corrected to compare the projection/reconstruction maps.
Original logs remain. The existing OpenDSS precompile fallback is nonfatal.
No solver tolerance or physical acceptance gate was relaxed.

See the [methods and complete results](ivr_hybrid.md), [API](ivr_nlp.md),
[component invariant](ivr_theory.md) and [tutorial section 41](tutorial_exact_ivr.md).

## Controlled power-unit interactions — 6 October 2026

The full suite passes **70,427/70,427 assertions**, adding **317 checks** in
`test/ivr_power_interaction_tests.jl`. They verify all eight dispatch/lift/reuse
combinations, every declared factor difference, independently owned options,
complete shared starts, physical objective agreement under both solver-scaling
policies, actual effective units/reuse counts, refusal paths and source-safe
benchmark provenance. The existing finalist runner retains its candidate set and
shares the same measurement protocol with the new factorial runner. Production
equations, defaults and all transformation options are unchanged.

All **2400 measured solves, 240 warm-ups and 120 separate preflight solves** pass
on unchanged BASE265, VOLTAGE265 and URBAN1220 scenarios. SI exports round-trip
with matching physical quantity fields. Six tighter-capability and two tighter-
voltage witnesses reject independently and algebraically. The original sources,
all added-device/bound manifests, actual coordinate bases, complete starts,
full/reverse membership and cyclic order balance pass audit. Maximum recovered-
power objective discrepancy is below 4.98e-14; within-cell spread is below
3.59e-13. An independent audit recomputes all **288 conditional contrasts and
144 pairwise interactions** from raw trials. No batch or slow tail is discarded.

Cost retains the 10 kVA dispatch/1 kVA lift/no-reuse leader on the two smaller
scenarios. Reuse with 100 kVA dispatch slows BASE265 cost about 25–27% and
raises iterations from 14 to 19. Urban cost has close unreused candidates whose
order changes between batches; urban gradient-scaled tracking supports combined
1 kVA lifts/reuse at 10 kVA dispatch. These conditional findings do not imply a
universal profile. Bounded-size hybrid condensation remains a recorded design,
with implementation and original-interior-bound tests still required.

An initial focused test used string indexing for NamedTuple metadata; field
access corrected the test before measurement. The first full-suite startup was
blocked by Julia-cache permissions and was rerun with the required access;
the existing OpenDSS precompile fallback remains nonfatal. Original logs are
retained. No solver timing overlaps tests, documentation execution or native
solver diagnostics. Small JSON progress reads occurred during exploration;
confirmation used only text-log progress reads.

See the [complete interaction study](ivr_power_interactions.md), updated
[profile shortlist](ivr_performance.md) and [tutorial section 40](tutorial_exact_ivr.md).



## Lifted units, exact generator reuse and transfer — 6 October 2026

The full suite passes **70,110/70,110 assertions**, adding **436 checks** in
`test/ivr_lifted_unit_tests.jl`. They exercise independent power-lift units with
fixed assembly and generator units, complete starts/inverse maps, physical
objectives, SI JSON round trips, and exact generator reuse with both power and
bounded-observation lifting. Single-phase and three/four-wire delta cases retain
native coil powers. Perturbed auxiliaries and tightened original capability,
current and voltage limits reject; reusable fixed-box/load changes preserve the
same physical problem. Invalid bases/ratios and sharing modes refuse. Profile
comparisons verify that the declared isolated controls differ in one option.

The ten-profile study admits **2400 measured solves and 240 warm-ups** across
exploration and complete fresh-process confirmation, three physical scenarios,
two power objectives and both solver-scaling policies. All **120 preflight SI
exports** round-trip with matching physical quantity keys. The original 265-bus
DER input is unchanged; its voltage-constrained variant records every added
216–242.5 V phase-neutral bound at original load buses. The 1220-bus scenario
records 268 DER additions on the original four-transformer feeder. All raw sources
and original fields are preserved. Six tighter-capability and two tighter-voltage
witnesses reject independently and algebraically. One voltage upper bound binds
in each constrained cost preflight solution.

Maximum recovered-power objective discrepancy is below 4.98e-14 and within-cell
spread below 3.57e-13. Source snapshots, additions, actual coordinate bases, reuse
counts, full/reverse membership, starts and cyclic order balance pass independent
audit. Timing precedes tests/docs; construction/extraction/audits do not rank
candidates. Every tail and slower alternative is retained.

Smaller power-lift units lead cost across the declared scenarios; generator reuse
helps tracking but slows urban cost despite removing 536 real variables.
Nonadjacent condensation loses to blocks on this panel. The evidence establishes
neither a universal default nor native factorization causality. Bounded-size
hybrid condensation is still unimplemented; this study tests an existing
conservative comparator.

All **41 executable tutorial blocks** pass. Thirty new confirmation timing rows,
earlier tables, and six rendered pages' links/anchors are checked against raw JSON
and HTML. See the [scientific results](ivr_objectives.md), [API contract](ivr_nlp.md),
[profile shortlist](ivr_performance.md) and [tutorial section 39](tutorial_exact_ivr.md).


## Independent generator units — 6 October 2026

The full suite passes **69,674/69,674 assertions**, including **460 new checks**
in `test/ivr_generator_scaling_tests.jl`. An independent two-generator economic
oracle checks heterogeneous dispatch bases, fixed objective normalization,
physical P/Q and reusable bounds. Additional cases cover single-phase and delta
channels, transformer reductions, regional-current coordinates, legacy prices,
complete starts, SI round trips, unknown/invalid bases and fixed/free/one-sided
updates. Tightened original capability, current and voltage limits reject in
both physical and encoded-model checks. A six-profile runner test verifies that
only dispatch units change within each full/reduced representation.

The initial focused run exposed a test macro syntax error and then an infeasible
manufactured update: fixing generation at 200 W with a 2 kW load exceeds its 5 A
line limit. The update fixture now reduces demand to 1 kW first, as in the earlier
update tests. Initial logs are retained; no limit or solver tolerance was relaxed.

On the unchanged 265-bus derived-DER panel, all **576 measured solves and 48
warm-ups** pass across exploratory/fresh-process batches, both cost/tracking
objectives and both Ipopt scaling policies. Maximum physical objective discrepancy
is below 4.45e-15 and within-cell spread below 5.33e-15. All 24 separate preflight
SI exports round-trip with matching physical keys, unchanged raw/scenario hashes
and the same 74 declared additions. Two tighter capability witnesses reject cost
endpoints independently and algebraically. Every profile occupies each position
twice; all tails are retained, and timing precedes tests/docs.

Cost improves with either smaller or larger dispatch units at a fixed circuit
base; tracking retains 10 kVA. The new dispatch-only cost candidate has not yet
been compared against common-1k finalists in one shared timing block. No native
factorization mechanism or global AC certificate is claimed. Defaults and every
transformation remain available; lifted-power units are unchanged.

All **40 executable tutorial blocks** pass. Six new timing rows, earlier tables,
and six rendered pages' local links are checked against raw JSON and HTML.
See the [scientific evidence](ivr_objectives.md), [coordinate contract](ivr_nlp.md)
and [tutorial section 38](tutorial_exact_ivr.md).

## Matched full/reduced power bases — 6 October 2026

The full suite passes **69,214/69,214 assertions**, adding **170 checks** in
`test/ivr_base_formulation_tests.jl`. These cover the 12 distinct base/reduction/
lifting combinations, owned objective declarations, unchanged normalization,
randomized cyclic blocks and refusal paths, complete shared starts, physical
objective equality, full/reverse representability and a source-safe report smoke
test. Every profile occupies each position once per block; predecessor pairs are
not balanced, and realized orders are saved.

The frozen 265-bus derived-DER input is unchanged. Exploration and fresh-process
confirmation admit **1152 measured solves and 96 warm-ups** across quadratic
cost/tracking and both Ipopt scaling policies. Maximum recovered-power objective
discrepancy is below 5.33e-15 and within-cell spread below 3.57e-13. Actual options,
all source/scenario hashes, original fields, added devices and trial orders pass
the evidence audit. All 48 separate preflight solves pass SI JSON round trips
and matching physical quantity keys across formulations. Two tighter-capability
witnesses reject a cost endpoint independently and in encoded constraints.

Full 1 kVA itself improves cost by 13.5–13.7% against full 10 kVA. At fixed base
and lifting, the reduction bundle improves every context in both batches, with
confirmation median paired ratios 0.929–0.949. Lowering the base to 1 kVA hurts
tracking, and 100 kVA tracking regresses by about 34% under gradient scaling while
remaining near 10 kVA with no automatic scaling. No global AC certificate or
native factorization explanation follows. All tails, options and defaults remain;
timings exclude construction/extraction/audits and precede tests/docs.

All **39 executable tutorial blocks** pass. Twelve new confirmation timing rows,
earlier objective tables and local links are checked against raw JSON and rendered
HTML. No production equation or physical bound changed. See the
[matched-base evidence](ivr_objectives.md) and [tutorial section 37](tutorial_exact_ivr.md).

## Derived DER dispatch on 265 buses — 6 October 2026

The full suite passes **69,044/69,044 assertions**, adding **112 checks** in
`test/ivr_der_scenario_tests.jl`. The additive scenario helper preserves original
fields and source bytes, records every generator addition and its source load,
owns nested declarations and protects the source path. Tests cover invalid or
existing dispatch, negative/nonfinite demand, capacity overflow, single-phase,
wye and delta channels, and fixed-zero channels. A fixed-voltage analytical
economic optimum predicts 3.75 kW generator P and zero Q; six profiles match it.
Tightening its apparent-power limit rejects the physical point in independent SI
and encoded-model checks. The initial ambiguous numeric literal in that test is
corrected, with its source and failure log retained.

The external source is unchanged. A separately saved 265-bus scenario adds 74
single-phase generators with 111 kW active capacity to 74 kW original demand.
All original fields and limits are preserved; none of its buses originally has
a voltage magnitude bound. This is a declared DER experiment, not an equivalent
rewrite or an untouched feeder operating case. All 24 preflight comparisons and
24 separate export solves pass, including SI JSON round trips and matching
physical quantity keys across formulations. All 74 new capability circles bind
under economic cost and remain slack under exchange tracking. Two stricter-circle
witnesses independently and algebraically reject a cost endpoint.

Exploration and fresh-process confirmation admit **576 measured solves and 48
warm-ups**. Actual orders place each candidate twice in each position; source and
scenario hashes, physical objectives and full/reverse maps pass. Maximum physical
objective discrepancy is below 5.33e-15 and within-cell spread below 3.58e-13.
These checks do not certify global AC optimality. Timings finish before tests and
documentation builds, retain every tail, and exclude construction/extraction/audits.

Reduced 1 kVA power lifting wins cost by 18.3–18.4% against full 10 kVA, but the
same base change hurts tracking. The best reduced 10 kVA tracking alternatives
gain about 6%, with off versus power lifting near a tie. Full 1 kVA is outside
this shortlist; no universal profile, base or factorization mechanism is claimed.
All options and defaults remain. All **38 executable tutorial blocks** pass;
four new timing rows and prior objective tables are checked against raw JSON
and rendered HTML, alongside local links. See [derived-DER evidence](ivr_objectives.md)
and [tutorial section 36](tutorial_exact_ivr.md).

## External LV power-objective transfer — 5 October 2026

The full suite passes **68,932/68,932 assertions**, adding **147 checks** in
`test/ivr_external_objective_tests.jl`. These verify explicit objective definitions,
multi-channel generation and nonzero box midpoints, legacy-price independence,
owned declarations, refusal of unsuitable dispatch panels, source overwrite
guards, provenance retention, balanced reports, physical objectives, complete
starts, full/reduced point maps and SI result round trips. The tests use a
manufactured network; external data remain outside the repository.

On the unchanged augmented LV input, exploration and fresh-process confirmation
admit **576 measured solves and 48 warm-ups** for quadratic cost and source P/Q
tracking under both Ipopt scaling policies. Every candidate occupies each trial
position twice per cell. All objective/input definitions and source hashes match;
maximum physical objective discrepancy is below 2.73e-12 and within-cell spread
below 1.46e-9. All 24 separate preflight solves pass, with physical SI JSON round
trips and identical exported physical quantity keys across formulations. All five
generator Q lower bounds are active for tracking; its zero-Q target is not reached.

Full IVR is fastest in every cell of both batches. The reduced unlifted bundle
is 34–44% slower in confirmation despite fewer variables and equal iterations.
Observation lifting helps the reduced models but remains slower than full.
Common 1 kVA power lifting and regional observation units offer no transfer gain.
This is one small inherited input, with large reactive export under its declared
parameters; it does not establish large-feeder performance or a global optimum.
All slow trials, failures and previous options are retained. Compilation is
excluded from ranking; no timing overlaps regression or documentation builds.

Initial exploratory array syntax and example keyword-constructor errors were
corrected before freezing the experiment, with original sources/logs preserved.
No production equation, physical input, solver tolerance or default changed.
All **37 executable tutorial blocks** pass. Four new timing rows are checked
against confirmation JSON and rendered HTML, with prior objective tables and
local links also checked. See [external evidence](ivr_objectives.md) and
[tutorial section 35](tutorial_exact_ivr.md).

## Matched power-objective factors — 5 October 2026

The full suite passes **68,785/68,785 assertions**, adding **293 checks** in
`test/ivr_objective_factor_tests.jl`. These cover the 24 independent option
combinations, seeded permutation/reversal orders, invalid-order refusal, complete
shared starts, physical objectives and full/reduced endpoint representability
for quadratic cost and exchange tracking. The generic runner retains its default
schedule and additionally accepts explicit, validated trial permutations.

Exploration and fresh-process confirmation admit **1536 measured solves and 192
warm-ups** across both workloads and both Ipopt scaling policies. Every cell
preserves the physical input, objective definition, objective divisor and start.
The evidence audit verifies factor coverage, actual option records, input hashes,
admission and equal mean trial position. Maximum physical objective discrepancy
is 1.30e-12; maximum within-cell spread is 1.82e-9. These are rounded-up bounds,
not solver tolerances or global-optimality certificates. Initial test code used
a Boolean inside a homogeneous integer vector, which Julia converted to an
integer before validation. The corrected negative witness preserves its Boolean
with an `Any` vector; both the initial failure and passing run are retained.
A first tutorial build exposed a missing `JSON3` import in the new example;
the explicit import fixes its module scope. The original source/log are retained.

Passive-block elimination improves every matched context in both batches.
Regional current units have little consistent benefit; observation lifting helps
quadratic cost after passive reduction but can hurt without it. On exchange,
observation lifting is slower than power lifting in all eight matched contexts
under both policies. All tails and slower options remain; no default changes.
The fixed 10 kVA assembly base does not retest the earlier 1 kVA candidate.

All **36 executable tutorial blocks** pass. The six new contrast-table rows and
four winning medians are checked against confirmation JSON and rendered HTML,
alongside the earlier objective timing table and local links. Timing batches
finish before regression and documentation builds. External feeder work in this
stage is a read-only dispatch inventory, not a transfer-performance claim.
See [matched factors](ivr_objectives.md) and [tutorial section 34](tutorial_exact_ivr.md).

## Physical-power objectives — 5 October 2026

The complete suite passes **68,492/68,492 assertions**, adding **942 checks**.
`test/ivr_power_objective_tests.jl` verifies a closed-form two-generator P/Q
quadratic dispatch optimum across assembly bases, objective divisors, lifting
modes and load/bound updates. It checks signed weighted aggregates, offsets,
native delta coils, every reported native port family, malformed definitions,
owned declarations, complete starts and SI JSON objective metadata.
`test/ivr_ibr_tests.jl` adds independent terminal/internal power-target checks for
single-phase, three-leg and four-leg IBRs, including retained internal freedoms.

Six workloads cross full and reduced formulations, common/regional current units
and optional power/observation lifting on the unbalanced leakage circuit. Each
accepted objective is checked against recovered SI powers and full-model endpoint
membership. Loss accounting independently includes line, transformer and finite
neutral-ground dissipation. The first test oracle omitted finite-ground losses;
that test was corrected, with its failure retained. The production balance-based
loss objective already included those losses. Two test-call keyword errors were
also corrected before the campaign; no solver tolerance was relaxed.

A separate export audit found and fixed an existing normalization bug for
unaccepted IVR diagnostic primals: JSON now multiplies by the effective explicit
objective divisor rather than always by `s_base`. Six nonzero failed-solve
witnesses cover custom power, legacy cost and source import at two bases. The
strict result wrapper still rejects those solves and keeps its objective NaN;
the exported candidate is diagnostic, not an accepted solution. Accepted-solution
conversion was already correct. The fix follows the frozen timing batches and
does not affect any accepted timing result.

Exploration and fresh-process confirmation admit **864 measured solves and 72
warm-ups**. All **35 executable tutorial blocks** pass. The objective page's
six confirmation timing rows are checked against raw JSON and rendered HTML,
and local links/anchors are verified. See [definitions and evidence](ivr_objectives.md)
and [tutorial section 33](tutorial_exact_ivr.md). Existing objective modes,
transformation choices and defaults remain available.

## Unbalanced leakage and power-base transfer — 5 October 2026

The full suite passes **67,550/67,550 assertions**, adding 237 checks in
`test/ivr_unbalanced_power_base_tests.jl`. Prescribed SI winding states cover
single-phase, delta–wye and wye–delta leakage, both flow directions and assembly
power bases of 1 and 1000 kVA with regional current units. Negative witnesses tighten both
sending and receiving ratings and require rejection by the independent SI audit
and encoded model. These tests respect the input schema's winding-versus-terminal
current-rating convention.

All six fixed power-base profiles solve the unequal three-phase panel's three
active-limit cases from a shared physical start. Checks require matching physical
objectives, active intended limits and rejection of tightened receiving-voltage
bounds. Separate reduced builds compose conductor specialization, passive-block
and transformer-current elimination, lifted bounds and exact observation sharing;
full/reduced endpoint membership, complete starts and physical SI JSON round-trips
pass. There is no analytical global-optimum certificate for these coupled OPFs.

The two independent timing batches admit **864 measured solves and 72 warm-ups**.
Separate diagnostics admit 36 native traces and 72 common-physical-point Jacobian
evaluations. The initial manufactured 232 V ceiling was inactive; its source and
preflight logs are retained, and the 231 V active case was frozen before timing.
No scaling profile or solver tolerance was tuned during the campaigns.

All **34 executable tutorial blocks** pass. Five rendered pages have their local
links and anchors checked, and all six new confirmation timing rows are verified
against raw JSON and rendered HTML. See the [unbalanced transfer evidence](ivr_performance.md)
and [tutorial](tutorial_exact_ivr.md). No existing option or default is removed.

## Controlled power bases and objective normalization — 5 October 2026

The full suite passes **67,313/67,313 assertions**, adding 464 checks.
`test/ivr_power_base_tests.jl` crosses four common power bases with optional
regional current bases on three independently solved active-limit circuits.
It verifies physical objectives, currents, dispatch, complete starts, original
bound violations, full-model containment, SI JSON round-trips and load/generator
updates while composing conductor/line/device reductions and lifted observations.
Explicit objective normalization is checked in both solve extraction and supplied
physical-point evaluation. Separate price-update tests verify physical cost
accounting and dispatch reversal after a price change.

Region tests check propagation through lines, open/closed switch boundaries,
unseeded defaults, unknown/conflicting/invalid declarations and ownership of the
build's option snapshot. The aggregate MV/LV harness verifies independent branch
accounting, upstream-rating guards, fixed objective divisors, balanced positions
and analytical admission. The initial bank helper's overly narrow dictionary type
was corrected before the study; its failure log is retained.

A cost-update test initially missed its 1 mW dispatch-accuracy target with a very
small normalized currency objective at solver tolerance 1e-10. The separate cost
test now uniformly uses 1e-12; its physical cost identities still hold at all
tested bases. This does not change the performance protocol: every source-import
timing retains strict 1e-10 settings and the same explicit objective divisor.
The initial test and failure log are preserved outside Git.

All **33 executable tutorial blocks** pass. Rendered links and six confirmation
timing rows are checked against raw JSON/HTML. Both timing batches finish before
full regression and documentation work; instrumented diagnostics finish before
timing starts. No default, physical bound or earlier transformation is removed.
See the [power-base evidence](ivr_performance.md) for confirmed gains and retained
counterexamples.

## Regional finite-ground scaling — 5 October 2026

The full suite passes **66,849/66,849 assertions**, adding 327 checks.
`test/ivr_regional_ground_scaling_tests.jl` checks regional multipliers at three
power bases, weak-ground retention, duplicate shunts, inconsistent-base fallback,
nonfinite coefficients and underflow refusal. Complex-admittance analytical
states and finite-current-error witnesses retain their physical meaning.

Independent active-limit optima cross global/local transformer units with full,
passive-block and transformer-current formulations, including lifted observations
and exact sharing. Checks cover complete starts, map inverses, source import,
dispatch, voltage/current values, physical JSON round-trips, negative original
bound witnesses and CP/generator updates. A charged-chain test verifies actual
passive-block elimination composed with regional grounds and transformer-current
substitution. The six-arm benchmark harness checks admission, balanced positions,
invalid settings and input/manifest exports.

An initial fixture attempted to build deliberately contradictory voltage sources
to test unit-selection fallback; the existing no-load circuit check correctly
refused it. The corrected test inspects base selection separately and asserts
the full builder's refusal. Its original script/log are retained. No physical
benchmark inputs or solver tolerances were changed.

All **32 executable tutorial blocks** pass. Rendered documentation links and eight
timing rows are checked against raw JSON and HTML. Separate diagnostics finish
before timing; both timing batches finish before full regression and documentation
work. The [performance evidence](ivr_performance.md) retains the confirmed
slowdown despite improved Jacobian norm spread. Defaults and older options are
unchanged.

## Active transformer-cascade limits — 5 October 2026

The full suite passes **66,522/66,522 assertions**, adding 224 checks.
`test/ivr_transformer_stress_tests.jl` compares source import, dispatch, voltage
and current with independent scalar optima for capability-, current- and
voltage-limited cascades. It crosses global/local coordinates with full IVR,
passive-block reduction and transformer-current elimination. Shared starts,
complete variable encoding and independent SI/full-model checks pass. Tightening
the intended active limit rejects the original solution in both independent SI
and encoded-model assessments. The runner tests analytical admission, balanced
orders and exported inputs/witnesses.

All **31 executable tutorial blocks** pass. Five rendered documentation pages,
their local links/anchors and six timing-table rows pass JSON/HTML checks. Both
timing batches finish before full regression/documentation work; separate
instrumented diagnostics finish before timing starts. The known OpenDSSDirect
precompile fallback and Documenter size warnings remain nonfatal. No production
equation, option or default changes in this extension. See the
[performance evidence](ivr_performance.md) for gains and retained regressions.

## Transformer-local coordinates and row scaling — 5 October 2026

The full suite passes **66,298/66,298 assertions**, adding 2,335 checks.
Independent SI witnesses cover single-phase, center-tap, delta-wye and wye-delta
transformers under reverse flow, two power bases, both row policies, lifting and
transformer-current elimination. Projection/reconstruction, physical objectives,
original both-side current bounds and supplied-point encoding agree. Separate
1:1, 10:1 and approximately 26.5:1 cases check actual solves, active capability
limits, voltage-limit violations, JSON voltage values/round trips and reuse after
load/generator updates.

Composition tests include actual charged-chain elimination, finite-ground
coordinates, conductor regions, lifted observations and transformer-current
substitution. Independent sources behind an open switch verify that rescaled
source fixing uses the inverse map. Inconsistent cycles/source magnitudes, absent
source seeds, mixed projection bases, unsupported multiwinding propagation and
overflow exercise conservative fallback/refusal. Fixed regulators use the same
nominal voltage level on both sides. Default options preserve the previous model.
The balanced experiment harness checks explicit none/gradient-based Ipopt scaling
blocks independently of the model variable/row policies.

An initial wye-delta fixture encoded roundoff-sized neutral currents as tiny
ratings, failing model checks even with scaling off. As in the earlier device
elimination tests, only manufactured current ratings are floored at 1e-6 A;
physical external inputs and solver tolerances are unchanged. Failed fixture
logs and the baseline reproduction are retained outside Git.

All **30 executable tutorial blocks** pass. Timing runs follow regression and
documentation checks and exclude compilation, extraction and audit costs.
The [performance guide](ivr_performance.md) separates measured benefits from
coordinate equivalence and no-op controls.

## Observation support and exact affine sharing — 5 October 2026

The full suite passes **63,963/63,963 assertions**, adding 2,742 checks.
`test/ivr_observation_policy_tests.jl` verifies equality of composed affine rows
with offsets, variable-order invariance, exact zero handling, and rejection of
opposite signs, conjugates and one-ULP coefficient differences. Separate power
definitions remain separate. Threshold boundary checks use 0, 2, 4 and 100;
physical single-phase/delta cases use thresholds 2, 4 and 8 with sharing off/exact.
Default and explicit legacy settings produce identical displayed JuMP models.

Complete shared starts, sequential auxiliary encoding, perturbed defining
equalities, bidirectional physical-point checks, independent SI residuals,
physical JSON voltage values and unchanged model reuse after CP/generator updates
are checked. The existing charged-block negative tests now also exercise threshold
8 with exact sharing across every covered interior voltage-bound family and both
line endpoints' current/apparent-power limits. None of these policies removes a
physical bound. `test/ivr_observation_study_tests.jl` checks the six-profile
factorial runner, admission flags and balanced order.

All **29 executable tutorial blocks** pass. Initial test syntax and keyword-call
fixture errors were corrected before the validation and timing gates; the latter
log is retained outside Git. The known OpenDSSDirect precompile fallback and
Documenter search-index warning remain nonfatal. Numerical timing evidence is
reported separately in the [performance guide](ivr_performance.md).

## Transformer coil-current substitution — 5 October 2026

The full suite passes **61,221/61,221 assertions**, adding 15,512 checks for the
optional `device_elimination=:transformer_currents` policy and its experiment
harness. Independent prescribed SI states exercise single-phase, center-tap,
delta-wye and wye-delta windings under reverse flow, bus terminal permutations,
two power bases, conductor/line modes and lifting. Arbitrary retained coordinates
verify projection/reconstruction and removed balance equations. Both-side current
limits have separate negative witnesses; physical JSON values and round trips
agree with full IVR on the determined-state fixtures.

Additional witnesses retain ideal delta circulation with unchanged secondary
terminal currents; preserve nonzero open-delta regulator bonds across all three
connections, both regulator types, excitation sides and flow directions; and
exercise zero leakage, finite/ideal grounding, actual charged-chain elimination,
load/generator updates and unchanged model reuse. Incomplete records and consumed
equations exercise atomic refusal. Multiwinding devices remain explicit with a
recorded certificate requirement. The source fixture's terminal arrays initially
aliased component maps; its permutation test was corrected to reassign arrays
and permute bus-indexed bounds consistently. The failed fixture log is retained.

All **28 executable tutorial blocks** pass. Performance measurements run after
tests/documentation, with original physical and full-model audits on every trial.
The [performance guide](ivr_performance.md) reports 192 exploratory and 64
separate confirmation measurements, with 24 and eight excluded warm-ups; all
are admitted. These samples support the declared domain, not general speed or
global-optimality claims. Known OpenDSSDirect precompile fallback and Documenter
search-index warnings remain nonfatal.

## External lifting transfer harness — 5 October 2026

The full suite passes **45,709/45,709 assertions**, including 16 new checks for
the external-feeder lifting runner. These verify source-file immutability,
electrical-field preservation after provenance relocation, sidecar hashes,
balanced ordering, matched ground scaling and objective, admission of all six
profiles on a charged single-phase fixture, and explicit refusal of unsupported
physics before timing. Output paths that alias the input, including symlinks,
are rejected. The benchmark retains failed preflights and rejected trials.
The known OpenDSSDirect precompile fallback remains nonfatal.

The [external-feeder tutorial](tutorial_exact_ivr.md) explains the raw reports,
input snapshots and manifests. Its feasibility objective does not establish
economic-dispatch performance, and a lifting option that introduces no variables
is a timing control rather than evidence for that transformation. Regression
tests and documentation builds are separate from all performance measurements.

## Exact lifting and charged-section blocks — 5 October 2026

The additive `lifting=:powers` and `:bounded_observations` policies preserve a
unique physical-to-auxiliary extension. `linear_elimination=:passive_blocks`
extends local chain elimination to charged π sections using conditioned linear
block solves. Existing policies and defaults are unchanged. The
[equivalence argument](ivr_theory.md) states the nonsingularity condition and
distinguishes mathematical equivalence from floating-point acceptance checks.

The full suite passes **45,693/45,693 assertions**, adding 4,967 checks. Tests
exercise arbitrary-coordinate inverse maps and omitted KCL/KVL equations for
two-, three- and four-wire circuits, both charged and uncharged, with reversed
lines and terminal/ID permutations. Independent SI audits and full/reduced
supplied-point checks accompany solved objective/output parity. Negative
witnesses cover every interior voltage family and both-end I/S limits. Direct
perturbations of auxiliary values expose their defining equalities. Tests also
cover singular resonant blocks, ill-conditioned/incomplete blocks, support-rule
rollback, generator boxes/prices and CP load updates.

The experiment harness checks equal reconstructed physical starts, including all
auxiliaries. Its active midpoint-voltage fixture has an independent uncharged
resistive solution: 4 A source current and **920 W source import**. Charged and
transformer-rich variants have independent physical admission checks. Capability
and midpoint-voltage slacks are recorded instead of assuming limits bind.
All **27 executable tutorial blocks** pass; three updated rendered pages pass
326 local link/anchor checks. Known OpenDSSDirect precompile fallback and
Documenter search-index warnings remain nonfatal. Timings are collected separately
from verification; see the [performance guide](ivr_performance.md).

## Common physical result contract — 5 October 2026

The new `result_dict`, `write_result` and `read_result` API follows the static-AC
BMOPFTools result layout at revision
`39523e8a5cc5543e0f644ab2d135dd43ef4d8c01`. The [result contract](results.md)
specifies terminal and coil indexing, SI units, current/power signs, solver status,
snapshot ownership and unavailable quantities. The exact-IVR tutorial now executes
a physical-result extraction and JSON round trip.

Tests compare physical field paths and numbers across nine exact-IVR policy
combinations on two-, three- and four-wire chains. Additional checks exercise all
six result types, raw versus physical powers, native moment serialization,
unsuccessful diagnostic primals, changed-input refusal, parsed input, signed zero,
strict JSON nulls and NaN-preserving round trips. Independent prescribed electrical
states check IBR filter/PCC recovery, capacitor and shunt powers, ideal-ground
reactions, charged-line endpoint currents, regulators and multiwinding coil/port
quantities. Scalar and per-coil winding ratings have separate witnesses.

The optional live BMOPFTools panel compares nested bus, line, load, source and loss
field sets and values, and exchanges JSON through both libraries' writers and
readers. It does not establish equivalence for every device law or transformer
rating convention. Approximate and relaxed phasors remain labelled candidates;
unidentified source/ground allocation and delta circulation are never filled by
an arbitrary choice. Original-network export after separate topology preprocessing
and complete failed-candidate extraction for every relaxation remain documented
gaps. These are result-contract tests, not performance measurements.

## Adjacent-chain certificate and benchmark — 5 October 2026

The additive `:passive_chains` policy consumes surviving incident-line equations
once, composes exact unit-pivot substitutions, and rolls back incomplete or
support-expanding transactions. It preserves device/ground boundaries and
all original physical observations. The original nonadjacent mode is unchanged.
The proof uses induction on elementary inverse coordinate maps; it does not
assume that a mesh is radial or invert a line impedance.

New tests cover two-, three- and four-wire cases, all conductor specializations,
reversed lines and terminal permutations, and IDs that force the second bus to
use a different surviving equation. Arbitrary complex coordinate vectors verify
projection/reconstruction inversion and every removed KCL/KVL row; independent
solves verify both supplied-point directions and objective parity. Every
interior phase/pair/neutral/sequence bound family and both-end line I/S records
have negative witnesses. Forward/reverse power flow additionally isolates one
apparent-power endpoint at a time, preventing the other endpoint from masking
a missing constraint. Unshunted endpoint current magnitudes tie by KCL, so those
witnesses necessarily violate both current ends together.

A zero-impedance first step preserves an earlier bus bound's support, then a
nonzero-impedance second step would expand it. The selector detects the earlier
bound and rolls back the second step; maps match the untouched nonadjacent
reference. Tests also cover local mesh sections, zero impedance, retained
junctions, charging/device/ground refusals, impedance-load composition and
CP/generator P/Q/price updates. The fixed-total-impedance benchmark fixture
checks unchanged total demand, preserved limits, equal physical starts and
identical passive/chain maps on alternating-load controls.

Final regression: **36,561/36,561 assertions** (1,844 added), including the
endpoint-isolating tests. Documentation executes all **24 tutorial blocks**;
seven updated rendered pages and 733 local links/anchors pass inspection. The
known OpenDSSDirect precompile fallback and Documenter search-index-size warning
are nonfatal.

The [performance guide](ivr_performance.md) reports the balanced timing panel
and fresh-process confirmation: **576/576 measured solves** and **48/48 warm-ups**
pass across the two separately retained batches. Failures and slow samples are never dropped;
compilation has no weight in the primary Ipopt wall-time score. No device law,
control capability, default or existing transformation was removed. The greedy
certificate is not maximal, and charged pi sections remain outside it.

## Distinct P/Q histories and reactive-bound transitions — 5 October 2026

The new `examples/benchmark_ivr_histories.jl` provides reproducible single-phase
and delta dispatch paths without consecutive repeated operating points. Fixed-
and changing-box histories share absolute P/Q demand and price paths; the latter
fixes/releases P and Q, and removes/restores a Q lower bound. The reuse runner
adds physical-unit generator dispatch records. Its existing reversed/rotated
order generator is exposed and tested, and the wrapper records planned balance
before solving. No production equation, bound, option or default changes.

An initial driver typo stopped before any solve. The subsequent six-sweep first
case passed all 216 measured and 36 warm-up solves, but its order-balance gate
failed. The paired schedule requires twelve sweeps for six workflows. That
entire case and original sources are archived, excluded from the corrected
batch and not pooled. The amended design preserves inputs/settings, uses twelve
sweeps for all four cases and places every workflow in every position twice.
No observed solve time guided the correction; no failed solve was repaired.

The balanced batch admits **1,728/1,728 measured solves** and **144/144 excluded
warm-ups**. Every eligible scenario has matching objectives and passes independent
physical, own/fresh-model and reverse-anchor checks. Source/network snapshots,
shared history paths, start digests, both-side resets, added/removed sides,
physical-unit dispatch, sequence sums and actual balance pass a separate audit.
Reconstructed/previous-primal median sequence ratios are **0.942/0.954** for
single-phase fixed boxes, **0.978/0.986** for single-phase changing boxes,
**0.962/0.970** for delta fixed boxes and **0.919/0.932** for delta changing boxes
(full/regional respectively). Six of eight paired ranges cross one; all outliers remain.
The 1–8% median gains support a narrower recommendation than the earlier panel's
10–26%. These different histories do not isolate the effect of deleting repeats.

Regional/passive is about 24% faster than full under matched reconstructed-dual
starts on both single-phase histories. Delta formulation medians differ by less
than 0.2%. Zero-dual initialization nearly matches reconstruction on the changing
single-phase history, while it accounts for part of the delta changing-box gain.
The third delta Q channel exercises its negative lower bound under expensive
generation, and a price/bound-activity reversal coincides with a warm-start
iteration regression. See the [performance guide](ivr_performance.md) for all
three treatments, paired ranges and scope limitations. Ipopt wall time remains
primary; model preparation and helper overhead are excluded.

The full suite passes **34,717/34,717** assertions, including **2,464 new checks**
of distinct inputs, independent bounds, physical-unit dispatch, reactive-side
removal/restoration, dual resets, planned/actual order balance and admission.
The tutorial now contains 23 executable blocks, including construction and
inspection of a changing-box delta history. The inherited OpenDSSDirect
precompile fallback remains nonfatal. Plans and raw evidence stay outside Git.

## Explicit reconstructed-dual initialization — 5 October 2026

The example-only dual helper and `dual_workflows()` compare previous primals
with normal initialization, a zero-dual warm control and reconstructed-dual warm
initialization. The helper caches solution values before mutation, validates
same-model/coordinate/equation correspondence and resets both bound sides when
any generator box endpoint changes. New bound sides start at zero; removed
sides are discarded. Unsupported structural, non-price objective and non-CP
constraint changes are refused before dual assignments. No production equations,
bounds, defaults, component coverage or prior options change.

A prospectively declared screen admits 576/576 measured solves plus 144/144
excluded warm-ups on 20/100-segment single-phase and delta dispatch. Separate
balanced confirmation on the two 100-segment inputs admits 864/864 plus 72/72
warm-ups. Each of six workflows occupies every position twice. Reconstructed/
previous-primal sequence ratios are **0.851/0.898** for single-phase full/regional
and **0.743/0.759** for delta full/regional. Zero-dual controls are slower on
single-phase and only slightly faster on delta. Regional is fastest on
single-phase; the two reconstructed-dual formulations are within 1% on delta.
These repeated known inputs do not establish performance on unseen networks.

A separate balanced ENWL 435 feasibility transfer admits **54/60 attempted
measured solves** and **9/10 attempted warm-ups**. The zero-dual control fails
the strict status gate with `ALMOST_LOCALLY_SOLVED` on scenario 2 in all six
measured sequences and its warm-up; no physical-point audit is evaluated for
those rejected results. Twelve later measured and two later warm-up scenarios
are unattempted after rejection. The failed workflow is ineligible for ranking.
Previous-primal and reconstructed-dual sequences pass every admission check,
but reconstructed duals **regress about 5%**: 470.487 versus 448.236 ms per
complete sequence, ratio 1.050 and paired range 1.002–1.068. Lower iteration
counts do not guarantee lower Ipopt wall time. All failures and slower options
remain available; there are no repaired retries or relaxed acceptance settings.

The independent raw-data audit verifies source/scenario hashes, shared controls,
primal/dual correspondence, changed-box resets, sequence completeness, eligibility,
objective comparability and actual order balance. Across all seven reports,
1,494/1,500 attempted measured solves and 225/226 attempted warm-ups are admitted.
Ipopt wall time is primary; construction, updates, dual capture/assignment and
result audits are excluded. The helper's substantial feeder-side preparation
cost is reported separately; this is not an end-to-end performance claim.
The [performance guide](ivr_performance.md) includes scenario regressions,
post-hoc repeat-time sensitivity and the refined workload-specific shortlist.

The full suite passes **32,253/32,253** assertions, including 234 new dual
correspondence, changed-box, added/removed-side, refusal, zero-control and
workflow-setting checks. The tutorial now contains 22 executable blocks,
including a same-model reconstructed-dual example with independent physical
and fresh-model verification. The inherited OpenDSSDirect precompile
method-overwrite fallback remains nonfatal. Plans and raw evidence stay outside
Git; no production equations, bounds or defaults change.

## External feeder reuse and initialization transfer — 5 October 2026

The new `examples/benchmark_ivr_feeder_reuse.jl` wrapper writes source/scenario
provenance before solving and applies explicit CP demand factors `(1,1,0.9,1)`
to owned inputs. It retains source files, equipment, all operating bounds and
source/generator accounting. Other load laws remain fixed and are listed. The
study requires a feasibility objective; it makes no economic-dispatch claim.

Two prospectively declared contrasts use DSuite 1,220 and ENWL 435. One crosses
full/regional reused models with fixed/previous-primal starts; the other crosses
full/regional fresh/reused models with fixed starts. Each uses eight sweeps over
four workflows, every workflow in each position twice. All **512/512 measured
solves** and **64/64 excluded warm-ups** pass physical, own-model, independent
fresh-full/fresh-same-formulation and applicable reverse-anchor checks. All
measured scenarios have accepted reverse anchors. Source hashes, scenario
correspondence, explicit start digests, identity checks, complete-sequence timing
sums and actual order balance pass an independent audit. Batches are kept separate.

Previous-primal/fixed median sequence ratios are **0.819/0.831** for DSuite
full/regional and **0.846/0.840** for ENWL full/regional. Fixed-start reused/fresh
ratios in the separate lifecycle batch are **1.002/0.998** and **0.976/1.004**.
Initialization has the larger effect on these sequences; full is slightly faster
on DSuite and regional is faster on ENWL. Construction cost remains excluded
from the Ipopt wall-time assessment. All formulations and start policies remain
available, including the earlier small-case regressions.

A separate diagnostic admits **14/14 solves** while checking two-wire/delta
generator prices, fixed/released bounds and removed/restored bound sides. All observed
constraint types support dual-start attributes, but no dual initialization is
applied. Non-variable-bound row references are retained while bounds change.
All 12 post-initial updates mark the installed Ipopt wrapper for reconstruction
and the next solve creates a different internal problem object. This does not
measure reconstruction's time contribution or establish factorization reuse.
The [performance guide](ivr_performance.md) documents the installed wrapper's
bound-dual reconstruction and the reset/correspondence policy used in the
subsequent reconstructed-dual experiment.

The final suite passes **32,019/32,019** assertions, including 24 new checks of
absolute demand scenarios, unchanged non-CP loads, invalid schedules, source-file
integrity, provenance, feasibility-only scope, admitted solves and actual position
balance. The final runner corrects an inherited cost-accounting note in metadata;
the original timed files and the metadata-only diff are preserved. It changes
no solve or ranking. The guide, reference and tutorial explain reproduction,
source accounting and the boundary between model reuse and solver initialization.
Raw evidence, protocol, source snapshots and the updated handover/roadmap remain
outside Git. No production equations, defaults or component coverage changed.


## Model reuse and explicit previous-primal starts — 5 October 2026

The new `examples/benchmark_ivr_reuse.jl` runner crosses full/regional-passive
formulations, fresh/reused models and fixed/previous-primal starts. It holds
AMD and normal dual initialization fixed and ranks the median complete-sequence
sum of Ipopt wall seconds. Compilation, updates, extraction and audits are
excluded. Independent cumulative input edits and fresh same-formulation/full
models check parameter updates. Start digests, coordinate layout and reused
variable identity are checked explicitly. No core equation, bound, formulation
option or production default changes.

The full suite passes **31,995/31,995** assertions, including 121 new checks of
scenario-specific objective comparison, incomplete/failed-workflow exclusion,
independent input updates, fixed-zero and restored generator availability,
explicit start propagation, reused variable identity and physical/fresh-model
admission. The tutorial adds an executable previous-primal example.

A prospective four-case single-phase/delta screen gives **768/768 admitted
measured solves** plus 192 excluded warm-ups. An eight-sweep replication on the
two 100-segment cases gives another **768/768** plus 96 warm-ups. Its independent
order audit finds that eight reversed/rotated sweeps do not balance eight
workflow positions. Preserve that batch, document the protocol correction and
run a fresh 16-sweep confirmation: **1,536/1,536 admitted measured solves** plus
96 warm-ups, each workflow in each position twice. No failing solve is repaired;
all three timing batches and the design correction remain in the evidence.

In the final balanced batch, matched reuse/fresh median ratios range
**0.994–1.003**. Starts and iteration counts match for the same representation
and start policy. Previous-primal starts reduce regional/passive reused sequence
medians from **60.882 to 49.994 ms** for single-phase and **137.236 to 115.417 ms**
for delta. Fixed starts still matter: the small single-phase screen regresses
about 4% with previous-primal initialization, and individual scenarios can
regress even when the complete sequence improves. No primal-dual warm-start,
global-optimality, native-factorization-reuse or universal-speedup claim follows.

The [performance guide](ivr_performance.md) gives the complete protocol,
comparison table, paired ranges, numerical environment and measured scope.
`REUSE_PROTOCOL.md`, the three raw batches, frozen sources, digests and the
independent `REUSE_ANALYZE.py` audit remain outside Git. All 3,072 measured solves
and 384 excluded warm-ups pass; these are manufactured dispatch sequences,
not new coverage of real feeder updates, equipment models or transformations.


## Formulation–ordering interaction and factor-storage diagnostics — 5 October 2026

The empirical runner now accepts explicit per-candidate solver settings and
records their effective values after merging with shared controls. The new
`ordering_profiles` helper crosses existing formulations with MUMPS ordering
requests; `mumps_diagnostics` reads actual-order and factor-storage fields from
separate verbose logs. Core formulations, bounds, numerical defaults and all
alternatives remain unchanged. Ipopt wall time is the primary metric throughout;
construction and extraction do not enter the ranking.

The full suite passes **31,874/31,874** assertions, including 29 new checks of
solver-option propagation, unchanged formulation options, ordering requests,
diagnostic parsing and physically admitted solves. Documentation adds an
executable ordering example, bringing the tutorial to 20 blocks.

A prospective screen crosses full IVR, scaled regional passive and selected
regional passive with automatic/AMD/AMF/METIS/QAMD requests. DSuite 2,854 and
ENWL 538 retain their electrical data and use feasibility objectives. Four
exploratory reversed/rotated sweeps yield **120/120 admitted measured solves**
and **30/30 excluded warm-ups**. Among combinations admitted on both inputs,
regional/passive AMD minimizes the sum of per-input median Ipopt times:
0.324344 s versus 0.521555 s for regional/automatic and 1.159862 s for full/
automatic. These are selection-set measurements, not independent speed estimates.

Freeze this choice before comparing it against full/automatic, regional/automatic
and selected-regional/automatic on DSuite 1,220, ENWL 435 and two delta dispatch
price regimes. Eight balanced sweeps per case give **128/128 admitted solves**
and **16/16 excluded warm-ups**. With the same regional formulation, AMD median
ratios to automatic are 0.759, 0.806, 1.061 and 0.541 respectively. The expensive-
DER delta case changes from 17 to 10 iterations and reverses its earlier median
regression against full/automatic. A timing outlier gives individual AMD/full-
automatic ratios as high as 3.692 in that small case; this is not an every-run
speedup or a statistical-significance claim.

Full IVR benefits from AMD too. A separate matched-order comparison, declared
after the screen but before inspecting validation outcomes, fixes AMD on both
full and regional/passive models. Six fresh balanced pairs per case give
**48/48 admitted solves** and **8/8 excluded warm-ups**. Regional/full median
ratios are **1.032** (DSuite 1,220), **0.839** (ENWL 435), **1.127** (cheap-DER
delta) and **0.987** (expensive-DER delta). This isolates the representation's
contribution under the shared ordering: reduction helps some workloads and
hurts others. The [performance guide](ivr_performance.md) gives paired ranges
and keeps the two validation batches separate. No ratios combine unmatched
absolute times from different experiments.

Thirty separate native diagnostics and 30 excluded warm-ups all pass. Ipopt
3.14.19/MUMPS 5.9.0 reports actual order 2 for every automatic request on these
screening inputs; explicit 0/2/5/6 requests report the requested orders. Thus
METIS did not silently fall back here. On DSuite 2,854, full-model symbolic
wall time falls from 0.359 s to 0.037 s in the diagnostic when changing automatic
to AMD; reported maximum factor-double storage only falls from 2,845,020 to
2,769,162. For the regional model those values are 0.198→0.033 s and
2,707,370→2,685,997 doubles. The large timing change is not explained solely by
smaller factor storage. On ENWL, ordering also changes nonlinear iterations.

The parser preserves signed `INFO(9/10)` values and missing fields; reported
storage counts are not process peak memory or measured fill ratios. Native
timers are nested and rounded. The zero numerical-factorization field remains
an instrumentation limitation. These verbose runs are excluded from rankings.

The source/input digests, prospective protocol, raw trials and every diagnostic
log remain outside Git with the handover/roadmap. Shared controls retain
`tol=constr_viol_tol=1e-10`, `acceptable_iter=0`, `bound_relax_factor=0`,
`max_iter=500`, `max_cpu_time=30`; BLAS and Julia use one thread and GC stays
enabled. Only ordering requests vary within a fixed formulation. Dispatch
uses the previous explicitly manufactured circuit/price scenarios and shared
solver objective scaling 1000. All accepted objectives and physical/model
checks agree. No tests or documentation builds overlap numerical timings.

The refined starting profile is regional/passive with voltage ground scaling
and explicit MUMPS AMD. Full IVR + AMD is a strong alternative. Bound-support
selection remains optional: on ENWL 538 with AMD it takes 17 iterations versus
eight for unconditional regional elimination. No formulation or option is
removed. Parameter-update/warm-start comparisons, broader mixed-port
certificates and the earlier strict 844-bus/source-import issues remain open.

## Ipopt wall-time priority and held-out validation — 5 October 2026

The primary metric is now `ipopt_wall_s` / `fastest_ipopt`, measured by
`JuMP.solve_time` (`MOI.SolveTimeSec`). Inspection of the installed Ipopt.jl
1.16.0 source confirms an elapsed wall timer around its optimizer call, including
backend setup and `IpoptSolve`, excluding FormulationLab construction, prior
JuMP cache transfer, extraction and physical/model audits. Previous timings
included extraction; those records remain historical and are not relabelled.
Construction cost contributes nothing to the primary assessment. Every
transformation option and core default remains available and unchanged.

The final suite passes **31,845/31,845** assertions (13 additional checks).
The profile tests distinguish construction, wrapper/extraction and solver-only
winners and reject missing/nonfinite/negative timing records. The tutorial
adds an executable solver-timer example, bringing its total to 19 blocks.

The original five-input screen is rerun with the same 12-profile shortlist,
four measured sweeps and excluded warm-ups. **232/240 measured solves** and
**58/60 warm-ups** pass. The same two unscaled passive profiles fail ENWL's
physical KCL tolerance; all failures remain recorded. Among profiles admitted
on every input, the sum of median Ipopt wall times selects
`scaled_regional_passive` (0.520009 s versus full IVR's 1.128893 s). These are
selection-set observations, not an independent speed estimate.

Before inspecting validation results, freeze that common choice plus the
predeclared full, scaled-passive and selected-regional-passive alternatives.
Four held-out feeders use unchanged electrical data from DSuite SPD Rural (66),
DSuite SPD Urban (1,220), ENWL network_2_Feeder_4 (241) and
network_17_Feeder_6 (435). Hold-out refers to this selection panel, not all
previous project experiments. Eight reversed/rotated sweeps balance candidate
positions. **128/128 measured solves** and **16/16 excluded warm-ups** pass.
The frozen common profile's sum of per-case median Ipopt times is 0.311300 s
versus 0.403894 s full (22.9% lower), with lower medians on all four cases.
The [performance guide](ivr_performance.md) gives individual medians, spread,
competing winners and the aggregate weighting limitation.

A separate dispatch extension uses 20-segment single-phase and delta services,
constant-power loads at even buses, a bounded DER at the last bus and a priced
source. DER prices 0.2/2.0 are compared with source price 1.0 currency/kWh;
no colocated free source/generator ambiguity is introduced. All variants use
a shared cost objective and solver-only objective scaling 1000. **128/128
measured solves** and **16/16 warm-ups** pass physical/model gates and accepted
objective comparison. Common/full median Ipopt ratios are 0.835/0.838 for the
two single-phase cases and 0.367/1.569 for delta. Thus the expensive-DER delta
case reverses the speedup despite identical derivative structures across prices:
common/full iterations change from 10/18 to 17/11. No updated-model or global
optimality claim is made.

Four additional native timing diagnostics (full/common on DSuite 2,854 and
ENWL 538), each after an excluded warm-up, all pass. Ipopt 3.14.19 with MUMPS
5.9.0 attributes approximately 85–94% of native algorithm wall time to the
primal-dual system solver in these individual observations. They are excluded
from the rankings. Nested timing fields do not partition total cost, and a
0.000 s numerical-factorization field is not proof that no numerical
factorization occurred. Actual fill/memory attribution remains unresolved.

The environment and strict solver/physical tolerances match the previous study;
no tests, documentation builds or profiling overlap its timed experiments.
The primary ranking requires complete, finite, nonnegative Ipopt timings and
comparable accepted objectives. Missing historical timings withhold a winner.
All source/input digests, scripts, raw failures, reports, native timing logs and
the prospective protocol remain outside Git with the revised handover/roadmap.
No element, control, tap, temporal or update coverage is added here. Next work
should examine solver ordering/KKT structure and repeated-update behavior under
explicit operating regimes; the strict 844-bus and source-import issues remain.

## Best-evidence profiles and selector preparation — 5 October 2026

All transformation/reformulation options remain available, including alternatives
that are slower or fail on this panel. Defaults are unchanged. The new empirical
runner admits configurations only after strict solver, independent SI physical,
own-model, fresh-full-model and reverse-anchor checks. It retains failures,
requested/effective options, input and runner digests, solver/environment details,
derivative structures, iterations, allocations, GC time and raw timings.
Objective disagreement beyond the declared tolerance withholds a winner.
The [performance guide](ivr_performance.md) gives the explicit recommendation,
reproduction procedure and workload limits.

The final suite passes **31,832/31,832** assertions, including 26 new checks of
failure/incomplete-profile exclusion, objective comparability, separate workload
rankings, balanced pair order, evidence serialization and physical/model mapping.
Documentation executes all 18 existing tutorial blocks. This change extends
measurement and preparation efficiency, not element or parameter-update coverage.

### Unchanged selector decisions with less preparation

The selector now indexes a conservative superset of possible series-elimination
targets, composes affected bound rows once, and shares substitution-resolution
caches only within one before/after phase. The actual bound compiler still
visits every original bound. Against a frozen `9f0a8f0` implementation,
**204 exact construction comparisons** preserve every constraint function/set,
objective, start, power coefficient, coordinate map and full selection report.
Cases cover two/three/four conductors, bounded/unbounded/rated/zero-impedance/mesh
variants, finite grounding, all conductor settings and both selection/scaling
choices. This build-only audit does not assert feasibility of every fixture.

A separate implementation ablation uses passive elimination, bound-support
selection and voltage ground scaling in both variants. Each of ten case/mode
combinations has one excluded warm-up per variant and six alternating-order
pairs. All **120 measured solves**, **60 paired comparisons** and **20 warm-ups**
pass their physical/model gates. Every pair has identical maps, selection reports
and derivative structures; bidirectional model and physical-channel checks are
outside timers.

| Input / coordinates | Median paired build-byte ratio | Median paired solve ratio | Median paired total ratio |
|:--|--:|--:|--:|
| DSuite 265, full | 0.932 | 1.003 | 0.973 |
| DSuite 265, regional | 0.934 | 0.989 | 0.782 |
| DSuite 2,854, full | 0.928 | 0.994 | 0.807 |
| DSuite 2,854, regional | 0.929 | 1.002 | 0.965 |
| ENWL 538, full | 0.925 | 0.990 | 0.975 |
| ENWL 538, regional | 0.927 | 0.994 | 0.876 |
| Synthetic impedance, full | 1.000 | 0.992 | 0.993 |
| Synthetic impedance, regional | 1.000 | 0.995 | 1.027 |
| Synthetic alternating loads, full | 0.886 | 0.985 | 0.940 |
| Synthetic alternating loads, regional | 0.882 | 0.988 | 0.936 |

Ratios are new/frozen-old within pairs, followed by medians. Build allocations
fall about 6.5–7.5% on the external feeders and 11–12% on the alternating-load
synthetic cases. The no-series-candidate control allocates identically. Total
ratios over all individual pairs range from 0.138 to 17.294 with GC enabled;
solve medians are nearly unchanged. Allocation savings are stronger evidence
than a general timing claim. These ratios must not be multiplied by earlier
study ratios to claim a cumulative speedup.

### Screen, freeze and confirm complete profiles

The 12-profile screen uses three unchanged electrical inputs from
`BMOPFDraftData`: `output/DSuite/original/DSuite_SPD_Suburban.json`,
`output/DSuite/original/DSuite_SPM_Suburban.json`, and
`benchmarks/ENWLbenchmark/reduced/Network_8_Feeder_2.json`. Two synthetic
40-segment four-wire cases place impedance loads at all downstream buses or
only the even-numbered buses. The objective is explicitly feasibility; legacy
reader provenance is detached without altering electrical data.

Four exploratory measured sweeps per case yield **232/240 accepted solves**,
with **58/60 accepted excluded warm-ups**. Two unscaled passive profiles fail
ENWL's physical KCL check at about 2.2083e-5 A against 1e-6 A; their failed records
are retained. The screen selects a common profile by minimizing the sum of
per-case median build-plus-solve times among profiles admitted on all five
inputs. `scaled_regional_passive` wins this declared common-workload criterion.

That common choice, each case's screen winner and full IVR are frozen before
six new balanced repeats: **90/90 measured solves** and **15/15 excluded warm-ups**
pass. The summed confirmation medians are 0.972433 s versus 1.622977 s for full
IVR (40.1% lower). This is a sum of per-case medians, not a timed batch, and its
weighting is dominated by larger cases. Small synthetic cases regress under
the common profile. Case-local rankings change in two cases between screen and
confirmation. See the performance guide for the full table and timing spread.
No universal optimum or statistical significance is claimed.

Both experiments run on Apple M4, Julia 1.12.6, JuMP 1.31.2, Ipopt.jl 1.16.0,
one Julia thread and one BLAS thread. Ipopt uses `tol=constr_viol_tol=1e-10`,
`acceptable_iter=0`, `bound_relax_factor=0`, `max_iter=500`, `max_cpu_time=30`.
Warm-ups, audits and study selection overhead are outside candidate timers;
`total_study_s` separately records portfolio overhead. No tests, documentation
builds or profiling overlap the final timings. This is a feasibility experiment,
not a general dispatch, global-optimality, or updated-model reuse result.

Raw screen/confirmation records, frozen baseline, 204-case audit, source
snapshots, input hashes and logs remain outside Git with the handover and roadmap.
An earlier instrumentation pilot is separately preserved and excluded from these
results. The known OpenDSSDirect precompilation fallback and nonfatal Documenter
search-index warning do not invalidate the successful checks. Broader mixed-port
certificates, factorization-aware selection, the strict 844-bus failure and
unbounded source-import examples remain unresolved.

## Conservative series selection by operating-bound support — 5 October 2026

`series_selection=:bound_support` optionally retains a structurally eligible
series bus when its tentative elimination increases the coordinate support
width of any affected operating-bound expression. It uses the compiler's
shared bus-voltage bound visitor and the assembler's current/apparent-power
limit records. Impedance substitution is unchanged; default `:all` retains
existing choices. The [contract](ivr_nlp.md#Series-selection-by-bound-support)
and [theory](ivr_theory.md#4.1.-Conservative-selection-by-operating-bound-support)
distinguish this local proxy from actual derivative/factorization sparsity.

The default suite passes **31,806/31,806** assertions, including **360 new checks**.
These cover all 11 voltage-bound field families, apparent-power bounds at both
line orientations, two/three/four conductors, terminal permutations, all conductor
settings, rejection rollback followed by neighbour selection, accepted sparse
sections, exact supplied-point reconstruction and mixed CP/generator reuse with
active finite-ground scaling. A zero lower-voltage rating correctly contributes
no constraint to the selector. Both selection choices retain every original
operating bound; a rejected reduction changes no physical constraint.

A separate build-only audit freezes the previous `328f3b8` builder and its
bus-bound compiler. Across all seven fixed transformer families and three mixed
static-device fixtures, all three objectives and conductor settings give
**90 exact comparisons**: every constraint function/set, objective, start and
stored power coefficient agrees at zero tolerance after aligning variable indices.
This checks unchanged default construction after introducing the shared bound
visitor; it is not a feasibility claim for those mixed fixtures.

A matched experiment compares `series_selection=:all` and `:bound_support`
within the same implementation. Both use `linear_elimination=:passive`,
`ground_scaling=:voltage` and an explicit feasibility objective. Three external
inputs retain their electrical data; two synthetic 40-line four-wire cases
have impedance loads at every bus or at alternating buses. For each full/regional
combination, one excluded warm-up per variant precedes six balanced
alternating-order pairs. Ipopt uses `tol=constr_viol_tol=1e-10`,
`acceptable_iter=0`, `bound_relax_factor=0`, `max_iter=500`, `max_cpu_time=30`,
and single-thread BLAS. Physical, own-model, both cross-model, fresh-full-model
and observation-channel checks lie outside timers. No tests, documentation
builds or profiling overlap timed trials.

All **120 measured solves** and **60 paired comparisons** pass those gates;
all 20 excluded warm-up solves pass their own physical/model and fresh-full
checks. ENWL's unchanged finite grounding is scaled in both variants, so these
results do not relabel the previously rejected unscaled runs below.

| Input / conductor mode | Selected buses: all → support | Real variables: all → support | Median paired solve ratio | Median paired total ratio | Median paired build-byte ratio |
|:--|--:|--:|--:|--:|--:|
| DSuite 265, full | 42 → 42 | 2,926 → 2,926 | 1.007 | 1.072 | 1.136 |
| DSuite 265, regional | 42 → 42 | 2,854 → 2,854 | 0.998 | 1.069 | 1.131 |
| DSuite 2,854, full | 496 → 496 | 30,764 → 30,764 | 0.995 | 1.217 | 1.149 |
| DSuite 2,854, regional | 496 → 496 | 30,364 → 30,364 | 0.997 | 0.818 | 1.142 |
| ENWL 538, full | 19 → 0 | 9,226 → 9,530 | 0.727 | 0.777 | 1.046 |
| ENWL 538, regional | 19 → 0 | 8,190 → 8,456 | 1.005 | 1.021 | 1.057 |
| Synthetic impedance, full | 0 → 0 | 652 → 652 | 1.014 | 1.016 | 1.000 |
| Synthetic impedance, regional | 0 → 0 | 572 → 572 | 0.999 | 0.992 | 1.000 |
| Synthetic series + impedance, full | 20 → 0 | 332 → 652 | 0.988 | 0.973 | 0.995 |
| Synthetic series + impedance, regional | 20 → 0 | 292 → 572 | 1.010 | 1.063 | 1.156 |

Ratios are bound-support/all, computed within pairs before medians. Total
includes build and solve/extraction. Forty/twenty impedance-load substitutions
remain selected in the respective synthetic inputs; external inputs select no
impedance loads. The rule preserves the same DSuite series reductions but adds
about 13–15% construction allocations there. The no-series-candidate synthetic
control allocates identically under both policies because the bound index is
never built.

Rejecting the ENWL series reductions decreases unique Hessian entries from
16,124 to 14,878 in full coordinates and 11,678 to 11,210 regionally, while unique
Jacobian entries increase from 78,358 to 79,326 and 67,404 to 68,222 respectively.
For the synthetic alternating-load case, full-coordinate Hessian entries fall
from 2,440 to 880 (regional: 1,474 to 800), while Jacobian entries rise from
5,508 to 6,322 (regional: 4,356 to 5,278). These are backend structures before
solver preprocessing, not factorization fill or native memory measurements.

The full-coordinate ENWL solve/total medians improve about 27%/22%, but regional
ENWL and regional synthetic total medians regress about 2% and 6%. Thus the rule
reduces some measured Hessian structures without establishing general runtime
benefit. Construction cost matters even when selections are identical. With GC
enabled, individual total ratios range from 0.066 to 5.536 across accepted pairs;
six pairs, three selected feeders and two related synthetic cases do not support
statistical significance or population claims. This is an explicit structural
comparison policy, not a calibrated automatic cost model. It does not establish
that prior regressions against elimination-off have all been removed.

Raw runners, input digests, default construction audit, every warm-up/trial,
source snapshots and logs remain outside Git. Default selection stays `:all`.
Future selection needs to account for preparation, Jacobian/Hessian interactions
and actual factorization cost, rather than relying on bound support alone.

## Finite-ground voltage scaling — 5 October 2026

`ground_scaling=:voltage` is now an opt-in numerical policy for retained free
voltages at one-terminal finite shunts. It composes invertible diagonal scaling
with the existing reconstruction maps and normalizes circuit rows in those
solver coordinates. No finite ground is replaced, no equation or bound is
removed, and the default remains `:off`. See the [contract](ivr_nlp.md#Finite-ground-numerical-scaling),
[equivalence argument](ivr_theory.md#5.-Invertible-finite-ground-scaling) and
[analytical tutorial](tutorial_exact_ivr.md).

The Julia 1.12.6 default suite passes **31,446/31,446** assertions (2m12.6s),
including **1,261 new checks**. Independently calculated two-wire impedance-load
states cover weak, stiff, complex and signed grounds at two power bases, all
three conductor settings and all three linear-elimination settings. Tests check
unchanged physical electrical rows, dimensions, objective values, both point
mappings, retained intermediate neutral/source-current bounds and reuse after
CP/generator updates. Fixed and ideal voltages, weak/zero scalar shunts,
multi-terminal shunts and multiple shunts sharing a terminal exercise the scope.

A fixed-state witness adds ``10^{-3}/Y_g`` V to a source-neutral voltage with
``Y_g=-\mathrm{j}10^{10}`` S while leaving every current observation unchanged.
This creates a 1 mA physical KCL error. The old normalized model check accepts
that state; the scaled model and unchanged SI auditor reject it. This is a
numerical-accuracy regression test, not an infeasibility claim for the circuit.

The original ENWL 538 regional/series failure is reproducible in a separate
12-configuration probe. Either current-unit circuit equations or diagonal
voltage scaling with transformed row normalization makes that configuration
pass the unchanged physical audit. The implemented latter policy additionally
reduces the large grounding coefficient presented to the solver. These probes
support the scaling diagnosis; they do not establish a universal choice of
scaling or a performance advantage over all alternative numerical policies.

A separate same-version experiment fixes `linear_elimination=:passive` and
compares ground scaling off/on on three unchanged external electrical inputs,
in full and regional conductor modes. It uses one excluded warm-up per variant
and six balanced alternating-order pairs, single-thread BLAS, explicit
feasibility objective, Ipopt `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, `max_iter=500`, and `max_cpu_time=30`. Independent physical,
own-model, both cross-model, fresh-full-model and channel checks lie outside
timers. No tests, documentation builds or profiling overlap measured trials.

Of **72 measured solves**, all **36 scaling-on** solves and **30 scaling-off**
solves pass their own-model and physical checks. The six rejected baselines
are all ENWL 538 regional/series runs. All 36 candidate states also pass a fresh
full model and their corresponding unscaled model. All six rejected baseline
states fail the scaled model's normalized check as well. There are **30 accepted
pairs** for timing comparisons; rejected baselines do not supply speed ratios.

| Input / conductor mode | Scaled terminals | Accepted solves: off / on | Median paired solve ratio | Median paired total ratio | Median paired build-byte ratio |
|:--|--:|:--:|--:|--:|--:|
| DSuite 265, full | 0 | 6 / 6 | 0.996 | 0.789 | 1.0002 |
| DSuite 265, regional | 0 | 6 / 6 | 1.020 | 1.015 | 1.0002 |
| DSuite 2,854, full | 0 | 6 / 6 | 0.998 | 0.982 | 1.0002 |
| DSuite 2,854, regional | 0 | 6 / 6 | 0.989 | 1.112 | 1.0002 |
| ENWL 538, full | 1 | 6 / 6 | 1.464 | 1.396 | 1.044 |
| ENWL 538, regional | 1 | 0 / 6 | — | — | — |

Ratios are scaling-on/off, computed within pairs before medians. Total includes
construction and solve/extraction. DSuite inputs have no scaling targets:
unchanged coordinates and numerical equations make them no-target controls,
not evidence of a scaling speed benefit. Broad GC-sensitive total ratios even
in these controls (0.217–4.564 across pairs) illustrate timing variability.

ENWL selects only source-neutral voltage, with scale ``5.768533333\times10^{10}``.
Its regional/series maximum KCL residual is ``2.208336038\times10^{-5}`` A without
scaling and ``2.842170943\times10^{-14}`` A with scaling, repeated across all six
measured runs. The SI tolerance remains ``10^{-6}`` A and finite susceptance
remains ``-10^{10}`` S. The already-accurate full-coordinate case is slower:
solve median increases about 46%, total about 40%, and build allocations about
4.4%. Scaling is consequently retained as an opt-in accuracy policy. No broad
runtime advantage, optimality improvement or memory-saving claim is warranted.
Dimensions and backend derivative sparsity are unchanged by scaling.

This evidence addresses the earlier **538-bus regional/series physical failure**.
It does not establish a resolution of the separate 844-bus strict-acceptance
failure or of the unbounded source-import examples below. General coupled-shunt
scaling, transformer-ground scaling and automatic policy selection remain
outside this change. Raw probe/benchmark scripts, input digests, trials,
failures, source snapshots and logs remain outside Git. The historical rejected
runs below remain part of the evidence; they have not been relabelled accepted.

## Local impedance and degree-two elimination — 5 October 2026

Two independent opt-in settings are implemented: `linear_elimination=:impedance_loads`
substitutes exact impedance-load coil currents, and `:passive` additionally
eliminates eligible nonadjacent device-free degree-two buses between unshunted
lines. Both compose with conductor specialization and retain the complete
physical circuit/observation records. Only defining solver equalities and
coordinates are removed; all original operating bounds use reconstruction.
Defaults remain off. See the [contract](ivr_nlp.md#Local-linear-elimination),
[proof](ivr_theory.md) and two new [tutorial examples](tutorial_exact_ivr.md).

The default Julia 1.12.6 suite passes **30,185/30,185** assertions (1m57.2s),
including **1,330 new checks**. They cover one- through four-conductor impedance
loads, pure-Z ZIP/exponent-two laws, zero and signed demand, all conductor modes,
reverse line orientation, terminal permutations, meshes, unequal lengths, zero
impedance, mixed CP/generator reuse and conservative boundary retention,
including declared zero-demand devices. Fixed-state
negative tests retain intermediate phase/neutral/sequence voltages and both
selected/surviving segment ratings. Perturbed eliminated currents and voltages
are rejected by reconstruction, without solving or fitting. All **16 executable
tutorial blocks** pass, including independent analytical impedance current and
a tightened neutral-voltage bound at an eliminated intermediate bus.

A matched experiment compares elimination off/on in the same implementation,
with one excluded warm-up per variant and six balanced alternating-order pairs,
using single-thread BLAS and a separate explicit feasibility objective. Three
external inputs retain their electrical data; two generated 40-line four-wire
cases use impedance loads at every bus or at alternating buses. These generated
cases are labelled synthetic, not original feeder results. Physical, own-model,
both cross-model and observation-channel checks lie outside timers. There are
**108 accepted measured solves** in nine case/mode combinations; the tenth
combination is retained as a rejected warm-up. Tests, profiling and documentation
builds do not overlap the timed experiment.

| Input / conductor mode | Real variables: off → on | Median paired solve ratio | Median paired total ratio | Median paired build-byte ratio |
|:--|--:|--:|--:|:--|
| DSuite 265, full | 3,430 → 2,926 | 0.881 | 1.230 | 1.068 |
| DSuite 265, regional | 3,346 → 2,854 | 0.877 | 0.741 | 1.065 |
| DSuite 2,854, full | 36,716 → 30,764 | 0.651 | 0.660 | 1.080 |
| DSuite 2,854, regional | 36,242 → 30,364 | 0.662 | 0.765 | 1.078 |
| ENWL 538, full | 9,530 → 9,226 | 0.490 | 0.536 | 1.081 |
| ENWL 538, regional | 8,456 → 8,190 | — | — | Rejected physical audit |
| Synthetic impedance, full | 892 → 652 | 1.119 | 1.095 | 1.133 |
| Synthetic impedance, regional | 812 → 572 | 1.080 | 1.048 | 1.046 |
| Synthetic series + impedance, full | 772 → 332 | 1.085 | 1.335 | 1.536 |
| Synthetic series + impedance, regional | 692 → 292 | 0.926 | 1.118 | 1.262 |

Ratios are elimination-on/off, calculated within pairs before taking medians.
Total includes construction and solve/extraction. All three external inputs use
`:passive` and have no impedance loads selected: the change there is series
elimination. The synthetic impedance case uses `:impedance_loads`; the alternating
case uses `:passive` and exercises both passes. The 2,854-bus case eliminates
496 intermediate buses and reduces unique Jacobian entries from 159,826 to
140,914 without conductor specialization (163,070 to 143,662 with regional mode).
Those are backend structures before solver preprocessing, not factorization fill.

The measured large-feeder solve medians improve about 34–35%, and total medians
about 24–34%. These are promising descriptive results, not a general speed
claim. Construction allocations increase about 6–8% on accepted external cases
and 4–54% on the synthetic cases. The synthetic series/impedance case has fewer
variables but a larger unique Hessian structure: 880 to 2,440 entries in full
coordinates. All four synthetic total medians regress. Individual total ratios
range from 0.228 to 18.344 across accepted pairs with GC enabled. Six pairs,
three selected external feeders and two related synthetic designs do not
establish statistical significance or population-wide performance. Allocated
bytes exclude native solver memory and peak resident memory.

**Retained failure.** Combined regional/series elimination on ENWL 538 returns
`LOCALLY_SOLVED` but fails independent source-neutral KCL: approximately
``2.21\times10^{-5}`` A against a ``10^{-6}`` A audit tolerance. A separate
repeat reproduces it. Both its own model and a fresh full model accept that
same point under their normalized residual checks (maximum approximately
``5.3\times10^{-16}``). The input contains a finite grounding susceptance of
``-10^{10}`` S. The observation exposes a gap between scaled-model residuals and
physical current acceptance on this stiff-ground circuit; it does not justify
replacing the finite ground with an ideal one or relaxing acceptance. The point
remains rejected and contributes no accepted timing ratio. The experiment's
legacy `strict_warmup_rejection` label denotes its combined acceptance gate;
solver status alone was successful in this case.

Raw scripts, input digests, warm-ups, trials, failures, a separate ENWL diagnostic,
source snapshots and logs remain outside Git. The known OpenDSSDirect method-
overwrite precompilation error falls back to successful loading and passing
reference comparisons. Charged pi sections, adjacent chain elimination and
mixed-port/device-boundary elimination remain outside the new certificate;
no element, control, temporal or equipment-update coverage is added.

## Avoiding unused real/reactive power copies — 5 October 2026

The default Julia 1.12.6 suite again passes **28,855/28,855** assertions
(2m15.5s). Exact IVR still builds and retains every complex power polynomial
``S_k=V_k\overline{I_k}``. Separate real and imaginary copies are now made only
for the load, generator, source and inverter families that consume them in the
device loop. Previously the compiler also made unused copies for line ends,
switches, capacitors and transformer terminal/coil observations. Their stored
complex powers, result extraction and all voltage/current/apparent-power bounds
are unchanged. No coordinate, constraint, objective or update API changes.

A separate build-only audit compares the frozen `ed5d249` builder and candidate
on all seven fixed transformer families (including multiwinding) and three
mixed static-device fixtures with two, three and four conductors. It covers
all three objectives and all three specialization settings: **90 comparisons**.
After mapping variables by index, every constraint function and set, objective,
start value and stored power coefficient matches at zero tolerance. The mixed
fixtures include bounded generators, source apparent-power limits, rated closed
switches, capacitors and filtered IBRs with availability, DC-link bounds and
internal-voltage setpoints. This establishes unchanged model construction;
the audit does not assert feasibility or successful solves for these fixtures.

A controlled same-process ablation uses three external feeders, full and
regional modes, one excluded warm-up per variant and six balanced
alternating-order pairs with single-thread BLAS. The explicit objective is
feasibility; input electrical data are unchanged. All **72 measured solves**
pass independent physical, own-model and both cross-model checks. Every pair
also passes the zero-tolerance comparison of all constraint functions/sets,
objective, starts and reported power coefficients, together with exact equality
of electrical records and matching variable/constraint/derivative counts.
Validation is outside the timers. No tests, profiling or documentation builds
run concurrently with the timed experiment.

| Input / mode | Build allocation MB: old / new | Median paired build-time ratio | Median paired total-time ratio |
|:--|--:|--:|--:|
| DSuite 265 buses, full | 54.56 / 49.80 | 0.682 | 0.802 |
| DSuite 265 buses, regional | 57.06 / 51.90 | 0.957 | 0.982 |
| DSuite 2,854 buses, full | 555.44 / 503.93 | 0.959 | 0.978 |
| DSuite 2,854 buses, regional | 576.01 / 523.17 | 0.921 | 0.955 |
| Reduced ENWL 538 buses, full | 177.63 / 165.12 | 0.948 | 0.986 |
| Reduced ENWL 538 buses, regional | 186.73 / 170.31 | 0.942 | 0.987 |

Allocation values are separate medians in decimal MB; ratios are new/old within
pairs. Total includes build and solve/extraction. The experiment times cloned
internal build entry points; the public wrapper and its error translation are
unchanged and excluded from these timers. Complete-build allocation falls
approximately **7–10%** on this panel. Both variants include the preceding
neutral-index, affine-emission and exact-zero passivity changes. This measures
one additional preparation change, not a cumulative speedup estimate.

Median paired total times improve in all six sampled case/mode combinations,
but individual build ratios range from 0.116 to 2.839 with GC enabled. Solve
medians range from 0.940 to 1.008 of baseline despite identical models. Six pairs
on three selected inputs do not establish a general runtime or statistical
significance claim. Allocated bytes exclude native solver memory and peak
resident memory. These separate feasibility experiments do not repair earlier
source-import failures or add element, bound or update coverage.

The retained baseline profile samples full builds at probability 0.005; it
identified power splitting and constraint expression construction among the
allocation sites. Sampling attributions are diagnostic observations, not total
allocation estimates. The earlier build-only prototype is retained separately;
the table uses the complete paired build/solve experiment. Scripts, frozen
baseline, input hashes, versions, raw trials, coefficient audits and logs remain
outside Git. The known OpenDSSDirect precompilation error falls back to successful
loading and passing reference tests.

## Exact-zero line-passivity preparation — 5 October 2026

The default Julia 1.12.6 suite passes **28,855/28,855** assertions (2m01.1s),
including **600 new checks** of passivity boundaries and SOC constraint emission.
Electrical assembly now accepts an exactly zero scaled line impedance or
admittance matrix as passive without an eigendecomposition. Every nonzero
matrix retains the previous test on its scaled Hermitian part, with the same
zero threshold. No approximately zero coefficient is discarded.

For a line matrix ``M``, dissipation has the form

```math
\operatorname{Re}(x^H Mx)=x^H\frac{M+M^H}{2}x.
```

When ``M=0``, this quantity is identically zero for every ``x``; the previous
eigenvalue test also accepts it. Series impedance and both end-shunt admittances
must still all pass before the line is labelled passive. Absent line charging
provides the motivating case: both shunt matrices are exactly zero. This avoids
preparation work without changing circuit rows or the SOC nonnegative-line-loss
inequality. The tests cover one to four conductors, both per-unit scales, each
of the three matrix positions, signed zeros, positive and singular dissipation,
pure reactance, tiny negative dissipation and nonreciprocal imaginary coupling.
They also inspect whether the precise SOC line-loss constraint is present with
physical projections enabled or disabled.

A same-process ablation against frozen assembly from `ec99700` compares three
external feeders in full and regional modes. Each case/mode excludes one
warm-up per variant, then measures six balanced alternating-order pairs with
single-thread BLAS. The explicit objective is feasibility; input electrical
data are unchanged. All **72 measured solves** pass independent physical,
own-model and both cross-model checks. Every pair has exactly equal assembled
rows, KCL, devices (including passivity flags), limits, fixed coordinates and
scaling data, plus equal variable, constraint and backend derivative counts.
Validation lies outside the timers. Tests and documentation builds do not run
concurrently with timing experiments.

| Input / mode | Build allocation MB: old / new | Median paired build-time ratio | Median paired total-time ratio |
|:--|--:|--:|--:|
| DSuite 265 buses, full | 56.48 / 54.56 | 1.010 | 0.997 |
| DSuite 265 buses, regional | 58.98 / 57.06 | 1.019 | 1.006 |
| DSuite 2,854 buses, full | 576.39 / 555.30 | 1.038 | 0.989 |
| DSuite 2,854 buses, regional | 596.97 / 576.01 | 0.675 | 0.877 |
| Reduced ENWL 538 buses, full | 183.28 / 177.63 | 1.009 | 0.979 |
| Reduced ENWL 538 buses, regional | 192.39 / 186.74 | 1.327 | 1.122 |

Allocation values are separate medians in decimal MB; ratios are new/old within
pairs. Total includes build and solve/extraction. Full-build allocation falls
approximately **3–4%**. Separate assembly-only measurements fall from **10.40
to 8.48 MB** (265 buses), **103.05 to 82.09 MB** (2,854 buses), and **26.79 to
21.14 MB** (538 buses), approximately **18–21%**. These separate stage
measurements are not additive components of the timed public build. Respectively,
263 of 264, 2,872 of 2,873 and all 537 lines have zero shunts at both ends;
none has zero series impedance. The selected panel consequently favours this
shortcut and does not represent all feeder types.

Median paired solve ratios range from 0.988 to 1.019. Individual build ratios
range from 0.142 to 4.087; GC remains enabled. The largest regional case's total
median improves about 12%, whereas the regional ENWL total regresses about 12%.
These six-pair observations establish an allocation saving on the selected
inputs, not a general speed benefit or statistical significance. Allocated
bytes exclude native solver memory and peak resident memory. The experiment
uses a separate feasibility objective and does not resolve the earlier strict
source-import failures or expand element/bound coverage.

An explicitly derived control sets `G_from_1_1=G_to_1_1=1e-8` on each
linecode or inline line, making every assembled line matrix nonzero. Eight
balanced assembly-only pairs per feeder retain exact electrical equality and
have allocation ratios of exactly one. Median time ratios are 1.019, 1.477 and
0.988; long GC events affect the first two controls. A separately retained
sensitivity run requests full GC outside the timer before each assembly:
its corresponding medians are 1.002, 0.998 and 1.003, with allocations still
unchanged. This supports negligible direct overhead in that diagnostic; it
neither replaces the original GC-enabled results nor establishes general
end-to-end performance. Derived controls are not original-feeder solve results.

Raw scripts, frozen assembly, source hashes, versions, warm-ups, paired trials,
controls and logs remain in the local evidence directory outside Git. An
allocation sample at probability 0.02 on the preceding assembly attributes
3,471 sampled allocations and 585,608 sampled bytes to the passivity expression;
these are sampled observations, not total allocation estimates. The known
OpenDSSDirect precompilation error again falls back to successful loading and
passing reference tests.

## Assembly-local neutral-role preparation — 5 October 2026

The default Julia 1.12.6 suite passes **28,255/28,255** assertions (2m13.7s),
including **190 new checks** of neutral-role discovery and reuse. The electrical
assembler already discovers a bus-to-neutral map. Fixed and multiwinding
transformers and capacitor banks now consume that same map instead of scanning
the network again. LinIVR loss preparation also uses the assembled map.
Standalone device plans and reconstruction retain local discovery when no map
is supplied. Every new assembly discovers roles afresh; there is no persistent
cache or new input-mutation contract.

For an unchanged input, each lookup returns the same neutral terminal as a
fresh invocation of the classifier. Connection matrices, grounding stamps,
physical observations and operating bounds therefore retain their coefficients.
Before this change, role discovery inside electrical assembly scanned the
network ``1+2T+3W+C`` times, where ``T`` counts fixed two-sided transformers,
``W`` counts all multiwinding ports and ``C`` counts capacitor banks. It now
scans once. This counts assembly role discovery only, not every preflight or
public-build operation. Tests exercise all seven transformer families, repeated
devices, renamed terminals, authoritative conventions, input immutability and
rejection of newly ambiguous declarations after an earlier successful build.

A same-process ablation against frozen routines from `bfc2d0c` uses three
external inputs, full and regional modes, one excluded warm-up per variant and
six balanced alternating-order pairs. BLAS uses one thread. Electrical inputs
are unchanged; the explicitly selected objective is feasibility. All **72
measured solves** pass independent physical, own-model and both cross-model
checks. Every pair has exactly equal assembled equations, KCL rows, device
records, limits, fixed coordinates and scaling data, together with equal
variable, constraint and backend derivative counts. Validation runs outside
timers; timing runs do not overlap tests or documentation builds.

| Input / mode | Build allocation MB: old / new | Median paired build-time ratio | Median paired total-time ratio |
|:--|--:|--:|--:|
| DSuite 265 buses, full | 57.19 / 56.48 | 0.989 | 0.984 |
| DSuite 265 buses, regional | 59.70 / 58.98 | 1.327 | 1.170 |
| DSuite 2,854 buses, full | 653.79 / 574.18 | 0.816 | 0.915 |
| DSuite 2,854 buses, regional | 674.44 / 596.97 | 0.827 | 0.928 |
| Reduced ENWL 538 buses, full | 183.28 / 183.28 | 1.359 | 1.056 |
| Reduced ENWL 538 buses, regional | 192.39 / 192.39 | 1.291 | 1.061 |

Allocation values are separate medians in decimal MB; ratios are new/old within
pairs. Total includes build and solve/extraction. The 2,854-bus input has ten
fixed transformers: assembly role scans fall from 21 to one. A separate
assembly-only measurement falls from **180.52 to 103.05 MB**, approximately
**43%**, in both modes. Full-build allocation falls approximately **11–12%**
by median paired ratios. The 265-bus input has one transformer: its separate
assembly allocation falls from 11.12 to 10.40 MB, but the regional timing
regresses. The ENWL control has neither transformers nor capacitors: allocations
are effectively unchanged (80 additional bytes), while sampled total time rises
about 6%. Separate assembly measurements are not additive components of the
timed public build.

Median solve-time ratios lie between 0.995 and 1.001. Build timings remain
GC-sensitive: individual paired ratios range from 0.446 to 6.349 across the
panel. These six-pair observations support reduced preparation allocation on
transformer-rich inputs, not a universal speedup or statistical significance
claim. Allocated bytes exclude native solver memory and peak resident memory.
The selected external inputs do not measure capacitor- or multiwinding-heavy
performance; those paths have regression coverage. This experiment does not
resolve the earlier source-import failures or expand element/bound coverage.

A preceding prototype skipped exact-zero matrix coefficients before sparse-row
accumulation. Eight balanced assembly-only pairs per feeder preserved all rows
but gave an allocation ratio of exactly one on all three inputs; the prototype
was not adopted. Raw scripts, frozen baselines, hashes, versions, warm-ups,
trials and logs remain in the local evidence directory outside Git. The known
OpenDSSDirect precompilation error again falls back to successful loading and
passing reference tests.

## Sparse affine expression preparation — 5 October 2026

The default Julia 1.12.6 suite passes **28,065/28,065** assertions (2m03.6s),
including **132 new expression checks**. Exact IVR and LinIVR now accumulate
sparse linear rows directly into a fresh complex JuMP affine expression. They
previously allocated a scaled expression for each row term before summation.
The numerical reference/reconstruction evaluator is unchanged. This modifies
preparation, not the circuit equations, conductor coordinates, objective,
operating bounds, input domain or update API.

For affine coordinates ``z_k(x)=a_k^T x+b_k`` and a circuit row ``c``, the emitted
polynomial remains

```math
\sum_k c_k z_k(x)
=\left(\sum_k c_k a_k\right)^T x+\sum_k c_k b_k.
```

This is an unconjugated linear combination. Tests compare its coefficients,
constant and numerical values against independently assembled dense coefficients.
They cover complex coefficients, cancellation, constant/empty rows, vector views,
repeated coordinate objects and mutations of the returned expression. Each
result is owned independently; neither input rows nor shared coordinate
expressions can be mutated by accumulation. The complete suite exercises this
helper through LinIVR, full and specialized exact IVR, device laws, operating
bounds, supplied-point reconstruction and update paths.

A controlled same-process ablation compares the old and new emitters on three
external feeders in full and regional modes. Each case/mode excludes one
warm-up per variant and measures six pairs in balanced alternating order with
single-thread BLAS. All inputs retain their electrical data; the explicitly
chosen objective is feasibility. Independent physical and both cross-model
checks pass for **72 measured solves**. All variable, constraint and backend
Jacobian/Hessian counts match. A further **12 production-method confirmation
solves** pass physical/model checks and retain those counts without the
experimental switch. No timings run concurrently with tests or documentation.

| Input / mode | Build allocation MB: old / new | Median paired build-time ratio | Observed build-ratio range |
|:--|--:|--:|:--|
| DSuite 265 buses, full | 65.60 / 57.53 | 0.912 | 0.129–2.624 |
| DSuite 265 buses, regional | 68.46 / 60.02 | 0.947 | 0.927–1.981 |
| DSuite 2,854 buses, full | 743.32 / 655.74 | 0.826 | 0.584–1.588 |
| DSuite 2,854 buses, regional | 768.67 / 678.48 | 0.808 | 0.626–1.381 |
| Reduced ENWL 538 buses, full | 224.61 / 184.17 | 0.679 | 0.393–2.135 |
| Reduced ENWL 538 buses, regional | 239.33 / 193.17 | 0.394 | 0.279–1.672 |

Allocation values are separate medians in decimal MB; ratios are new/old within
pairs. Build allocation falls approximately **12–19%** in the controlled
ablation; the production-method checks confirm the saving. Julia allocated
bytes exclude native solver memory and peak resident memory. GC is included in
timings and contributes to their broad ranges. Solve-time ratios are near one;
the full 538-bus case's median paired total time increases about 5% despite the
lower median build-time ratio. Consequently these observations support an
allocation improvement, not a general runtime or solver-speed guarantee.
Six pairs and three selected inputs do not provide a statistical significance
or population claim. This repeats the preparation workload under a separate
feasibility objective, not the earlier source-import optimization study.

Raw scripts, hashes, versions, warm-ups, trials and confirmation results remain
in the local evidence directory outside Git. An earlier exploratory run partly
overlapped focused-test compilation and is retained separately; its timings
are not used above. The known OpenDSSDirect method-overwrite precompilation
error still falls back to successful loading and passing reference comparisons.
It is not changed by this optimization. Earlier regional timing results below
describe the older emitter.

## Regional performance and coordinate ablation — 5 October 2026

The expanded experiment uses `examples/benchmark_ivr_regions.jl`: one excluded
warm-up pair per case, then six balanced alternating-order pairs with strict
Ipopt tolerances, single-thread BLAS, fresh builds and unloaded starts. Physical,
own-model, cross-model and objective checks lie outside the timers. The runner
retains failures, raw timing/allocation observations and within-pair ratios.
Inputs and evidence remain outside Git; production equations and coordinates
are unchanged by this experiment.

Of eight source-import cases, four pass the warm-up and all six measured pairs.
The other four are retained as rejected warm-ups. A separately labelled
feasibility experiment passes three of those four cases. Thus **84 measured
solves** pass all gates across seven case/objective combinations. These include
related/reduced variants and are not seven independent feeder designs.

| Input and explicit objective | Buses | Median solve ratio | Median total ratio | Observed total-ratio range |
|:--|--:|--:|--:|:--|
| DSuite SPD Suburban, import | 265 | 1.078 | 0.944 | 0.336–1.624 |
| DSuite SPM Suburban, import | 2,854 | 1.007 | 1.054 | 0.956–1.137 |
| ENWL network 23 feeder 3, import | 59 | 0.920 | 0.972 | 0.166–0.990 |
| Reduced DSuite SPD Suburban, import; no selected region | 178 | 1.001 | 1.025 | 0.231–1.540 |
| Reduced ENWL network 8 feeder 2, feasibility | 538 | 0.377 | 0.497 | 0.403–0.610 |
| ENWL three-wire Kron variant, feasibility | 844 | 0.955 | 1.356 | 0.793–1.506 |
| ENWL three-wire phase-neutral variant, feasibility | 844 | 0.954 | 1.025 | 0.823–1.285 |

Ratios are regional/full, calculated per pair before taking the median. Total
includes build and solve/extraction; it excludes validation. GC remains enabled
and contributes to the wide observed ranges. Six pairs are descriptive evidence,
not a significance test. In particular, the 2,854-bus result reverses the earlier
small total-time improvement. No general speed benefit is established. The
538-bus feasibility result is promising for that workload but is not an accepted
source-import optimization result. Regional build allocation increases by about
2–9% across these cases, including detector overhead in the fallback control.

**Fewer variables can produce more derivative entries.** On 265 buses, variables
fall from 3,430 to 3,346 while unique backend Jacobian entries rise from 14,528
to 15,168. On 2,854 buses the corresponding counts are 36,716 to 36,242 and
159,826 to 163,070. On the 59-bus uniform feeder both variables and Jacobian
entries fall. These are structures before solver preprocessing, not factorization
fill or memory. The separate large-feeder stage pass takes approximately 17 ms
for certification and 3 ms for maps; assembly and GC are more prominent in the
sampling profile. These separate measurements are diagnostic, not additive
components of the timed public build.

A process-local prototype retained physical voltages while reducing only line
currents. It passes 24 measured solves on the two DSuite cases, reduces Jacobian
entries relative to differential voltages, but leaves them above full-IVR counts.
It does not recover the two rejected cases included in that ablation. Timing
variation and inconsistent gains do not justify changing production coordinates;
the prototype remains only in local experimental evidence.

**Failure interpretation.** The two mixed three-wire inputs have unrestricted
colocated generators and sources. Separate feasibility witnesses allow increasing
each generator phase by ``t`` W and decreasing source injection by the same
amount. Phase injections cancel; the existing unbounded ideal-ground return
can absorb any neutral imbalance. All downstream states remain unchanged and the import objective falls
by ``3t`` W. Eight fixed-state witnesses (four per input, up to ``t=10^7`` W)
pass independent physics and both full/regional models. The absence of limiting
source/generator bounds establishes an unrestricted decreasing direction; Ipopt's
`NORM_LIMIT` status alone would not establish this. Source files are unchanged.

The original 844-bus bounded-generator input returns `ALMOST_LOCALLY_SOLVED`
in both modes even under the separate feasibility objective. Diagnostic raw
iterates pass the ordinary physical/model audit tolerances, but residuals around
``3.2\times10^{-9}``–``3.8\times10^{-9}`` exceed the requested ``10^{-10}``
solver threshold. The largest physical residuals are source-bus KCL. These
iterates remain rejected; audit tolerances and strict acceptance are not
interchangeable. The reduced 538-bus source-import comparison similarly lacks
strict regional acceptance, despite its successful separate feasibility study.

The runner's **17 smoke assertions** cover accepted-only arithmetic, retained
failures, invalid arguments, balanced order, profiles and JSON output. All
**14 executable tutorial blocks** and documentation checks pass. The existing
**27,933-assertion** production gate belongs to the preceding implementation
checkpoint; it is not a new test count for this benchmark-only change.

## Exact IVR pendant-region specialization — 5 October 2026

The default Julia 1.12.6 suite passes **27,933/27,933** assertions (test summary
2m35.5s), including 2,398 new regional checks. The old whole-section option
retains its scope and regression behavior. `:conductor_regions` is a separate
opt-in certificate for disjoint pendant interiors behind retained boundary
buses. It does not reduce through transformers, switches, earth paths or mixed
conductor junctions. See the [proof](ivr_theory.md#Pendant-region-certificate)
and [public contract](ivr_nlp.md#Pendant-regions-inside-a-larger-network).

Independent SI witnesses deliberately give the upstream retained line a nonzero
conductor-current sum. Full and regional models accept the same states in both
directions. Tests cover two/three/four-wire regions, mixed boundary subsets,
cycles and parallel edges, multiple sources, every fixed transformer family,
open/closed switches, voltage-dependent demand, capacitors, generators and
static IBRs. Fixed-state probes cover boundary/interior voltage and sequence
limits, neutral magnitudes, both ends of selected and retained line ratings,
and delta-generator limits. Current perturbations cannot be repaired by
projection. Demand reuse retains model variables and the certificate.

This exercise found a shared initialization defect: a finite phase-earth shunt
could seed zero voltage before propagation reached it from a fixed source.
Fixed-source/ideal-ground references now propagate first; finite grounds seed
only conductor components still unreached. The changed starts affect neither
physical admittance nor KCL. Regression cases that failed strict solver
acceptance from the old starts now pass. One ideal winding comparison had a
separate full-model restoration failure; the composition fixture now explicitly
uses finite leakage. Ideal winding behavior remains covered elsewhere, and no
unique bond/ground current allocation is assumed.

A bounded repeat of the earlier 83-entry local panel assessed 41 networks,
refused 31 unsupported/invalid inputs and left 11 above the 3,000-bus cap
unassessed. Regional certificates select lines in 15 entries, including 10
where the whole-section certificate declined. Several entries are related
variants; this is not a count of independent feeder designs.

Three original DSuite inputs also pass strict full/regional solves, independent
physics, model checks, both cross-model directions and objective agreement:

| Buses | Selected lines | Regions | Real JuMP variables: full → regional |
|--:|--:|--:|--:|
| 66 | 4 | 4 | 882 → 874 |
| 265 | 42 | 29 | 3,430 → 3,346 |
| 2,854 | 237 | 152 | 36,716 → 36,242 |

These experiments preserve electrical inputs and explicitly use source-import
minimization. The 66-bus case is effectively unloaded; the two larger cases
have nonzero demand. Already-present input reductions are inherited. The
single-run timings include compilation/order effects and do not establish a
speed benefit.

A separate run excludes one warm-up per mode and feeder, then measures five
alternating-order full/regional pairs. All 20 measured solves pass physical,
model, cross-model and objective-agreement gates. Validation runs outside the
timed intervals. Median times in seconds are:

| Buses | Build: full / regional | Solve: full / regional | Total: full / regional |
|--:|--:|--:|--:|
| 265 | 0.03893 / 0.02507 | 0.03360 / 0.03707 | 0.07253 / 0.06235 |
| 2,854 | 0.40725 / 0.38413 | 0.65755 / 0.68316 | 1.09439 / 1.07209 |

Total medians need not equal sums of component medians. Both solve medians
increase; total medians decrease by approximately 14% and 2%, respectively.
Five pairs on two feeders provide no general speed guarantee or statistical
significance claim. The demonstrated result is broader applicability with
fewer variables and preserved physical states. Raw cases, digests, diagnostics
and timings remain in the user's local evidence directory outside Git. The
known OpenDSSDirect method-overwrite precompilation error still falls back to
successful loading in the complete regression suite.

## Exact IVR voltage-dependent demand — 5 October 2026

The voltage-law extension adds **2,461 assertions**: 2,335 manufactured-state,
solve, bound, domain, input and update checks, and 126 assertions against
18 OpenDSS circuits. The default Julia 1.12.6 suite passes **25,535/25,535**
assertions. The known OpenDSSDirect precompilation issue still falls back to
successful loading; reference comparisons pass. The new executable tutorial
compares all five laws at an identical fixed voltage, separate from the suite
count. Counts here supersede earlier dated milestones below.

Independent SI witnesses cover single-phase, three-wire delta and four-wire
wye loads; unbalanced P/Q; positive, zero and reverse demand; two power bases;
full/reduced representations; fractional, zero and negative exponents; and
terminal reordering. Holding each state fixed, tests violate its load-current
law, matched voltage bound, line current bound or auxiliary squared-voltage
binding. Mixed invalid updates leave valid constant-power entries unchanged.
Pure-Z witnesses check zero current at zero coil voltage while preserving KCL
and power in the deliberately invalid point. This found an independent-auditor
gap: power alone did not identify zero-voltage impedance current. Equal engineering magnitude bounds also have
60 checks that ensure constant power factors add no redundant fixed auxiliary. Scalar ZIP
broadcasting in that auditor was also corrected.

OpenDSS comparisons cover all three connections and laws at 0.85 and 1.08 pu,
with a series line, matching source phasors and coil nominal voltages. They
compare load power, downstream phasors and line input current. DSS ZIP dropout
is disabled and all points stay inside its declared model voltage thresholds;
no claim is made for the different low/high-voltage substitutions documented
in the [OpenDSS load reference](https://dss-extensions.org/dss-format/Load.html).
The local 2,815-network inventory contains 334,486 constant-power load entries
and no explicit current/ZIP/exponential entries. It therefore supplies no
new-law feeder validation or performance conclusion.

All five native static load laws and seven fixed transformer families are now
implemented within documented restrictions. General nonlinear load powers
require a positive bound on the **actual coil voltage** or a fixed nonzero
source coil; nominal voltage supplies no such certificate. Pure impedance laws
retain their linear current equations at zero. This is an explicit applicability
domain, not full deenergized-load behavior or full schema coverage. Controls,
optimized taps, external DC and time-series semantics remain outside scope.
Region-wise conductor specialization and broader reusable parameter APIs also
remain future work.

## Exact IVR fixed regulators — 5 October 2026

The default Julia 1.12.6 suite passes **23,074/23,074** assertions (test summary
2m36.9s). The regulator package adds 3,471 analytical, perturbation, bound,
refusal and solve checks, plus 60 assertions against eight OpenDSS fixed
circuits; two former unsupported-family checks are retired. The OpenDSSDirect
precompilation warning described below persists, with successful fallback
loading and reference-test completion.

Both type-A/type-B fixed gains, all three open-delta connections, optional
neutral, single-phase implicit earth and nonneutral common conductors are
covered. Tests vary leakage, excitation location, power base and power-flow
direction. Grounding cases distinguish unique voltages from possibly nonunique
bond/earth current allocations. Explicit bond-current observations bind the
supplied exact-IVR point; older formulation observations retain only physically
identifiable audit relations. Side-current negative tests tighten individual
entries while holding the physical state fixed.

The OpenDSS comparison uses explicit shared nodes and a documented conversion
from native leakage ohms to fixed two-winding parameters. It compares output
phasors and source complex power, not regulator-controller behavior or a
universal interpretation of connection labels. A read-only scan of transformer
entries in the earlier 2,815-network local dataset inventory found only
single-phase and delta–wye types, so it supplies no regulator feeder evidence.
The executable tutorial now includes an analytical fixed-gain example and an
output-current bound violation. No regulator performance claim is made.

All seven fixed transformer families are now accepted by exact IVR. The
remaining static load-law package is constant-current/ZIP/exponential demand;
controls, optimized taps, external DC and time-series semantics remain outside
scope. Every transformer still causes conductor-specialization fallback. This
checkpoint supersedes the earlier scope statements below; their dated results
remain historical evidence.

## Exact IVR static components and reusable models — 4 October 2026

At implementation commit `ac89168`, the default Julia 1.12.6 suite passes
**19,545/19,545** assertions (test summary 2m26.6s). This includes 1,657 new static
IBR checks. Documentation builds pass. OpenDSSDirect still reports its existing
method-overwrite precompilation error, falls back to loading without the cache,
and its oracle tests pass. The dated counts below describe earlier milestones.

The exact-IVR validation separates four kinds of evidence:

| Claim assessed | Reproducible evidence | Limit of inference |
|:--|:--|:--|
| Local coordinate identities and conditional network equivalence | `test/compiler_algebra_tests.jl`, `test/compiler_network_tests.jl` | Narrow declared certificate, not mixed-section/transformer composition |
| Physical equations and port conventions | independently manufactured SI states; fixed-transformer and capacitor OpenDSS tests | Stated native circuits, not universal schema or hardware equivalence |
| Operating bounds retained | `test/ivr_bound_coverage_tests.jl`, switch/capacitor/IBR suites hold states fixed and violate one limit | Implemented inventory; future fields require new tests |
| Reusable updates preserve the problem | fresh/reused solves, objectives, variable identity and bidirectional supplied-point checks | No implicit warm-start/factorization claim or universal speedup |

The [equation chapter](ivr_theory.md) states the equivalence assumptions and
source map. The [tutorial](tutorial_exact_ivr.md) runs its analytical, full/reduced,
fresh/reused, generator-price, inverter-loss and refusal checks during every
Documenter build, using `examples/tutorial_exact_ivr.jl`. Tutorial assertions
are a documentation gate, separate from the dated default-suite count above.

An exploratory local panel used 18 ENWL inverter snapshots (30–538 buses,
28–302 single-phase inverters). Explicitly removing their unsupported control
records on owned copies produced changed static-capability scenarios. Of 36
initial full/reduced solves, 32 passed strict acceptance; four full 538-bus runs
returned ALMOST_LOCALLY_SOLVED and remained rejected. Disabling acceptable
termination and raising the iteration limit from 300 to 600, with the same
1e-10 tolerances, produced four strictly accepted retries. Physical/model checks
passed and retry objectives agreed with the reduced counterparts. These results
are local experimental evidence, not a repository CI gate, raw controlled-input
support, a global certificate or a performance conclusion. The user's planning
documents and raw panel evidence remain outside Git; the portable synthetic
tutorial supplies the repository's reproducible demonstration.

No omitted operating bound was found in the implemented native inventory;
negative tests and independent decoding provide evidence rather than a proof
of completeness for all possible schema fields. Fixed regulators/autotransformers,
constant-current/ZIP/exponential loads, control profiles, optimized taps, external
DC and time-series semantics remain outside exact-IVR scope.

## ENWL generation-cost comparison — 30 September 2026

The complete 128-file ENWL reduced-topology panel (5–538 buses) compares
generation-cost-minimising LinIVR, Kron-reduced LinDist3Flow and BMOPFTools'
four-wire nonlinear IVR. All three solve 127 cases. The main panel explicitly
consolidates each priced `grid` generator with its otherwise unpriced source;
five as-supplied audits retain the original artificial export-credit behavior.
Original DER prices and bounds are preserved. Prices receive a common positive
numerical scaling, and costs are independently reconstructed in original units.

On 118 paired converged four-wire replays, median feeder-maximum magnitude
errors are 0.0615 V versus 0.8658 V for phase-to-neutral voltage and 0.0237 V
versus 2.002 V for neutral-to-ground voltage (LinIVR versus LinDist3Flow).
The latter has no neutral state and is assessed using its imposed zero-neutral
assumption. Its Kron projection also discards neutral current ratings; both
model changes remain explicit findings.

Both approximations understate the nonlinear reference cost by a median 4.20%.
Among 115 paired replays passing the assessed operational checks, the median
replayed cost excess is 0.195% for LinIVR versus 0.845% for LinDist3Flow.
Three converged LinDist3Flow replays fail assessed limits; no converged LinIVR
replay does. Solver failures and near-convergence statuses are retained and
excluded from paired accuracy statistics. Nonlinear optimality remains local,
and the solution checker retains its unassessed dimensions.

The panel required LinDist3Flow to accept omitted/one-sided reactive generator
bounds, without adding artificial Q limits. Eleven new regressions and the full
**6,842/6,842** suite pass. The reproducible runners are
`examples/benchmark_enwl_cost.jl` and `examples/report_enwl_cost.py`.
The report, figures, aggregate JSON and compressed complete observations are
under `examples/results/enwl_cost_comparison_2026-09-30.*`.

## Explicit-neutral LinIVR experiment — 30 September 2026

After the coverage expansion, the Julia 1.12.6 default suite passes
**6,831/6,831** checks, including 439 dedicated LinIVR checks. The documentation
site builds successfully. OpenDSSDirect emits its existing precompilation
warnings and runs its tests without the cache.

The initial Julia 1.12.6 default suite passed **6,518/6,518** checks after extracting
the shared solver-independent IVR circuit assembler. The first 126 LinIVR checks
cover analytical neutral displacement and finite grounding, per-unit and
rotation invariance, dispatch/loss objectives, zero-reference neutral limits,
constant-impedance references, singular/unsupported inputs, coupled four-wire
lines, delta loads, endpoint shunts, a parallel circuit and a fixed transformer.

The coverage expansion adds 313 checks for all seven fixed transformer families,
tap changes and reversed flow, exact impedance aliases, delta coil dispatch,
current-only reference freedom, transformer loss identities and all three static
inverter topologies. It tests an affine internal-power budget that is exceeded
by the actual filter power, so that limitation remains visible. The independent
checker accepts `physical_residuals(input, result::LinIVRResult)` and selects the
appropriate delta coil convention automatically.

The optional BMOPFTools comparison covers 18 synthetic scenarios and three
existing ENWL cases without applying neutral Kron reduction. Nonlinear replay
exposes a voltage-limit violation in a stressed case accepted by LinIVR. See
[the formulation and experiment](linivr.md); these checks establish neither
universal approximation accuracy nor AC-feasible dispatch guarantees.

The expanded panel contains 73 transformer cases with independently constructed
and physically validated AC references, plus seven BMOPFTools PCC comparisons:
three inverter topologies at a fixed source and on an unbalanced feeder, and an
unbalanced delta generator. The loaded references are validation data only.
Delta P/Q and current ratings follow BMOPFTools' coil convention; existing SDP
conductor semantics are unchanged. The inspected nonlinear comparator does not
stamp the inverter filter/internal-power extensions, which are tested separately.
Raw observations and limitations are retained in
`examples/results/linivr_coverage_2026-09-30.json` and its Markdown companion.
All 73 transformer approximations solve, with maximum conductor phasor error
0.359 V on this panel. All seven device replays report `LOCALLY_SOLVED` and pass
the comparator's assessed solution checks; replayed device dispatch differs from
the requested dispatch by less than ``2\times10^{-8}`` VA. These results do not
extend to untested limits or certify AC feasibility of the approximate states.

## Branch-flow milestone — 21 September 2026

The `BranchFlowSDP` checks cover analytical radial optima, coupled unbalanced
meshes, multiple sources, endpoint line shunts, fixed open/closed switches,
capacitors, wye and delta generators, explicit-neutral matrix KCL, all supported
load laws and advanced voltage maps. Explicit and line-derived LNCs are
exercised. Every fixed transformer connection is covered, including a general
three-winding hyperedge, leakage, excitation, neutral grounding, galvanic bonds,
declared current limits, mixed line/transformer topology and reversed component
declaration. Common cases compare objectives and voltages against `IVRSDP`, and
the independent AC validator checks recovered states where rank permits. The
suite also retains permuted/partial device-map regressions and malformed-input
applicability checks, including permuted delta dispatch, partial/permuted
multiwinding maps, scalar phase-voltage bounds, inert open-switch model size and
declaration-independent line orientation. Paper-derived regressions exercise
parallel-line cross-voltage consistency and the strengthening from
apparent-power/voltage bounds to total endpoint and shunt-corrected
series-current limits. The shared LNC regressions also cover IVR derivation from
`s_max`, while operational P/Q-box tests discriminate applied/skipped
voltage-current RLT domains. Closed-switch and multiwinding-coil regressions
check matching-voltage inferred current limits. Static IBRs remain an
intentional refusal.

The Julia 1.12.6 default suite passes **6,353/6,353** checks. OpenDSSDirect still
emits the precompilation warnings recorded below and then runs its oracle tests
without the cache.

These comparisons establish the implemented static component contracts and
several radial/meshed agreement cases; they do not establish universal
equivalence to `IVRSDP`, scalable performance, or AC feasibility of an arbitrary
recovered moment solution. The branch-flow formulation uses local
current-voltage blocks plus a conditional global voltage Gram, whereas `IVRSDP`
lifts a global eliminated current-voltage system.

## Static AC containment milestone — 11 September 2026

The new [AC containment audit](ac_validation.md) adds 1,102 passing checks to
the default suite (4,634 total on Julia 1.12.6). The first 1,097 of these new
checks also pass on Julia 1.10.11; the five additional passive/missing-observation
checks were run on Julia 1.12.6. The optional BMOPFTools/Ipopt transformer audit
passes 180 assertions on 12 compatible reference cases. Nine incompatible
reference states and four reference initialization failures remain explicit
findings, not passing coverage. The table below records earlier milestones.

| Check | Result |
|---|---|
| Default suite, Julia 1.10.11 | 3,527 passed, no skips |
| Default suite, Julia 1.12.6 | 3,532 passed, no skips |
| Optional MosekTools analytical SDP suite | 1,986 passed |
| New fixed-transformer OpenDSS comparisons (included above) | 42 passed |
| Documenter build and cross-reference checks | Passed |
| Separate BMOPFTools replay integration | 46 passed |
| Historical PowerOptLab adapter check (adapter subsequently removed) | 7 passed |
| Core package loading without a solver | Passed |
| Runtime/default-test dependency audit | No BMOPFTools, PowerOptLab, or Mosek dependency |
| PowerOptLab tracked diff whitespace check | Passed |

The default suite runs the migrated coefficient, component, applicability,
SI/per-unit, IEEE feeder, and OpenDSS oracle checks, plus new PowerIO-boundary,
callback, schema-spelling, independent-island, generic API, and SDP checks. The transformer extension adds 98 analytical and
contract checks plus 42 independent OpenDSS checks at unity and non-unity taps.
Mosek is isolated in `test/optional/Project.toml` and uses the same SDP tests.

The 46 replay checks were executed separately using the sibling PowerOptLab
Julia environment. The entire PowerOptLab test suite was not rerun; its
then-proposed forwarding API and nonlinear replay were checked by seven
integration checks. The adapter was subsequently removed from the PowerOptLab
PR; PowerOptLab has no FormulationLab dependency.

OpenDSSDirect 0.9.9 emits constructor-method/precompilation warnings on Julia
1.12.6 and falls back to loading without its cache. Its oracle tests nevertheless
run and pass. The Julia 1.10.11 suite also passes.

Clarabel 0.11.1 with OrderedCollections 2 reproduced an indexed-OrderedSet failure
in chordal PSD completion. The default optional Clarabel factory disables chordal
decomposition for this dense reference. Explicitly supplied optimizer factories
retain their own settings. No claim about a performance-optimal profile is made.

The static AC extension adds analytical grounding, switch/capacitor, inverter,
voltage-limit and load-envelope checks, plus 36 three-winding OpenDSS comparisons.
A non-star four-winding case checks coupled leakage independently.

A combined three-phase fixed inverter setpoint and delta-capacitor fixture exposed
Clarabel numerical sensitivity. Fixed P/Q boxes now compile as single equalities,
and source-fixed internal magnitude equations are not duplicated. The combined
regression checks optimal status and its analytical power result at the default
Clarabel settings, as well as with optional Mosek. Near-optimal statuses remain
unpublished as optimal results. These local encoding fixes are not a general
performance or reliability guarantee for the dense representation.

These tests establish the migrated L3F contracts and the declared static AC SDP
models and envelopes. They do not establish complete BMOPF coverage, scalable SDP performance,
rigorous numerical lower-bound certificates, or AC feasibility of a recovered
SDP voltage candidate.

The LNC extension adds 1,766 checks of normalized coefficients, rank-one validity,
fixed SOC projections, explicit interphase/winding domains, diagnostics, automatic
line-angle bounds, shunt correction and neutral/mutual coupling. Automatic cuts
are opt-in and preserve the original problem domain; explicit operating domains
are distinguished in diagnostics. No unbalanced benchmark-wide gap or speedup
claim follows from these unit and analytical checks.

The warmed comparison script on the analytical two-bus case returned approximately
10,429.8183 W with and without automatic LNCs, with maximum scaled constraint
violations below 4e-8. The pair added nine linear constraints (including its
magnitude/sector domain) and no variables: four scalar variables in both models.
This already-exact case demonstrates consistency, not an OPF gap improvement.

The fixed SOC extension removes iterative separation, adds bounded complex
three-map projections and constant-power secants, and audits propagated physical
bounds. Its regressions cover complex projection validity, unchanged model size
across a solve, deterministic triplet budgets, phase-pair ordering, phase-only
source/line limits, and three-wire generator/converter conductor powers. The
five additional budget checks were also run in the focused Julia 1.12 SOC suite.
The Mosek and replay counts above are prior checks, not reruns of this extension.

## Broader NLP / SOC panel — 11 September 2026

A size-stratified sample of 12 of the 128 reduced ENWL feeders (5–538 buses)
was compared with six DistributionTestCases inputs. Both engines received the
same BMOPFTools-normalized input, with source generators removed, taps fixed,
control laws omitted, and a source-import objective. One BLAS thread and small
warm-up cases were used; timings are single observations, not repeated estimates.

| Panel | Ipopt NLP | Default Clarabel SOC |
|---|---|---|
| 12 ENWL feeders | 12 locally solved, no error-level post-solve findings | 4 optimal, 5 almost optimal, 3 construction-budget failures |
| Two 907-bus LV snapshots | Both locally solved, about 0.07 s solve time | Neither completed within its 240 s process budget |
| Modified IEEE 13 / IEEE 123 | Both rejected missing converted line impedances | Same input failures |
| Modified IEEE 34 | Locally infeasible with nameplate caps | Slow progress |
| CIGRE test case | Locally infeasible with nameplate caps | Optimal; no feasible NLP reference for an original-input gap |

The 538-bus ENWL NLP took 0.24 s to build and 0.39 s to solve. SOC construction
already took 54 s at 140 buses. Bounded retries at 178, 241 and 538 buses stopped
in construction; their 240 s process budgets include startup and warm-up.

Fixed Kim strengthening reached optimal status on 3 of the 9 completed ENWL
comparisons. It reduced the 45-bus gap from 20.7 W to 9.0 W but increased total
time from 47 s to 71 s. Modestly relaxed stopping tolerances recovered optimal
status on 3 of 5 almost-optimal default-SOC cases, but did not address build cost.

The transformer `s_rating` interpretation materially affects the imported
comparisons. In **separate derived-input diagnostics**, removing those fields
made both CIGRE and IEEE 34 NLPs locally solved with no error-level findings.
CIGRE then had a numerical NLP-minus-SOC objective gap of 1006.7 W on a 1.837 MW
import (0.055%); IEEE 34 SOC still returned slow progress. Restoring IEEE 13's
explicitly stated missing line impedance allowed model construction but did not
produce a successful solve with its original nameplate caps. The IEEE 123
converter also warned that a delta–delta transformer was dropped: these imported
outcomes cannot establish feasibility of the unchanged DSS circuits.

The full report and numerical evidence are in
`examples/results/nlp_soc_combined_2026-09-11.md` and its JSON companion.
`examples/README_nlp_soc_experiments.md` documents the runners, bounds on execution,
controlled changes and interpretation caveats. These numerical objectives are
not certified global bounds; Ipopt results are local candidates, and solver
status alone does not establish physical equivalence across input conventions.
