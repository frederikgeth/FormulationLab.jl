# Verification

## Paired voltage-law timing — 6 October 2026

Full regression passes **97,223/97,223 assertions**, including 129 new checks for
matched options, independent ownership, strict benchmark admission and common
nameplate bounds in the full reference. Mixed physical policies are refused.
The production equations, solver timer and package defaults are unchanged.

Both frozen batches complete **2304 measured trials and 192 warm-ups**. All
1152 lifted trials and 96 lifted warm-ups pass. Original mode passes 576/1152
trials and 48/96 warm-ups; all 624 rejected solves remain explicit. Failed
profiles have no survivor-only timing median. Eligibility agrees across batches.
Independent QA verifies inputs/frozen source, all options, position balance,
reference policy, admission gates and 128 eligible paired contrasts. Objective
reconstruction error is below 5.92e-10 and within-cell spread below 1.91e-10.
Timing is isolated and ranks only Ipopt wall time, excluding compilation.

The [study](ivr_load_power_timing.md) reports conditional benefits and slowdowns.
Full/reduced power lifting are close for cost; reduced power with reuse is the
tracking shortlist. Passive elimination/cap-four restrictions are inactive on
this feeder. Original preflight/campaign admission differences remain an open
sensitivity question; no failed historical trial is relabelled.

## Voltage-law power lifting — 6 October 2026

Full regression passes **97,094/97,094 assertions**, including **3916 new checks**
for exact auxiliary recovery, signed/zero loads, bases, connections, existing
lifting modes, JSON exports and tightened bounds. All **96 external preflight
combinations** pass with `load_power_lifting=true`, including the 22 previously
rejected arms. All **384 bound witnesses** reject and all 48 tracking endpoints
retain the active inherited nameplate cap. The original mode remains the default.

Thirty-six manufactured first/second derivative checks pass. A larger derivative
attempt was stopped for diagnostic cost; its partial discrepancy flags remain
and are not claimed as a passed audit. Solver-only counterfactuals and original
failures remain explicit. No timing campaign is run. See the
[scientific study](ivr_load_power_lifting.md) for scope and limitations.

## Three-phase transfer and explicit nameplates — 6 October 2026

The full suite passes **93,178/93,178 assertions**, including **4868 new checks**.
The new `transformer_nameplate=:bmopftools` policy adds ordinary-transformer
`s_rating` bounds at the correct rated ports, while retaining the previous
`:ignore` policy and all numerical options. Independent analytical witnesses
cover six families, reverse flow, two bases, lifting and current elimination.
An active-cap dispatch example and SI exports agree with the live BMOPFTools
reference in **108 optional integration assertions**. Its supplied-zero rejection
corrected an initial assumption based only on the reference's constraint builder.

The source-preserving three-phase factorial preflight covers **96 combinations**:
**74 admitted**, **22 rejected** (17 `ALMOST_LOCALLY_SOLVED`, four `OTHER_ERROR`,
one `LOCALLY_INFEASIBLE`). All rejections occur with voltage-dependent loads;
full power lifting passes every cell. All 22 rejected models admit a separately
solved full-model point. Their convergence cause remains open, so **no timing
campaign or new speed ranking is reported**.

The 74 admitted SI exports pass physical/full/reverse membership, objective
reconstruction and round trips. All 296 tightened-bound witnesses reject.
All 41 admitted tracking endpoints activate an inherited transformer nameplate
phase cap. Independent input/factor/limit audits pass; objective error is below
5.56e-10 and within-cell spread below 2.05e-10. A retrospective check of 112
saved urban/rural endpoints finds all 912 rated observations below nameplate
(maximum utilization 0.179210); prior timings still describe uncapped models.
See the [study](ivr_threephase_transfer.md) and tutorial sections 48–49.

Initial fixture/setup/reporting errors and all rejected admissions remain in
the outside-Git evidence. One regression run loaded the policy before the
zero-rating correction and failed that new test; the final full run uses the
stable source. Existing OpenDSS precompile fallback remains nonfatal. No source
dataset is edited and no prior transformation is deleted.

## Common urban finalists — 6 October 2026

The full suite passes **88,310/88,310 assertions**, including **2214 new checks**
for profile provenance, isolated factors, independent option ownership,
single-phase/delta objectives under both solver scaling policies, complete
starts, physical/full/reverse membership and SI JSON round trips. Tightened
original capability and voltage limits reject unchanged recovered points.
Both report checkpoint policies preserve accepted rows and retain failed trials.

All **2048 measured solves, 128 warm-ups and 64 preflight exports** pass on the
unchanged urban DER scenario. All **64 tightened capability witnesses** reject
physically and algebraically. An independent audit verifies the frozen source,
exact input preservation, full recorded profile and solver options, balanced
orders, recovery and 120 paired contrasts. Maximum recovered-objective error is
below 4.98e-14 and within-cell spread below 2.92e-13. Only Ipopt wall time ranks;
timing does not overlap tests, documentation builds or other solver work.

Reuse slows urban cost about 7–10% but helps tracking about 2–4%. Several cost
finalists are closely grouped, and the tracking winner changes between batches.
Power-only reuse remains a tracking candidate; signed observations do not
consistently improve it. See the [study](ivr_urban_finalists.md) for the complete
16-profile table, paired contrasts and conditional shortlist, and
[tutorial section 47](tutorial_exact_ivr.md) for an executable example.

An initial campaign was stopped before ranking analysis when per-trial report
rewrites exceeded 100 MiB. Its files remain separate and excluded; the entire
panel restarted with sweep checkpoints after regression tests. The solver timer,
trial routine, candidates and physical inputs are unchanged. The checkpoint
failure test initially hit an earlier objective guard; using an invalid power
base exercises the intended retained-error path without weakening that guard.
The existing OpenDSS precompile fallback is nonfatal. No production equation,
package default, previous option or result schema changes.

## Mixed-device rural transfer — 6 October 2026

The full suite passes **86,096/86,096 assertions**, including **2189 new checks**
for explicit generator/IBR power objectives, source-preserving scenarios,
single-phase/three-leg/four-leg filters, voltage-dependent load composition,
complete starts, physical/full/reverse membership, recovered filter losses and
SI JSON exports. Capability, internal DC and voltage limits reject unchanged
recovered points through both independent physical and encoded checks.

All **576 measured solves, 96 warm-ups and 48 preflight exports** pass on the
selected 70-bus rural feeder. The independent evidence audit checks exact source
preservation/additions, frozen source, ordering and 96 paired contrasts. All
120 tightened-bound witnesses reject; mixed cost activates all 17 IBR DC budgets
and all 18 generator capability ratings. Recovered-objective error is below
3.78e-15 and within-cell spread below 1.71e-14. Only Ipopt wall time ranks profiles;
timing is isolated from tests/docs/other solver work.

Reduced power lifting leads all mixed confirmation cells. Reuse slows mixed cost
5–6% and adds an iteration, although it helps constant-power tracking. The cap-four
and block arms emit identical MOI algebra/maps; no cap benefit is inferred.
All alternatives and raw tails remain. No production equation, default or result
schema changes. A test initially used the wrong export namespace; correcting it
to the existing `_formulationlab.devices` extension resolved the errors.

Thirty-five older documentation sections move to linked history pages with
content preserved and old heading links retained; the page-size limit is unchanged.
See the [scientific study](ivr_mixed_devices.md) and [tutorial section 46](tutorial_exact_ivr.md).

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

This evidence is retained in the [historical study](verification_history.md#verification-history-1).

## Exact lifting and charged-section blocks — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-2).

## Common physical result contract — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-3).

## Adjacent-chain certificate and benchmark — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-4).

## Distinct P/Q histories and reactive-bound transitions — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-5).

## Explicit reconstructed-dual initialization — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-6).

## External feeder reuse and initialization transfer — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-7).

## Model reuse and explicit previous-primal starts — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-8).

## Formulation–ordering interaction and factor-storage diagnostics — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-9).

## Ipopt wall-time priority and held-out validation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-10).

## Best-evidence profiles and selector preparation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-11).

### Unchanged selector decisions with less preparation

This evidence is retained in the [historical study](verification_history.md#verification-history-12).

### Screen, freeze and confirm complete profiles

This evidence is retained in the [historical study](verification_history.md#verification-history-13).

## Conservative series selection by operating-bound support — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-14).

## Finite-ground voltage scaling — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-15).

## Local impedance and degree-two elimination — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-16).

## Avoiding unused real/reactive power copies — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-17).

## Exact-zero line-passivity preparation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-18).

## Assembly-local neutral-role preparation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-19).

## Sparse affine expression preparation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-20).

## Regional performance and coordinate ablation — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-21).

## Exact IVR pendant-region specialization — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-22).

## Exact IVR voltage-dependent demand — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-23).

## Exact IVR fixed regulators — 5 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-24).

## Exact IVR static components and reusable models — 4 October 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-25).

## ENWL generation-cost comparison — 30 September 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-26).

## Explicit-neutral LinIVR experiment — 30 September 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-27).

## Branch-flow milestone — 21 September 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-28).

## Static AC containment milestone — 11 September 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-29).

## Broader NLP / SOC panel — 11 September 2026

This evidence is retained in the [historical study](verification_history.md#verification-history-30).
