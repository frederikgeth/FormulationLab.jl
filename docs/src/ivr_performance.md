# Best-evidence exact-IVR profiles

All transformation and reformulation options remain available. A configuration
that is slower on one panel is still useful for future numerical evidence.
Recommendations here are additive; package defaults and the individual options
are unchanged. “Fastest” always refers to a declared workload, accepted physical
solutions, a candidate set, solver settings and a measured environment.

The [single-phase voltage-bound transfer](ivr_singlephase_transfer.md) admits
all 108 full/reduced/reuse combinations with exact load-power lifting and
aligned nameplates. A sequentially declared narrow band reaches two upper
voltage bounds under cost and five lower bounds under tracking; the wider
controls remain inactive. Inherited line and nameplate limits remain loose.
This establishes strict admission near added voltage boundaries; speed claims
remain pending. All 1,944 subsequent trials and 216 warm-ups pass, but a
competing Julia workload invalidates timing isolation. The whole campaign is
excluded from speed recommendations; its raw results are retained.

The [equipment-boundary extension](ivr_equipment_boundaries.md) additionally
admits all 72 supported comparisons at larger added DER capacity. Export tracking
reaches all three inherited transformer caps; the wide band also activates five
upper-voltage limits, while a separate positive-domain-floor scenario leaves
added voltage bounds inactive. The 36 inherited-only cases are refused because
their voltage-dependent loads lack a positive-domain certificate. These are
correctness/applicability results, with no new speed claim.

The [local reactive-transfer study](ivr_line_boundaries.md) admits 24/24
comparisons across six retained formulations, two directions and both solver
policies. All three selected line conductors reach the inherited 600 A cap at
both ends while transformer caps remain inactive. This extends correctness
evidence at original current boundaries; it does not change timing rankings.

The [shunt-loaded extension](ivr_shunt_boundaries.md) admits all 96 manufactured
comparisons with one endpoint active and the other inactive, including
single-phase/delta connections and equivalent inline/linecode matrices. Its
independent SI audit also verifies inherited shunt recovery in the 24 archived
feeder exports. This is additional correctness evidence, with no timing ranking.

The [joint-boundary study](ivr_joint_boundaries.md) admits all 144 manufactured
P/Q comparisons and verifies 96 independent restriction witnesses. Relaxing
current or voltage alone admits a better point that violates only that original
bound family. Roundoff-sized negative slacks remain explicit. This adds no
timing recommendation and removes no formulation option.

The [inherited MV shunt study](ivr_external_shunts.md) admits 24/24 comparisons
on a separately selected French feeder. Both directions reach an inherited
428 A cable rating at different ends; 48 endpoint rejection certificates pass,
including series-only counterexamples. This transfers boundary correctness to
original shunted-line data without changing numerical recommendations.

The [mixed-device rural transfer](ivr_mixed_devices.md) adds filtered IBRs and
voltage-dependent demand on a selected 70-bus feeder. Reduced power lifting leads
the mixed confirmation panel; generator reuse helps constant-power tracking but
slows mixed cost and does not help mixed tracking. The cap-four/block arms emit
identical algebra here, so their timing differences do not establish a cap effect.

The [common urban finalist panel](ivr_urban_finalists.md) compares 16 retained
profiles on the same input. For cost, keep unreused 1 kVA power lifting with
10/100 kVA dispatch and block/cap-four alternatives; several leading medians
are too close to establish a meaningful ordering. For tracking, power-only
reuse at 1 kVA lifts remains a useful candidate, alongside nearby alternatives.
Its matched gain is about 2–4%, whereas reuse slows cost about 7–10%.
Signed observations do not consistently improve power-only reuse. Raising lift
units to 10 kVA under gradient scaling can add iterations and lose 10–21%,
depending on dispatch units and reuse. The study retains full 1/10 kVA and
full-power controls, both batches and every tail; no universal default follows.

The [three-phase transfer preflight](ivr_threephase_transfer.md) identifies a
correctness qualification and a robustness gap. Previous exact-IVR panels used
the native policy that ignores transformer `s_rating`; the new opt-in BMOPFTools
policy enforces its ordinary-transformer nameplate caps. All 112 retrospectively
checked urban/rural endpoints satisfy these caps, but their recorded timings do
not include the extra rows. On the new French feeder, 22 of 96 strict admissions
fail, all with voltage-dependent demand, while full power lifting passes every
cell. Each failed reduced model admits a full-model feasible point. These failures
require a robustness qualification before timing a reduced shortlist there.
A [subsequent exact load-power extension](ivr_load_power_lifting.md) admits all
96 combinations with unchanged strict settings. It is available as the opt-in
`load_power_lifting=true`. The subsequent [isolated paired study](ivr_load_power_timing.md)
admits all 1152 lifted measured trials, versus 576/1152 original trials. For cost,
lifted full/reduced power profiles are closely matched; for tracking, prioritize
lifted reduced power with generator reuse (about 7.5–37.5% below the lifted full
control by paired median). Lifting can also slow eligible full-model tracking,
so this is a conditional shortlist. Signed observations and inactive cap-four
restrictions do not establish a speed advantage. All original/rejected outcomes
and every option remain available; package defaults are unchanged.

The [independent load-unit study](ivr_load_power_units.md) admits all 2304
measured trials and 192 warm-ups. A declared MV/LV unit split improves some
full-model tracking cells, but gives no consistent large gain over the reduced
finalists. Nominal load units have small mixed effects; uniform 10 kVA load units
consistently slow generator reuse. Keep 1 kVA load auxiliaries as the common
control, with other power lifts also at 1 kVA. The conditional cost shortlist
remains full/reduced power lifting; tracking favours reduced power with reuse.
No new automatic scaling default follows. The subsequent
[row/column factorial](ivr_load_power_rows.md) passes all 1024 measured solves
and 128 warm-ups, but finds no consistently faster row policy and no iteration
changes. Keep assembly-unit load rows (`load_power_row_scaling=:off`) with the
1 kVA load-column control. All row modes remain experimental options. Broader
MV sampling and original-mode sensitivity remain open. The next
[six-MV-site transfer](ivr_mv_scale_transfer.md) passes all 576 measured solves
and 96 warm-ups. Nominal-demand load columns reduce low-filter tracking time
by about 18–19% with Ipopt scaling off (37 to 29 iterations), but gradient-scaled
tracking still gives a lower absolute time in that setting. High-filter tracking
favours Ipopt scaling off. Cost and row-policy differences remain mixed. Keep
nominal and voltage-class columns as conditional candidates; the common control
and package defaults remain unchanged. This panel has no active inherited
network limits, so active-boundary transfer remains open.

## Primary assessment: Ipopt wall-clock time

The primary assessment now **excludes the cost of constructing reduced models**.
Rank profiles by `ipopt_wall_s`, obtained from `JuMP.solve_time(model)` / MOI's
`SolveTimeSec`. The installed Ipopt.jl 1.16.0 implementation measures elapsed
wall time from entry to its optimizer call through completion of `IpoptSolve`.
This includes backend setup and solver evaluations; it excludes FormulationLab
construction, JuMP cache transfer before that call, result extraction and audits.
It is not CPU time or an isolated native factorization timer.

The report's `fastest_ipopt` is the primary winner. Construction allocations,
`fastest_total` and `fastest_solve` remain secondary diagnostic fields and do not
influence it. Here `solve_s` / `fastest_solve` retain their original meaning:
the surrounding solve wrapper **including extraction**. Historical reports do
not contain isolated Ipopt timings and cannot be relabelled as such. Missing,
nonfinite or negative Ipopt timings withhold the primary winner, without
inventing a value from those older measurements.

All physical/model admission rules and objective-comparability requirements
still apply. A failed profile cannot win on time. Warm-ups are excluded and
no construction-time penalty is applied to any transformation. All options
remain available, including configurations that lose this particular comparison.

The [power-objective comparison](ivr_objectives.md#Confirmed-workload-comparison-—-5-October-2026)
extends the source-import evidence to linear/quadratic economic cost, P/Q tracking,
curtailment and losses. Its fastest candidates differ by workload; use that panel
when selecting a power-based objective profile. Subsequent matched-factor tests
separate reduction, scaling and lifting effects. The
[external LV dispatch transfer](ivr_objectives.md#External-LV-dispatch-transfer)
then finds full IVR fastest in all four cost/tracking and solver-scaling cells;
the reduced unlifted bundle is 34–44% slower despite fewer variables. Retain full
IVR in every shortlist: manufactured-case winners do not establish external gains.
The subsequent [265-bus derived-DER panel](ivr_objectives.md#Derived-DER-transfer-on-265-buses)
finds a conditional benefit: reduced 1 kVA power lifting improves economic cost
by 18.3–18.4% against full 10 kVA, but that lower base hurts exchange tracking.
The best 10 kVA reduced tracking candidates gain about 6%. This explicitly added
DER scenario preserves original equipment limits. That shortlist omitted full
1 kVA; larger multi-transformer/voltage-constrained controls also remain open.

The [matched full/reduced base study](ivr_objectives.md#Matched-full-and-reduced-power-bases)
subsequently closes the full 1 kVA gap on that scenario. Full 1 kVA itself gains
13.5–13.7% on cost versus full 10 kVA; matched reduction contributes roughly 5–7%.
Reduced 1 kVA with lifting off/powers is the cost shortlist, while reduced 10 kVA
off/powers is the tracking shortlist across both tested solver policies. A 100 kVA
tracking base is near 10 kVA without automatic scaling but about 34% slower with
gradient scaling. These are scenario-specific profiles; all alternatives remain.

The [independent dispatch-unit study](ivr_objectives.md#Independent-generator-dispatch-units-—-6-October-2026)
holds the assembly base at 10 kVA and varies only generator P/Q units. Cost
improves at both 1 and 100 kVA dispatch bases, with matched paired ratios
0.887–0.893 and 0.865–0.878. The response is nonmonotonic; smaller LV ratings alone
do not identify a best base. Reduced 100 kVA dispatch is an additional cost
candidate, alongside the earlier common-1k profiles; no shared timing panel yet
ranks those alternatives. Tracking retains 10 kVA dispatch: 1 kVA loses, and
100 kVA is near a tie without automatic scaling but loses with gradient scaling.
That panel held lifted-power units fixed; the following study isolates them and
compares previous finalists in a shared block.

## Matched cost and tracking finalists — 6 October 2026

The [three-scenario finalist study](ivr_objectives.md#Matched-finalists-and-external-transfer-—-6-October-2026)
compares prior winners, isolated lifted-power units, exact generator-definition
reuse and less aggressive nonadjacent condensation. It includes the unchanged
265-bus DER scenario, a separately declared voltage-constrained variant, and a
1,220-bus/four-transformer scenario with 268 added DERs. All 2400 measured solves,
240 warm-ups and 120 separate SI exports pass. Original source files are unchanged.

The finalist-panel **cost shortlist** leads with reduced blocks, nominal transformer
coordinates, voltage-ground/composed-row scaling, exact sharing, assembly and
generator bases 10 kVA, power lifting with `lifted_power_base=1e3`, and
`power_sharing=:off`. Against full-10k, confirmation median gains are 19.6–20.2%,
17.1–17.5% and 8.6–9.3%, respectively. These are bundle gains: the isolated lift
unit benefit on the larger feeder is only 1–2%. Retain the nearby alternatives.

For **tracking**, keep the same reduced structure with either generator reuse
(`lifting=:powers, power_sharing=:generators`, assembly/dispatch/lifts 10 kVA)
or 1 kVA lifts without reuse. Reuse leads all three scenarios with automatic
scaling off. Under gradient scaling, it leads the unchanged 265-bus case, while
1 kVA lifts lead the constrained and larger cases. Both must stay in the shortlist.

Generator reuse improves tracking about 3% relative to its matched power-lift
control, but slows larger-feeder cost by 6–7% despite removing 536 real variables.
Nonadjacent condensation is 3.6–6.8% slower than blocks in every confirmed context.
These negative results are retained. Common-1k and dispatch-only old finalists
are now compared in the same block; they do not beat the new cost leader here.
No automatic default is promoted. The subsequent
[controlled interaction study](ivr_power_interactions.md) tests combined
unit/reuse tuning and updates the workload-specific shortlist.

The controlled combinations retain the 265-bus cost leader: dispatch 10 kVA,
lifts 1 kVA, reuse off. At 100 kVA dispatch, reuse instead slows BASE265 cost
about 25–27%. Urban cost has several close unreused candidates whose ordering
changes between batches. For urban gradient-scaled tracking, dispatch 10 kVA,
lifts 1 kVA and reuse leads both batches; the incremental matched reuse gain is
about 2–4%. Keep the prior alternatives: the same combination loses on the
voltage-constrained tracking case. See the linked interaction study for complete
conditional effects and unchanged physical-result checks.

The [hybrid studies](ivr_hybrid_transfer.md) preserve all caps. Unrestricted
blocks remain the general starting candidate; cap four repeats a small urban
cost gain under both scaling policies, but tracking and active suburban voltage
limits show no consistent benefit. Cap eight has identical block maps on these
feeders, so its timing differences are not cap benefits.

[Signed affine sharing](ivr_affine_sharing.md) saves observation auxiliaries and
helps the tested delta chain by roughly 6–8% against power-only lifting. BASE265
cost gains about 1%; real proportional matching adds no further reuse there.
The [structural factorial study](ivr_structural_interactions.md) adds signed
sharing plus reuse to the urban tracking shortlist. Reuse instead slows urban
cost about 7–10%, with two extra iterations, and removes cap four's small matched
cost benefit. The combined signed/cap cost candidate does not reliably displace
power-only lifting. Cap choices and close smaller-case rankings change between
batches. All older finalists remain; this panel does not rank every power-only/
reuse or power-base alternative. No default changes.

[Physical non-unit sharing](ivr_nonunit_transformers.md) now activates exact
transformer factors −8 and −1/8. Proportional sharing gains 4.5–7.7% over signed
sharing at threshold zero, but threshold two remains faster in every paired
median. Keep the option; do not add lifting solely to enable more sharing.

## Unbalanced transformer-leakage transfer — 5 October 2026

The fixed power-base candidates transfer successfully to a manufactured coupled
three-phase circuit, but their ranking changes. A common 1 kVA base improves the
current-limited case by **33.6% / 33.2%** relative to common 10 kVA (`none` /
`gradient-based`). Lowering only the regional LV current base provides no
comparable benefit on that case. Regional LV 1 kVA is fastest among these six
candidates on the capability and voltage cases, with **6.4% / 6.7%** and
**6.0% / 5.3%** gains over common 10 kVA, respectively. These are ratios of
confirmation medians, not pooled averages or universal recommendations.

The circuit has a shared bank of three single-phase 11 kV/2.3 kV transformers,
two 2.3 kV/230 V delta–wye transformers, nonzero R/X leakage on every transformer,
and twelve mutually coupled four-wire LV sections per branch. Unequal phase
loads total 12.6 kW and 3.36 kvar before six unity-power-factor generators supply
power. Each LV end has a finite 2 ohm neutral ground. All six full-IVR models
have **486 real variables**. Distinct cases bind generator capability, phase-a
line current or terminal phase-neutral voltage limits. Initial fixture preflight
found that 232 V was slack; the voltage-case ceiling was set to 231 V before
freezing the campaign, and the original source/logs are retained. This is a
designed transfer panel, not an untouched feeder holdout. It changes several
physical features together, so rank changes cannot be attributed to leakage alone.

All six earlier profiles transfer unchanged: four common assembly power bases
and two regional current-unit choices, nominal voltage coordinates, composed
linear rows, `ground_scaling=:voltage`, fixed objective divisor 10,000, full IVR,
MUMPS AMD and the same unloaded physical start. Each cell has six excluded
warm-ups and twelve rotated/reversed sweeps, with every profile appearing twice
in each position. A second complete panel runs in a fresh process. Across both
panels, **864 measured solves and 72 warm-ups pass** the independent SI audit,
original bounds, own/full-model membership, reverse anchor mapping and objective
agreement. Construction, extraction and audits are excluded from ranking.
Timings never overlap diagnostics, tests or documentation builds.

Confirmation median Ipopt wall time, milliseconds:

| Case | Ipopt scaling | Common 10 kVA | Common 1 kVA | Common 100 kVA | Common 1 MVA | Regional LV 1 kVA | Regional LV 10 kVA |
|---|---|---:|---:|---:|---:|---:|---:|
| Capability | none | 9.668 | 9.391 | 12.233 | 12.800 | 9.051 | 9.741 |
| Capability | gradient-based | 9.606 | 9.457 | 12.272 | 12.712 | 8.965 | 9.694 |
| Current | none | 15.186 | 10.084 | 10.680 | 23.520 | 15.327 | 15.332 |
| Current | gradient-based | 15.231 | 10.178 | 10.720 | 23.430 | 15.119 | 15.290 |
| Voltage | none | 10.757 | 10.236 | 16.029 | 11.966 | 10.109 | 11.465 |
| Voltage | gradient-based | 10.566 | 10.105 | 15.911 | 11.751 | 10.007 | 11.249 |

In the same column order, iteration counts are `12/12/16/17/11/12` for
capability, `18/13/14/20/18/18` for current, and `14/13/14/16/13/15` for voltage,
under both Ipopt scaling policies. At fixed source/MV regional bases, lowering
LV current units from 10 to 1 kVA improves capability by 7.1% / 7.5% and voltage
by 11.8% / 11.0%, but current is essentially tied (0.03% / 1.1%). Common 1 MVA
is about 54–55% slower than common 10 kVA in the current case. All candidates,
including regressions and outliers, remain available.

All twelve paired confirmation ratios for common 1 kVA versus 10 kVA in the
current case are below 0.693 under both policies. Smaller gains have noisier
tails: a capability/gradient-based regional-LV-1-kVA trial is 2.26 times its
paired common-10-kVA time despite the same iteration count as its own other
trials. Conversely, a slow capability/no-scaling baseline yields a ratio of
0.218. Both are retained without assigning a cause or presenting them as
representative speedups.

Separate NLPDiagnostics instrumentation covers **36 solves and 72 evaluations**
at the identical SI unloaded start and full-model reference endpoint. In the
current case with Ipopt scaling disabled, common 10 kVA and regional LV 1 kVA
both have five positive-regularization records, whereas common 1 kVA has zero.
Their endpoint Jacobian column-norm spreads are approximately 36,795, 1,995 and
28,814 respectively. Thus the much smaller spread from regional current units
does not predict the fastest solve. For voltage, common 100 kVA has the same
fourteen iterations as common 10 kVA but is substantially slower and has two
positive-regularization records versus zero. These observations motivate further
factorization diagnostics; they do not prove a causal explanation or measure
matrix condition numbers. Maximum within-cell objective disagreement across
timings and warm-ups is below 7.1e-10 W. Physical SI reference solutions are also
exported in the established BMOPFTools-compatible result format.

The independent analytical optimum of the earlier ideal single-phase panel
does not apply here. SI feasibility and agreement between local optima are
necessary admission evidence, not a certificate of global optimality. Separate
prescribed-current SI witnesses check single-phase, delta–wye and wye–delta
leakage under forward/reverse flow, changed power bases and tightened ratings
on both sides. Reduced-model tests also compose the current units with conductor,
passive-block and transformer-current elimination, lifted bounds and SI JSON
recovery. These checks provide evidence for the exercised combinations; they do
not constitute an exhaustive bound-expression proof for every possible network.

Reproduction: `examples/benchmark_ivr_unbalanced_power_bases.jl`; see
[tutorial section 32](tutorial_exact_ivr.md). Raw evidence, fixed protocol,
complete source snapshots, SI reference exports, separate diagnostic traces and
the initial inactive-voltage fixture are retained outside Git in
`UNBALANCED_POWER_BASE_STUDY_20261005`. No production default changes. The next
useful comparison crosses the best candidates with exact passive/device
reductions and then transfers them to fixed external unbalanced feeders; choosing
a base from LV voltage level alone is not supported by this evidence.

## Common power bases and regional current units — 5 October 2026

Power-base changes deliver reproducible benefits on a manufactured aggregation
panel, but the best choice depends on the active constraints. A shared ideal
11 kV/2.3 kV supply feeds four independent 2.3 kV/230 V LV branches. Each branch
has twelve resistive sections, 2 kW demand, finite neutral grounding and controlled
generation. Separate cases bind per-branch capability, reverse-current or voltage
limits. MV therefore aggregates four branches' power. Independent scalar branch
optima add; the builder requires slack shared upstream current ratings. This is
an analytical single-phase control panel, not a realistic unbalanced feeder.

The six profiles comprise common assembly bases of 1, 10, 100 kVA and 1 MVA,
and two regional **current-coordinate** policies with assembly base 10 kVA and
source/MV/LV declarations of 1 MVA/100 kVA/1 kVA or 1 MVA/100 kVA/10 kVA.
All use nominal voltage coordinates, the existing global-ground policy, composed
circuit rows, full IVR with **442 real variables**, MUMPS AMD and identical SI
inputs/unloaded starts. `objective_scale=1e4` holds the numerical objective divisor
fixed in every arm. Changing `s_base` otherwise changes objective normalization
as well as electrical units under the legacy default.

Common-base changes affect electrical coefficients, P/Q and ground normalization.
The regional option deliberately changes current coordinates only: dispatch,
lifted observations/powers and ground multipliers retain assembly conventions.
Thus the two regional arms isolate LV current scaling while holding upstream
bases and other units fixed. See the [contract](ivr_nlp.md),
[dimensional derivation](ivr_theory.md) and [tutorial section 31](tutorial_exact_ivr.md).

Exploration and fresh-process confirmation each admit **432/432 measured solves
and 36/36 warm-ups**, using twelve balanced sweeps per case/policy block. The
maximum measured error against the independent physical optimum is below
7.28e-7 W, with a predeclared 1e-4 W admission threshold. All solver, independent
SI, own/full-model and reverse-map checks pass. Confirmation repeats all six
arms under explicit Ipopt `none` and `gradient-based` scaling; the voltage case
is retained as a regression control. Batches are not pooled. No diagnostics,
tests or documentation builds overlap timings. Compilation, starts, extraction
and audits are excluded from the Ipopt wall-time ranking.

Confirmation median wall times in milliseconds. The first four numeric columns
are common assembly power bases; the final two are regional current-base arms.

| Active limit | Ipopt scaling | Common 10 kVA | Common 1 kVA | Common 100 kVA | Common 1 MVA | Regional LV 1 kVA | Regional LV 10 kVA |
|:--|:--|--:|--:|--:|--:|--:|--:|
| Capability | none | 7.132 | 6.302 | 8.523 | 9.302 | 6.494 | 6.984 |
| Capability | gradient-based | 7.029 | 6.361 | 8.533 | 9.403 | 6.510 | 6.930 |
| Current | none | 7.890 | 7.184 | 6.745 | 7.559 | 6.969 | 7.849 |
| Current | gradient-based | 7.952 | 7.198 | 6.817 | 7.701 | 6.958 | 7.923 |
| Voltage | none | 5.600 | 6.382 | 5.500 | 6.353 | 5.489 | 5.525 |
| Voltage | gradient-based | 5.559 | 6.379 | 5.517 | 6.299 | 5.447 | 5.581 |

Relative to the common 10 kVA control, common 1 kVA improves capability timings
by **11.6% / 9.5%**, while common 100 kVA improves current timings by
**14.5% / 14.3%** under none / gradient-based solver scaling. Common 1 kVA is
**14.0% / 14.7% slower** on the voltage case. Common 1 MVA is also slower on
capability and voltage. A smaller electrical base is therefore not a uniform
speed improvement.

The matched regional comparison is more directly relevant to lower LV power
levels. With source and MV bases held fixed, regional LV 1 kVA versus LV 10 kVA
improves capability medians by **7.0% / 6.1%** and current medians by
**11.2% / 12.2%**. Every paired capability ratio is below 0.957 and every paired
current ratio below 0.922. Voltage differences are small, 0.6% / 2.4%, with some
paired ratios above one. All outliers remain: regional LV 10 kVA reference
trials produce paired ratios as low as 0.310 in current/gradient-based and 0.303
in voltage/none, without different iteration counts. No cause is assigned and
these minima are not reported as representative speed gains.

Separate diagnostics retain **36 native traces and 72 Jacobian evaluations** at
shared unloaded and full-model endpoint physical states. All instrumented
endpoints pass physical and analytical checks. Capability iterations are
12/11/15/16/11/12 in table order; current iterations are 14/13/12/14/11/14;
voltage iterations are 9/11/9/11/9/9 under both solver policies. On the current
case, regional LV 1 kVA takes fewer iterations than common 100 kVA yet is slower
in median wall time. Its disabled-solver-scaling trace has two regularization
records versus zero for common 100 kVA. This is telemetry, not a proven causal
mechanism. Norm spreads and iteration counts remain insufficient ranking rules;
no KKT fill or condition-number claim is made.

The new knobs are additive and defaults remain unchanged. Regional dispatch,
lifted-power and ground normalization are separate future interventions. Next
transfer the promising candidates to unbalanced MV/LV networks with transformer
leakage and mixed active limits, then retest reduction interactions. The current
panel's ideal, separable branches do not establish portability or an automatic
rating-based power-base selection rule.

Reproduction: `examples/benchmark_ivr_power_bases.jl`. Raw inputs, complete code
and dependency snapshots, protocols, JSON trials, diagnostics/traces, analyses
and separate confirmation remain outside Git in `POWER_BASE_STUDY_20261005`.
A separate cost-update regression test uses tighter 1e-12 solver accuracy because
currency/h divided by 1e4 can leave a dispatch bound insufficiently resolved at
1e-10; the initial test result is retained. All performance runs retain the
original strict 1e-10 settings and fixed source-import objective divisor.

## Regional finite-ground scaling — 5 October 2026

The additional `ground_scaling=:regional_voltage` policy uses the nominal
regional shunt admittance ``|Y|V_r^2/S_b`` to choose its invertible voltage
multiplier. The existing `:voltage` policy retains the global-base multiplier;
`:off` and every prior option remain available. See the
[contract](ivr_nlp.md), [derivation](ivr_theory.md) and
[tutorial section 30](tutorial_exact_ivr.md). Physical equations, bounds, source
values, output units and update semantics are unchanged. Default settings are
unchanged.

The six-arm study crosses global/nominal transformer coordinates with
no/global/regional ground scaling. Every arm uses composed circuit-row norms,
full IVR with 406 real variables, the common 10 kVA power base and MUMPS AMD.
The three analytical active-limit inputs below are unchanged: 48 resistive
segments, two ideal transformer stages, finite neutral ground and the same
unloaded physical start. Each explicit Ipopt scaling block uses twelve balanced
sweeps and six excluded warm-ups. Admission includes the independent optimum
within 1e-4 W and all original solver, physical and representation checks.

Exploration admits **432/432 measured solves and 36/36 warm-ups**. No regional
policy achieves the predeclared 5% gain under both solver policies. A supplemental
fresh-process confirmation was instead declared after exploration to test the
current-case regression, retaining all six arms and both solver policies. It
admits **144/144 measured solves and 12/12 warm-ups**. This is a confirmation of a
selected negative result, not a held-out network generalization experiment.
The batches are not pooled. Diagnostics and tests do not overlap the timing runs;
compilation, extraction and audits do not enter the primary metric.

Median Ipopt wall times in milliseconds. In the column headings, G/L denotes
global/local transformer coordinates; off/global/regional denotes the ground
multiplier policy.

| Case / batch | Ipopt scaling | G/off | G/global | G/regional | L/off | L/global | L/regional |
|:--|:--|--:|--:|--:|--:|--:|--:|
| Capability (exploration) | none | 9.647 | 9.704 | 9.637 | 6.528 | 6.559 | 6.648 |
| Capability (exploration) | gradient-based | 10.402 | 10.339 | 10.360 | 6.569 | 6.611 | 6.609 |
| Current (exploration) | none | 6.846 | 6.816 | 6.835 | 8.042 | 6.535 | 8.024 |
| Current (exploration) | gradient-based | 7.007 | 6.912 | 6.982 | 8.128 | 6.560 | 8.049 |
| Voltage (exploration) | none | 5.154 | 5.260 | 5.156 | 5.668 | 5.589 | 5.663 |
| Voltage (exploration) | gradient-based | 6.039 | 6.040 | 6.086 | 5.574 | 5.618 | 5.666 |
| Current (confirmation) | none | 7.056 | 7.045 | 7.049 | 8.294 | 6.724 | 8.400 |
| Current (confirmation) | gradient-based | 7.133 | 7.120 | 7.087 | 8.217 | 6.743 | 8.083 |

With local transformer coordinates, regional versus global ground scaling makes
the current-limited case **24.9% slower with solver scaling disabled** and
**19.9% slower with gradient-based scaling** in confirmation. Every paired
regional/global ratio exceeds 1.20 and 1.11, respectively. Iterations increase
from 12 to 15 under both policies. Ground scaling off also takes 15 iterations.
The capability and voltage cases show no meaningful new-policy gain in
exploration and were not repeated in the supplemental confirmation. The existing
nominal/global-ground profile remains the fastest tested current-case profile
in each confirmation block. No option is promoted or removed.

Separate NLPDiagnostics work retains **36 native traces and 72 sparse Jacobian
evaluations** at shared unloaded and accepted full-model physical points.
All instrumented endpoints pass the independent physical and analytical checks.
At the current-case endpoint, column-norm spread falls from approximately
68,901 with local/global-ground scaling to 34.8 with local/regional-ground
scaling; ground scaling off gives 24.6. Yet the latter two solve more slowly.
All three traces report one regularization record, with 12 versus 15 summed
line-search trials. In the capability case, regional ground scaling reduces
column spread from about 312,034 to 157.5 without reducing the 12 iterations.

This rejects the claim that more balanced raw Jacobian column norms alone imply
faster solves on these cases. It does not identify a general conditioning,
barrier or factorization mechanism: native trace metrics are in solver/model
units, norm spreads are not condition numbers, and no KKT fill is measured.
The regional coordinate remains mathematically useful and available for future
experiments, but has no demonstrated speed advantage here. These ideal
single-phase cases do not establish outcomes for unbalanced feeders with
transformer leakage or alternative regional power bases.

Implementation and reproduction: `examples/benchmark_ivr_regional_ground.jl`.
Frozen inputs, source/dependency snapshots, protocols, all raw JSON trials,
shared-point diagnostics, traces, analyses and separate confirmation results
remain outside Git in `REGIONAL_GROUND_SCALING_20261005`. Next extend the panel
to unbalanced mixed-voltage dispatch with leakage before selecting regional
power/current bases or retuning reductions. Preserve the active-limit examples
as analytical controls.

## Active transformer-cascade limits — 5 October 2026

A second panel replaces the feasibility-only workloads with three manufactured
OPFs whose optima follow from independent scalar circuit equations. Two ideal
transformer stages, 11 kV/2.3 kV/230 V, supply a 48-section resistive two-wire
feeder, a 2 kW load, finite neutral grounding and dispatchable unity-power-factor
generation. Separate cases bind a 250 VA generator capability, a 5 A reverse
phase-current limit, or a 232 V terminal phase-neutral limit. See
[tutorial section 29](tutorial_exact_ivr.md) for the derivation and runnable cases.
All four profiles retain **406 real variables**; this experiment removes no
variables or equations.

The four-arm protocol and strict physical admission below are retained, with a
source-import objective and an additional independent optimum check within
1e-4 W for every trial and warm-up. Eight balanced sweeps run under each explicit
Ipopt scaling policy. Exploration and fresh-process confirmation each admit
**192/192 measured solves and 24/24 warm-ups**. The maximum measured objective
error is below 1.82e-7 W. Compilation, extraction, diagnostics and test work are
excluded from the primary timings and do not overlap either batch.

Confirmation medians in milliseconds (batches are not pooled):

| Active limit | Ipopt scaling | Global / legacy | Global / composed | Local / legacy | Local / composed |
|:--|:--|--:|--:|--:|--:|
| Generator capability | none | 9.471 | 9.489 | 6.395 | 6.426 |
| Generator capability | gradient-based | 10.120 | 10.064 | 6.392 | 6.324 |
| Reverse current | none | 6.758 | 6.700 | 6.467 | 6.384 |
| Reverse current | gradient-based | 6.842 | 6.908 | 6.496 | 6.535 |
| Voltage rise | none | 5.097 | 5.082 | 5.390 | 5.388 |
| Voltage rise | gradient-based | 5.965 | 5.946 | 5.489 | 5.374 |

Local/composed versus global/legacy improves capability-case medians by
**32.2% / 37.5%** and current-case medians by **5.5% / 4.5%** for none /
gradient-based solver scaling. The voltage case is **5.7% slower** with solver
scaling disabled and **9.9% faster** with gradient-based scaling. The same signs
occur in exploration. Every paired confirmation capability ratio is below
0.688; every voltage/none ratio exceeds 1.009. All observations are retained.

The finite-ground coordinate change activates composed row normalization under
both row policies. Thus legacy/composed arms at a fixed coordinate policy are
**no-op controls on this panel**, not independent row-scaling interventions.
The local-coordinate intervention includes the corresponding recomputed circuit
row norms. The evidence does not isolate a pure column-scaling effect.

Separate NLPDiagnostics runs retain 24 native callback traces and 48 sparse
Jacobian evaluations at shared unloaded and accepted full-model physical points.
All instrumented endpoints pass the physical and independent-optimum checks.
Capability iterations decrease from 18/20 to 12, current from 13 to 12, and
voltage changes from 9/11 to 10 under none/gradient-based policies, respectively.
With solver scaling disabled, the capability trace's summed line-search trials
decrease from 114 to 12. This is consistent with an improved search path, but
does not establish a factorization, rank or conditioning mechanism.

At the shared capability endpoint, positive equality-row infinity norms range
from 0.5 to 9.716 globally and 0.577 to 1 locally. However, full Jacobian
column-norm spread increases from about 312 to 312,034. The unloaded point has
249 zero-gradient inactive inequalities in either representation. Row records
retain source identity, function type, set, value, encoded slack, derivative
method and norm. Activity uses a declared encoded-set tolerance; it is not an SI
feasibility certificate. No inactive tiny-gradient normalization is applied.
Norm spread is not a condition number, and native trace metrics are not SI
residuals. The shared unloaded point is a start, not a feasible OPF solution.

This establishes a reproducible, workload-specific benefit for nominal local
units in an active dispatch problem. It does **not** establish a universal best
profile: the voltage-case regression remains, and these ideal, single-phase,
resistive fixtures do not cover unbalanced feeder dispatch or transformer leakage.
Defaults remain unchanged and all options remain available. Next investigate
unbalanced mixed-voltage dispatch with leakage, then regional power/current
bases and matched reduction interactions. The previously measured real-feeder
scaling effect below remains inconclusive.

Implementation: `examples/ivr_transformer_stress_cases.jl` and
`examples/benchmark_ivr_transformer_stress.jl`. Raw inputs, source/dependency
snapshots, protocols, all trials, traces, summaries and local handover notes are
retained outside Git in `TRANSFORMER_ACTIVE_LIMITS_20261005`, with a separate
`CONFIRMATION` subdirectory. An initial diagnostic run was interrupted after two
completed profiles to replace an unused expensive solver-result profile with
the direct trace-capture API; its script, partial JSON and log are retained.

## Nominal transformer-local scaling — 5 October 2026

`transformer_scaling=:nominal` composes local voltage/current units with the
existing reconstruction maps; the common power base remains 10 kVA.
`row_scaling=:composed` independently normalizes circuit rows after composition.
All bounds, objectives, source fixings and physical outputs retain their original
meaning. Both are additive options with unchanged defaults. The
[theory](ivr_theory.md), [contract](ivr_nlp.md) and
[tutorial](tutorial_exact_ivr.md) describe scope and conservative fallback.

The first timing panel isolates these interventions in **full IVR**, with no
conductor/line/device elimination or lifting. Four arms cross global/local
coordinates with legacy/composed row norms. They share voltage ground scaling,
MUMPS AMD, a 10 kVA power base, the same unloaded physical start and strict 1e-10
solver tolerances. Ipopt `nlp_scaling_method` is explicitly fixed to `none` or
`gradient-based` in separate experimental blocks. All inputs and feasibility
objectives are unchanged; this is not an economic-dispatch comparison.

DSuite265 has one 11 kV/415 V transformer; DSuite1220 has four. Within each
case/policy block, one excluded warm-up per arm precedes eight rotated/reversed
sweeps, giving two appearances in every position. No tests, documentation builds
or other experiments run concurrently. Compilation, start encoding, extraction,
auditing and source normalization are excluded from the assessment. All
**128 measured solves and 16 warm-ups** pass independent SI, own/full-model,
reverse-anchor, complete-start and objective admission checks.

Exploratory medians in **milliseconds of Ipopt wall time**:

| Case | Ipopt scaling | Global / legacy rows | Global / composed rows | Local / legacy rows | Local / composed rows |
|:--|:--|--:|--:|--:|--:|
| DSuite 265 | none | 13.885 | 13.904 | 14.074 | 13.961 |
| DSuite 265 | gradient-based | 13.866 | 13.867 | 13.808 | 13.785 |
| DSuite 1,220 | none | 61.151 | 60.659 | 61.240 | 61.762 |
| DSuite 1,220 | gradient-based | 62.857 | 61.931 | 61.270 | 62.034 |

The predeclared fresh-process confirmation repeats DSuite1220 under both solver
policies regardless of exploratory ranking. All **64 measured solves and eight
warm-ups** pass; batches remain separate:

| Case | Ipopt scaling | Global / legacy rows | Global / composed rows | Local / legacy rows | Local / composed rows |
|:--|:--|--:|--:|--:|--:|
| DSuite 1,220 | none | 60.891 | 61.638 | 61.040 | 60.540 |
| DSuite 1,220 | gradient-based | 61.307 | 61.808 | 61.594 | 60.795 |

The confirmation establishes correctness on these inputs, not a practical speed
advantage. Combined local/composed scaling improves the larger-feeder median by
only 0.6% with solver scaling off and 0.8% with gradient-based scaling. All arms
in both batches take **three iterations**. Global/composed rows differ from the
global/legacy median by 1.2% and 0.8% in confirmation despite unchanged coordinates:
with full identity coordinates and no finite-ground intervention, recomputing row
norms is mathematically the same normalization. Such controls caution against
interpreting sub-percent timings as a scaling mechanism. Local coordinates alone
have mixed signs between blocks/batches; no default or automatic selection changes.

No slow observations were discarded. Exploratory paired local-legacy/global-legacy
ratios reach 10.782 on DSuite265 with gradient-based scaling; local/composed ratios
reach 3.718 on DSuite1220 with solver scaling off. In confirmation, paired combined/
baseline ratios span 0.946–1.016 (`none`) and 0.948–1.010 (`gradient-based`); even
these do not support an every-run improvement claim. A global/composed control
also has a confirmed paired ratio of 3.363. Iteration counts do not explain these
outliers, and this experiment does not assign them a cause.

The pass actually rescales 1,700 complex coordinates on DSuite265 and 7,642 on
DSuite1220, without changing model dimensions. There are no nominal-cycle/source
fallbacks or unsupported transformers on these inputs. Bus bases propagate the
source magnitude through declared nominal ratios, so the LV base tracks the actual
source-level anchor rather than replacing it with a nominal source voltage.
This confirms that the experiment exercised local units rather than a no-op flag.
It does not establish improved condition numbers or KKT factorization fill.

Keep the new policies available for harder mixed-voltage operating points,
active-limit objectives and reduction interactions. Next test a declared regional
power-base policy and component-aware NLPDiagnostics evidence, preserving the
existing physical tolerance gates and keeping instrumented traces outside timing
rankings. Three-iteration feasibility cases leave little convergence work for
scaling to improve; they neither demonstrate nor rule out benefits on harder cases.

Reproduce with `examples/benchmark_ivr_transformer_scaling.jl`. The untracked
`TRANSFORMER_SCALING_STUDY_20261005` archive contains the frozen protocol/source,
unchanged input snapshots, raw JSON, all outliers, independent analysis and separate
confirmation. The new implementation was validated by 66,298 regression assertions
and 30 executable tutorial blocks before timings began.

## Scaling conventions and transformer priority — 5 October 2026

All exact-IVR electrical coordinates are per unit: `Sb=s_base`, `Vb` is the
largest voltage-source magnitude, `Ib=Sb/Vb`, and `Zb=Vb/Ib`. An audit of 708 saved
profile-option records across 111 JSON files finds `Sb=10,000 VA` throughout;
these include manifest/report duplication, not 708 independent experiments.
Inputs and physical results remain SI. The previous campaigns therefore do not
need rerunning because per-unit conversion was absent.

However, **the voltage/current bases are network-wide, not transformer-local**.
DSuite265/1220 use `Vb≈6414.36 V` and `Ib≈1.559 A` despite 11 kV/415 V delta-wye
transformers. A nominal 239.6 V LV phase is approximately 0.0374 on that global
base. The synthetic transformer-current campaign used 230/230 V devices; it did
not test the numerical challenge of large voltage-ratio transitions. Earlier
rankings are conditional on this common-base policy.

Magnitude limits already use their declared ratings for normalization. Linear
circuit rows are normalized, with norms recomputed in composed coordinates only
when finite-ground scaling actually changes a coordinate. The historical saved
solver settings do not explicitly specify `nlp_scaling_method`; they inherit the
installed solver default. Model units, row scaling, objective scaling and solver
scaling must be distinguished in future experiments.

The next priority is an additive local voltage/current coordinate policy across
transformer boundaries, followed by independently controlled composed-row scaling
and regional power bases. Preserve every ratio, connection, tap, bond, ground,
operating bound and physical output. Test the new policy in matched full/block/
transformer-current formulations before transferring previous speed rankings.
This historical planning step established no new scaling policy or speed advantage.
The optional nominal-coordinate and composed-row controls are now implemented;
their matched experiment is documented separately as evidence becomes available.

A baseline-only NLPDiagnostics pilot successfully evaluates full, block-reduced
and transformer-current models at a shared unloaded point and accepted DSuite265
endpoint. All six Jacobian evaluations use exact-symbolic rows with no evaluation
failures. The very large global row-norm ratios arise from tiny derivatives in
inactive quadratic limits: the smallest full-model endpoint row has function
value about 1.60e-85 against an upper bound of 1. Such ratios are not condition
numbers and do not justify inflating those rows. Local equation families, active
bounds and explicit coordinate maps are required for a useful diagnosis.

The untracked `TRANSFORMER_SCALING_PLANNING_20261005` folder contains the per-unit
audit, raw pilot, source identities and staged protocol. Scaling experiments will
explicitly compare model interventions under fixed Ipopt scaling policies, retain
independent SI acceptance and keep instrumented traces outside wall-time rankings.
Transformer-aware scaling now precedes the generator P/Q reuse experiment proposed
below; all previous options and experimental evidence remain available.

## Observation support and exact affine sharing — 5 October 2026

Two additive controls separate when to lift a bounded affine observation from
whether identical composed observations reuse a definition. The threshold is a
strict lower bound on distinct real-variable support; T2 is the existing default,
T8 is an explicit experimental comparator. Exact sharing includes constants and
all nonzero coefficients, without rounding or sign normalization. The four
observation profiles use identical power lifting. Full and direct-block controls
remain available; device-current elimination is off throughout this experiment.

The frozen panel contains a charged 96-section three-wire delta chain with
terminal generation bounded by 400 VA per coil, and unchanged DSuite 265-bus and
ENWL 435-bus inputs. The chain minimizes source import; external objectives remain
feasibility, preserving source/generator accounting. All profiles use the same
unloaded physical start, voltage ground scaling, MUMPS AMD, single-thread Julia
and BLAS, and strict 1e-10 tolerances. Twelve alternating/rotated sweeps place
each of six profiles twice in every position after one excluded warm-up.
Compilation, start encoding, extraction and auditing do not enter the assessment.

All **216 measured solves and 18 warm-ups** pass original SI physical, own-model,
full-model, reverse-anchor and objective checks. Exploratory median Ipopt wall
times in **milliseconds** are:

| Case | Full | Direct blocks | T2 | T2 + sharing | T8 | T8 + sharing |
|:--|--:|--:|--:|--:|--:|--:|
| Delta 96 sections | 41.238 | 205.355 | 32.292 | 32.639 | 32.350 | 32.131 |
| DSuite 265 | 14.008 | 13.156 | 13.520 | 13.328 | 13.222 | 13.218 |
| ENWL 435 | 198.502 | 132.616 | 160.568 | 156.793 | 132.662 | 132.375 |

A predeclared fresh-process confirmation repeats the delta and ENWL cases with
all six profiles, regardless of the exploratory ranking. All **144 measured
solves and 12 warm-ups** pass. The batches are not pooled:

| Case | Full | Direct blocks | T2 | T2 + sharing | T8 | T8 + sharing |
|:--|--:|--:|--:|--:|--:|--:|
| Delta 96 sections | 39.745 | 198.408 | 31.747 | 31.464 | 31.613 | 31.665 |
| ENWL 435 | 198.508 | 132.256 | 159.050 | 157.886 | 130.963 | 132.560 |

The useful finding is selective avoidance of overhead, not a universally faster
new formulation. On ENWL, T8 removes all 1,808 observation variables and recovers
the 6,604-variable direct-block model. The confirmed T8 median is 17.7% below T2,
but T8 and direct blocks have the same derivative structures and no lifted
variables. Their 1.0% median difference is a no-op control difference. All ENWL
profiles take eight iterations. DSuite likewise has no lifted variables at T8;
its direct-block/T8 variants are structural controls, not distinct improvements.

On the charged delta chain, T2 remains useful: its confirmed median is 20.1%
below full IVR and 84.0% below direct blocks. Full/direct blocks take 12 iterations;
all observation profiles take 11. Original capability slacks stay below
9.1e-8 VA. Direct blocks have only 42 variables but 127,191 raw Hessian entries;
T2 has 3,498 variables and 5,832 entries. T8 removes only 12 variables and increases
raw Hessian entries to 5,886; its 0.4% confirmed median advantage over T2 does not
establish a useful threshold improvement. Unique Hessian entries remain 5,256
for both lifted policies. These are derivative structures, not KKT factor fill.

Exact sharing finds 18 reusable definitions on DSuite and 24 on ENWL at T2,
removing 36 and 48 real variables respectively. It finds none on the delta case
or the external T8 profiles. ENWL's sharing advantage shrinks from 2.4% to 0.7%
in confirmation; the confirmed paired sharing/off ratios span 0.888–1.047.
That does not establish a practical speed benefit, especially when unchanged
T8/off versus T8/sharing controls differ by 1.2% in median. The unchanged delta
T2 sharing control also has an exploratory paired ratio as high as 1.666; that
slow trial is retained. Confirmed delta T8/T2 ratios span 0.960–1.020, while ENWL
T8/T2 ratios span 0.734–0.901. No significance or every-run improvement is claimed.

Keep all thresholds and sharing policies available, with the defaults unchanged.
For these external inputs, direct blocks avoid broad observation-lifting overhead;
for the charged delta workload, retain the existing bounded-observation option.
Earlier regional-passive comparisons remain relevant and were not remeasured
in this six-profile panel. The next distinct experiment should test reusing
existing generator P/Q dispatch definitions at matching capability bounds,
separately from affine sharing and with all original bounds and physical outputs
preserved. Broader threshold tuning requires new cases and independent validation.

Implementation: `examples/benchmark_ivr_observations.jl`; local raw JSON, input
snapshots, source hashes, protocol, confirmation and independent audit script:
`OBSERVATION_POLICY_STUDY_20261005` beside the untracked handover. See the
[theory](ivr_theory.md), [tutorial](tutorial_exact_ivr.md) and
[verification record](verification.md) for equivalence and test obligations.

## Transformer coil-current elimination — 5 October 2026

The additive `device_elimination=:transformer_currents` policy removes recorded
from-side coil currents through unit current-balance pivots. Its
[equivalence argument](ivr_theory.md) and [contract](ivr_nlp.md) retain to-side
circulation, bonds, grounds, all bounds and original physical outputs. Defaults
and earlier options remain unchanged. This experiment asks whether that exact
substitution improves Ipopt wall time independently of line elimination.

**Protocol.** Four profiles cross full/regional-block coordinates with device
elimination off/on. All use lifting off, voltage ground scaling, AMD, the same
strict settings and the same unloaded physical start. Eight rotated/reversed
sweeps place each profile in each position twice; one warm-up per profile is
excluded. Compilation, start encoding, extraction and audits do not enter the
primary metric. No tests, docs or other experiments overlap timing.

Four synthetic single-phase cases have 48/192 segments, charging off/on, a fixed
1:1 transformer replacing every fourth line (12/48 transformers) and terminal
generation bounded by a 400 VA capability circle. They inherit the earlier
transformer fixture: these are not impedance-equivalent versions of its plain
chain. The objective is source import, and every measured capability slack is
below ``9\times10^{-8}`` VA in magnitude. Two previously studied external controls
retain the original DSuite SPD Suburban/Urban electrical data and source accounting,
with feasibility objective. They have only one/four delta-wye transformers.
Their provenance and source hashes are retained; they are not unseen holdouts
or economic-dispatch evidence.

All **192/192 exploratory measurements and 24/24 warm-ups** pass solver, original
SI physics, own/full-model, reverse-map and objective-comparability checks. The
table gives median Ipopt milliseconds; `T` means coil-current elimination.

| Input | Full | Full + T | Blocks | Blocks + T |
|:--|--:|--:|--:|--:|
| 12 transformers, uncharged | 6.131 | 6.074 | 6.649 | 6.794 |
| 12 transformers, charged | 7.002 | 6.853 | 9.942 | 9.819 |
| 48 transformers, uncharged | 22.206 | 21.652 | 25.353 | 24.369 |
| 48 transformers, charged | 25.321 | 24.631 | 38.448 | 38.126 |
| DSuite 265 | 13.430 | 13.416 | 12.573 | 12.584 |
| DSuite 1,220 | 60.300 | 60.086 | 57.984 | 57.660 |

**Predeclared confirmation.** The charged 48-transformer case and DSuite 1,220
were repeated in a fresh process with all four profiles and unchanged settings,
regardless of the initial winner. All **64/64 measurements and eight/eight
warm-ups** pass. Batches remain separate; no outliers are deleted.

| Input | Full | Full + T | Blocks | Blocks + T |
|:--|--:|--:|--:|--:|
| 48 transformers, charged | 25.653 | 24.821 | 38.368 | 37.712 |
| DSuite 1,220 | 60.108 | 60.627 | 57.869 | 57.664 |

On the transformer-rich confirmation, elimination improves the full-coordinate
median by **3.2%** and the block-coordinate median by **1.7%**. Paired on/off
ratios are 0.916–0.996 and 0.955–1.031 respectively. All profiles take eleven
iterations. The pass removes 48 complex currents and 48 complex balance equations:
full variables fall from 1,450 to 1,354; block variables from 682 to 586. Supplied
Hessian entries remain 9,236 for full and 21,188 for blocks, while unique entries
fall by 96 in each case. These are derivative structures before preprocessing,
not measured KKT fill or factor memory. Smaller dimension alone does not predict
the relative speed: full + T is still substantially faster than blocks + T.

DSuite confirmation changes are −0.9% for full (a slowdown) and +0.4% for blocks
(a speedup). Paired ratios span 0.982–1.023 and 0.622–1.039, including the retained
slow baseline observation. Only 12 complex currents are removed on DSuite 1,220;
all profiles take three iterations. These small, mixed differences do not support
a practical feeder speedup claim. Likewise, the 12-transformer uncharged block
profile regresses about 2.2% in exploration. No significance or every-run speedup
claim is made.

**Recommendation.** Keep this exact pass as an optional comparator. On these
transformer-rich cases, full coordinates plus current elimination lead the tested
shortlist, with modest gains over full alone. This does not warrant a default
change or replacing the earlier feeder recommendations. Selective observation
lifting and exact auxiliary reuse are the next representation experiments;
multiwinding current elimination still requires a separate certificate.

`examples/benchmark_ivr_transformer_currents.jl` reproduces the four-profile
comparison. The [tutorial](tutorial_exact_ivr.md) includes an executable one-unit
example. Frozen source/input hashes, protocols, raw JSON, analysis and separate
confirmation are retained outside Git in `TRANSFORMER_CURRENT_STUDY_20261005`.

## External transfer of lifting and blocks — 5 October 2026

`examples/benchmark_ivr_feeder_lifting.jl` compares six fixed candidates on four
existing DSuite/ENWL files from BMOPFDraftData. These inputs have appeared in
earlier studies; they are **not unseen validation cases**. The original DSuite
SPD Suburban/Urban inputs contain 265/1,220 buses and one/four delta-wye
transformers. Reduced ENWL Network 17 Feeder 6 and Network 8 Feeder 2 contain
435/538 buses, one shunt each and 57/77 generators. The source files' existing
reductions are inherited. All declared loads are constant power.

Every profile uses the feasibility objective, voltage finite-ground scaling,
MUMPS AMD and the same strict tolerances. Source/generator accounting, demand,
equipment and bounds are unchanged. Known legacy provenance is relocated on an
owned copy; source hashes and an independent recursive comparison verify input
preservation. Each model receives the same unloaded physical circuit point,
including exact auxiliary definitions. All 24 preflights encode every variable;
the largest binding/reconstruction residual is below ``2.3\times10^{-16}`` pu.
The start need not satisfy nonlinear load equations or operating bounds.

Twelve rotated/reversed sweeps place each profile in each position twice.
**288/288 measured solves and 24/24 excluded warm-ups** pass the solver,
independent physical, own/full-model, reverse-map and objective gates. Only
Ipopt wall time ranks candidates; construction, start assignment, extraction
and audits are excluded. Tests and documentation builds do not overlap timing.
The experiment does not assess model reuse or economic dispatch. Its starts
and matched ground scaling differ from some earlier panels, so their times
must not be pooled. Feasibility solutions may differ between profiles; admission
checks each reconstructed state against the original physics and model, rather
than assuming a unique physical solution or identical returned dispatch.

Exploratory median Ipopt milliseconds follow. `Regional` means the earlier
regional/passive profile; blocks also request regional coordinates. `P` and `O`
mean power lifting and power plus bounded-observation lifting respectively.

| Input | Full | Regional | Blocks | Blocks + P | Blocks + O | Full + P |
|:--|--:|--:|--:|--:|--:|--:|
| DSuite 265 | 13.529 | 13.342 | 12.759 | 12.771 | 12.915 | 13.430 |
| DSuite 1,220 | 60.262 | 61.111 | 57.571 | 57.742 | 60.854 | 60.340 |
| ENWL 435 | 194.519 | 129.973 | 130.755 | 130.689 | 158.665 | 194.907 |
| ENWL 538 | 188.276 | 531.182 | 165.715 | 167.397 | 170.071 | 189.811 |

Power lifting adds **zero variables** on these inputs. Its profiles therefore
provide no-op timing controls, not evidence of a power-lifting benefit on real
feeders. Their median differences are below 1.1% in this batch, although paired
ratios retain substantial outliers. Do not interpret the small ordering changes
between these controls as structural improvements.

Block elimination lowers the full-IVR median by about 6%, 4% and 12% on DSuite
265, DSuite 1,220 and ENWL 538. On ENWL 435, regional/passive is about 33% faster
than full; blocks have the same variable and derivative counts and are within
1% of regional/passive. ENWL 538 behaves differently: regional/passive takes
23 iterations in every repeat, whereas the other profiles take eight. This
coincides with a roughly 69% block-versus-regional median improvement; it does
not establish why the nonlinear trajectory changed. All DSuite profiles take
three iterations; all ENWL 435 profiles take eight.

Broad observation lifting loses to blocks alone on all four inputs. On ENWL
435 it reduces supplied Hessian entries from 24,132 to 13,292 and unique entries
from 9,240 to 8,012, but increases variables from 6,604 to 8,412 and takes about
22% longer. These are structures supplied before solver preprocessing, not KKT
factor fill or peak memory. A lower Hessian-entry count alone cannot justify
a runtime selector. The earlier synthetic benefits remain valid for their
declared workloads; this transfer result does not justify deleting the option.

All outliers remain. Exploratory paired blocks/full ranges are 0.920–0.957,
0.934–1.564, 0.620–1.445 and 0.489–0.894 in table order. The ENWL 435
regional/full range is 0.613–0.739. These are observed ranges, not confidence
intervals or statistical-significance claims.

**Fresh-process confirmation.** DSuite 1,220 and ENWL 538 were repeated with all
six candidates and unchanged inputs/settings. ENWL 538 replaced ENWL 435 in an
unexecuted follow-up plan after the unexpected 23-versus-eight iteration result
appeared. The initial plan and amendment are retained. This is outcome-selected
follow-up, not unseen validation, and its timings are not pooled with exploration.
All **144/144 measured solves and 12/12 warm-ups** pass the same gates.

| Input | Full | Regional | Blocks | Blocks + P | Blocks + O | Full + P |
|:--|--:|--:|--:|--:|--:|--:|
| DSuite 1,220 | 58.034 | 59.619 | 56.943 | 56.924 | 60.024 | 59.254 |
| ENWL 538 | 189.424 | 520.408 | 169.696 | 165.928 | 171.413 | 191.138 |

DSuite's block/full median gain falls to **1.9%**, with paired ratios
0.941–1.036. The identical full/P control differs from full by 2.1% in median,
so the evidence does not support a robust practical separation of these close
DSuite candidates. On ENWL 538, blocks without lifting are **10.4% faster than
full and 67.4% faster than regional/passive** in median. The 23-versus-eight
iteration pattern repeats in every measurement. The no-op block/P control has
a 12.4% gain against full; that difference is not caused by power lifting.
Its median differs from blocks by 2.2%, illustrating remaining timing variation.
Paired ENWL block/full ratios are 0.751–1.059; the regional/full range is
2.349–2.822. Preserve the no-op block/P DSuite outlier of 3.480 times full as
well. These results do not imply that every block solve is faster.

**Refined shortlist.** For these fixed-start feasibility feeders, compare full,
regional/passive and regional/blocks with AMD and matched ground scaling. Blocks
are the leading tested candidate on ENWL 538; regional/passive and blocks are
close on ENWL 435; full and blocks remain close on DSuite. Broad observation
lifting has no median win over blocks in this transfer panel. Retain it for the
synthetic domains where it helped and for further experiments. No option is
deleted, and no package default or automatic selector changes. Nonlinear load
mixtures, IBRs, real active power-capability limits, other starts and updated-model
workloads remain outside this panel.

The runner, protocol, frozen source hashes/snapshot, raw JSON/input/manifest
files and independent analysis are retained outside Git in
`FEEDER_LIFTING_STUDY_20261005`, with confirmation in its own directory.
The [tutorial](tutorial_exact_ivr.md) gives the reproduction command. Across the
two separate batches, 432 measured solves and 36 warm-ups are admitted.

**Next exact experiments.** Test stricter observation-support thresholds and
exact reuse of auxiliaries whose composed expressions coincide, keeping the
current policy as a comparator. Do not infer factorization savings from a
symbolic support score. A distinct structural candidate is transformer
coil-current substitution: the existing stamp imposes ``j_f+R^Hj_t=0``, so
``j_f=-R^Hj_t`` can eliminate from-side coil currents through unit pivots without
inverting leakage or terminal-incidence matrices. Remaining coil circulation,
bonds, grounds, all bounds and physical exports must be preserved and verified.
The subsequently implemented `device_elimination=:transformer_currents` option
applies this substitution; the feeder study above predates it. Generic IBR filter
condensation is not a new opportunity here: filter current and internal voltage
are already affine expressions in the implemented electrical assembler.

## Exact lifting and charged-section blocks — 5 October 2026

Two additional exact choices are implemented: `linear_elimination=:passive_blocks`
uses conditioned local block substitutions, including charged π sections;
`lifting=:powers` introduces exact P/Q definitions for apparent-power limits,
and `:bounded_observations` additionally materializes compound bounded affine
voltage/current expressions. The [contract](ivr_nlp.md) and
[proof](ivr_theory.md) specify eligibility, reconstruction and numerical gates.
All earlier policies and defaults remain available.

**Protocol.** Twelve synthetic 48-segment networks cross single-phase/delta,
charging off/on and absent/binding-capability DER, plus two active-midpoint-voltage
networks and two networks containing 12 fixed 1:1 transformers. Chain length and
total demand are fixed. Transformer networks replace every fourth line with
declared leakage and a grounded secondary; they are separate inputs, not
impedance-equivalent versions of the plain chain. All original interior voltage
and endpoint current/power limits remain. Capability cases have 400 VA per
coil; the uncharged midpoint case has an independent 920 W analytical optimum.
The measured slacks verify activity; names alone do not establish it.

Each input has six candidates, the source-import objective, identical strict
Ipopt settings and MUMPS AMD. All receive the same unloaded physical circuit
point, including consistent auxiliary definitions. This matters because flat
zero-current starts generally violate charged-section KCL and cannot be encoded
by its elimination. The common start is not a solved OPF incumbent. Twelve
rotated/reversed sweeps put each profile in each position twice. One warm-up per
profile is excluded. Compilation, start encoding, extraction and audits do not
enter the sole primary score, Ipopt wall time. Tests/docs did not overlap timing.

**Exploration:** 864/864 measured solves and 72/72 warm-ups pass solver, physical,
own/full-model, reverse-map and objective-comparability gates. Median Ipopt
milliseconds are below. `Existing` requests regional/chains on uncharged inputs
and regional/off on charged inputs. Blocks request regional coordinates, although
earth-connected charging can independently prevent the conductor certificate.
`P` means power lifting and `O` means power plus bounded-observation lifting.

| Input | Full | Existing | Blocks | Blocks + P | Blocks + O | Full + P |
|:--|--:|--:|--:|--:|--:|--:|
| Single-phase, uncharged, no DER | 2.909 | 2.017 | 2.063 | 1.696 | 1.908 | 2.612 |
| Single-phase, uncharged, active capability | 8.163 | 5.228 | 5.217 | 4.854 | 5.572 | 8.372 |
| Single-phase, charged, no DER | 3.276 | 3.287 | 3.928 | 2.588 | 2.901 | 2.971 |
| Single-phase, charged, active capability | 9.350 | 9.349 | 10.419 | 8.083 | 9.590 | 9.388 |
| Delta, uncharged, no DER | 7.831 | 8.843 | 8.577 | 5.742 | 5.928 | 6.290 |
| Delta, uncharged, active capability | 18.963 | 19.180 | 18.866 | 13.515 | 13.760 | 15.708 |
| Delta, charged, no DER | 8.775 | 9.012 | 40.176 | 12.700 | 6.624 | 7.452 |
| Delta, charged, active capability | 20.735 | 20.887 | 94.812 | 30.568 | 16.447 | 17.782 |
| Active midpoint, uncharged | 6.910 | 4.367 | 4.361 | 4.048 | 4.722 | 6.895 |
| Active midpoint, charged | 7.681 | 7.708 | 5.661 | 4.757 | 6.043 | 7.378 |
| Twelve transformers, charged, no DER | 3.483 | 3.527 | 4.959 | 4.031 | 3.817 | 3.261 |
| Twelve transformers, charged, active capability | 7.353 | 7.444 | 10.487 | 9.198 | 8.709 | 7.276 |

**Fresh-process confirmation:** four cases were selected after exploration and
repeated unchanged with all six profiles. This is replication, not held-out
validation; batches are not pooled. All 288 measured solves and 24 warm-ups pass.
Input bytes, profile settings, position balance and source digests are audited.

| Confirmation input | Full | Existing | Blocks | Blocks + P | Blocks + O | Full + P |
|:--|--:|--:|--:|--:|--:|--:|
| Delta, uncharged, active capability | 19.327 | 19.306 | 19.264 | 13.779 | 14.006 | 15.949 |
| Delta, charged, active capability | 19.976 | 20.036 | 90.929 | 29.475 | 16.186 | 17.543 |
| Active midpoint, charged | 7.536 | 7.563 | 5.561 | 4.665 | 5.952 | 7.179 |
| Twelve transformers, charged, active capability | 6.974 | 6.994 | 9.921 | 8.723 | 8.403 | 7.002 |

The best tested choices reduce the median relative to full IVR by approximately
29%, 19% and 38% on the first three confirmation cases. Full wins the transformer
repeat; full and full/P differ by only 0.4% there, reversing their roughly 1%
exploratory ordering. All outliers remain. The paired winner/full ratios range
0.487–1.985 for uncharged delta, 0.789–0.825 for charged delta, and 0.600–3.363
for the active midpoint case. Median gains are not a claim of improvement on
every run or of statistical significance.

**Mechanism evidence.** Charged delta with active capability has 606 variables
in full IVR and only 42 after blocks, yet blocks alone are 4.6 times slower in
the confirmation median. Adding bounded-observation lifting creates 1770
variables and is faster than full. The supplied Hessian-entry count falls from
63,255 for blocks to 2,952 with observation lifting; unique entries instead rise
from 246 to 2,664. These are derivative structures before Ipopt preprocessing,
not factorization fill or memory measurements. They implicate expression and
derivative representation as an important investigation target, without proving
a complete runtime attribution. Lifting also changes delta capability iterations
from 12 to 11; the active-midpoint variants all take ten iterations.

**Updated experimental shortlist.** For these uncharged chains and single-phase
charged chains, regional/blocks with `lifting=:powers` is the leading candidate.
For these charged delta chains, use `lifting=:bounded_observations` as the
leading candidate. Keep full IVR/AMD and full/P as comparators; they are preferable
on the transformer panel. No general automatic selector or default change is
justified. Wider real-feeder, stiff-ground and nonlinear-load evidence remains
necessary. Raw inputs, protocols, source snapshots, times, starts, slacks and
independent audits are retained outside Git in `LIFTING_BLOCKS_STUDY_20261005`.

```julia
include("examples/benchmark_ivr_lifting_blocks.jl")
using LinearAlgebra
BLAS.set_num_threads(1)
report = IVRLiftingBlockStudy.benchmark("charged-delta.json";
    conductors=3, segments=48, charged=true, tight=true, repetitions=12)
```

## Adjacent-chain elimination with retained interior limits — 5 October 2026

`linear_elimination=:passive_chains` is an additional exact coordinate policy.
The original `:passive`, every earlier profile and all start/ordering options
remain available. The new pass uses surviving unit-pivot equations to compose
adjacent eliminations; [the proof and limits](ivr_theory.md) and
[executable tutorial](tutorial_exact_ivr.md) describe its certificate.

**Protocol.** `examples/benchmark_ivr_chains.jl` constructs two-wire single-phase
and three-wire delta chains with 12 or 48 segments and terminal demand. A
48-segment alternating-load control has no extra adjacent opportunity. Each
segment has length `1/n`, so total series impedance is fixed. Total P/Q demand
is also fixed: 2000 W/500 var for single-phase; delta P is [2000, 750, 250] W,
Q=P/4. Every interior voltage bound, 200 A conductor rating and 100 kVA phase
apparent-power rating at both ends remains present. These are synthetic,
unshunted, lightly loaded cases with slack operating limits, not real-feeder
or active-limit evidence.

Six candidates cross full/regional coordinates with elimination off/passive/
passive_chains. Every candidate uses source-import minimization, the same
strict Ipopt settings and MUMPS AMD. A preflight verifies equal reconstructed
flat physical starts to 1e-12 pu. Twelve rotated/reversed sweeps place every
candidate in every position twice; each has one excluded warm-up. The sole
primary metric is Ipopt wall time. Construction, extraction and audit times
are excluded. Tests, documentation and other Julia experiments did not overlap
timing runs. Source/input snapshots, digests, protocols, raw rows and an
independent balance/admission/objective audit are retained outside Git under
`CHAIN_STUDY_20261005`.

The first panel admits **432/432 measured solves** and **36/36 warm-ups**, with
matching objectives, independent physical checks, own/full-model checks and
reverse anchors. Median Ipopt wall time in milliseconds:

| Conductors; segments; loads | Full | Full + passive | Full + chains | Regional | Regional + passive | Regional + chains |
|:--|--:|--:|--:|--:|--:|--:|
| 2; 12; terminal | 1.320 | 1.476 | 1.537 | 1.380 | 1.376 | 1.189 |
| 2; 48; terminal | 2.941 | 3.524 | 2.887 | 3.098 | 3.322 | 2.064 |
| 2; 48; alternating | 3.438 | 4.092 | 4.115 | 3.582 | 3.794 | 3.828 |
| 3; 12; terminal | 2.431 | 3.261 | 3.634 | 2.976 | 3.338 | 3.018 |
| 3; 48; terminal | 7.510 | 11.735 | 10.925 | 9.694 | 12.028 | 8.269 |
| 3; 48; alternating | 6.323 | 10.350 | 10.398 | 9.272 | 10.981 | 10.685 |

Regional chains improve over regional passive by 14%/38% on the 12/48-segment
single-phase inputs and 10%/31% on the delta inputs. This does **not** make
chains the fastest delta formulation: full IVR remains faster there. Full
coordinates plus chains regress 4% and 11% against full plus passive on the
short single-phase/delta cases. Alternating controls have identical passive/
chain maps and derivative counts; their median differences, at most 2.7%, are
a useful noise check. All raw outliers remain: the regional delta 48-segment
paired chain/passive range is 0.261–2.435, despite its median improvement.

For the 48-segment single-phase case, regional chains reduce 156 real variables
to 12 and the supplied unique Hessian entries from 835 to 38, with two iterations
for both policies. For the delta case they reduce 268 variables to 28 and 2227
unique Hessian entries to 129, with three iterations for both. Yet full delta
IVR, with 594 variables, is faster. With full coordinates, delta-chain elimination
leaves the unique supplied Jacobian entry count unchanged at 5814 despite
reducing variables to 30. These are backend derivative counts before Ipopt
preprocessing, not factorization fill or memory measurements. They illustrate
why variable counts alone cannot identify the fastest formulation.

**Fresh-process confirmation.** The same two 48-segment terminal-load inputs
were repeated unchanged, with all six candidates and twelve balanced sweeps.
All **144 measured solves** and **12 warm-ups** passed. This batch is retained
separately, not pooled with the first panel. Median Ipopt milliseconds:

| Conductors | Full | Full + passive | Full + chains | Regional | Regional + passive | Regional + chains |
|:--|--:|--:|--:|--:|--:|--:|
| 2 | 3.145 | 3.716 | 2.979 | 3.245 | 3.552 | 2.268 |
| 3 | 7.751 | 11.690 | 11.420 | 10.699 | 12.332 | 8.614 |

Regional chains are 36% faster than regional passive and 28% faster than full
IVR on the single-phase confirmation. On delta they are 30% faster than regional
passive, but **11% slower than full IVR**. Paired regional chain/passive ranges
are 0.080–0.717 for single-phase and 0.679–0.746 for delta; the very small
single-phase minimum comes from a retained slow passive observation, not a
removed outlier. Full-coordinate delta chain/passive has range 0.908–2.470 and
only a 2.3% median improvement. No statistical-significance claim is made.

**Workload-specific choice.** For the demonstrated terminal-load single-phase
chains, regional coordinates plus `:passive_chains` and AMD are the fastest
measured candidate. For these delta inputs and alternating-load controls, retain
full IVR plus AMD as the leading comparator. This refines the earlier regional/
passive starting recommendation; it does not replace package defaults or justify
a topology-only automatic selector. Larger real feeders, active interior bounds,
heterogeneous long chains and update histories need their own measurements.
Compilation cost plays no role in these choices.

## Earlier starting configuration: regional IVR with AMD

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-1).

### Selection and transfer evidence

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-2).

### Isolate reduction after fixing the ordering

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-3).

### What the detailed solver logs establish

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-4).

### Reproduce the ordering comparison

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-5).

## Earlier Ipopt evidence with automatic ordering

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-6).

### Dispatch changes can reverse the ranking

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-7).

### What the solver timing breakdown suggests

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-8).

## Historical build-plus-solve comparison — 5 October 2026

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-9).

## Compare the workload that matters

For the current assessment, compare Ipopt wall time for a declared initial state
and workload. Fresh and reused models, parameter updates and previous-primal
warm starts require separate controlled experiments. Recording their preparation
and extraction costs is useful for provenance, but these costs do not enter the
primary formulation ranking. The studies here exclude warm-ups.

The experimental runner in `examples/benchmark_ivr_profiles.jl` preserves a
12-profile shortlist: full, complete conductor difference, pendant regions,
passive elimination combined with those coordinates, finite-ground scaling,
and bound-support selection. It is not an exhaustive Cartesian search. All
other valid option combinations, including standalone impedance elimination,
remain callable and can be supplied through the runner's `candidates` argument.

```julia
include("examples/benchmark_ivr_profiles.jl")
using LinearAlgebra
BLAS.set_num_threads(1)
report = IVRProfileStudy.benchmark(network, "/tmp/ivr-profiles.json";
    repetitions=4, candidates=IVRProfileStudy.profiles(objective=:feasibility))
```

The explicit feasibility objective makes this a numerical feasibility study.
For an OPF objective, request it consistently across all profiles. The ranking
withholds a winner if accepted objective values differ beyond its declared
comparison tolerances; solving a different local optimum faster is not silently
counted as an equivalent speed improvement. Objective agreement is not a global
optimality certificate or a check of the economic meaning of the input data.

Each profile has an excluded warm-up. Measured sweeps reverse each pair's order
and rotate the starting position between pairs. Four sweeps over 12 profiles
are exploratory, not fully position-balanced. Save the raw trials and confirm
promising choices with new paired runs. Do not overlap timings with tests,
documentation builds or profiling.

## Admission before ranking

A measured trial must satisfy strict solver acceptance, the independent SI
physical audit, its own compiled model, a fresh full model, and reverse mapping
of a full-feasible anchor point into the candidate model. The first accepted
warm-up supplies that anchor. Bounds, coefficients, objective and electrical
inputs are not modified to obtain acceptance. Errors and failed trials remain
in the output; they are not retried with relaxed settings.

A profile must have an accepted warm-up and every requested measured repeat to
enter the ranking. The report gives `fastest_ipopt` as the primary winner and retains
`fastest_total` and `fastest_solve` as secondary diagnostics, with exact options
and provenance. A fast failed or incomplete profile cannot
win. The runner does not mutate a production default or silently replace the
user's chosen representation.

Profile selection itself costs time: reference construction, warm-ups, audits,
all competing runs and evidence output are excluded from each candidate's
Ipopt score. The report separately records `total_study_s`. Tune an
intended repeated workload and reuse its explicit configuration; running the
entire portfolio before every single solve is not a speed optimization.

```julia
name = report["ranking"]["fastest_ipopt"]
name === nothing && error("No comparable accepted winner")
candidate = only(filter(p -> p.name == name, IVRProfileStudy.profiles()))
formulation = IVRNLP(candidate.options)
```

Use the **same candidate list/objective** when looking up the chosen name, and
retain the reported input digest, solver settings and software versions with
any recommendation. Rerun the study when the workload or inputs change.

## Model reuse and previous-primal initialization

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-10).

### Measured sequence evidence — 5 October 2026

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-11).

## Transfer to external feeder demand sequences

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-12).

### External-feeder initialization evidence — 5 October 2026

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-13).

### Matched fresh/reused feeder evidence

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-14).

### What is reused inside the installed solver wrapper?

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-15).

### Design requirements for reconstructed-dual starts

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-16).

## Explicit reconstructed-dual initialization

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-17).

### Declared screen and confirmation design

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-18).

### Balanced synthetic confirmation

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-19).

### Feeder transfer and strict rejection

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-20).

### Interpretation of the transferred multipliers

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-21).

## Distinct operating histories and changing reactive limits

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-22).

### Balanced history results

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-23).

### Active limits and transition evidence

This evidence is retained in the [historical study](ivr_performance_history.md#ivr_performance-history-24).

## Why the structural selector is still optional

The bound-support rule can avoid growth in some operating-bound expressions,
but it does not estimate actual factorization fill or runtime. It previously
added substantial preparation work even when every DSuite candidate remained
selected. Preparation now indexes only a conservative superset of coordinates
that a series candidate could remove, composes the relevant rows once, and
shares resolution caches within each before/after check. Cache lifetimes never
cross a change to the tentative substitutions.

This optimization changes no selection criterion, bound, coordinate map or
formulation option. The frozen implementation, exact model/decision audit,
paired allocation experiment and raw evidence are retained. See
[verification](verification.md) for measured results and limitations.

## Current evidence and remaining uncertainty

The earlier experiments establish useful reductions and specific accuracy
improvements, but no universal fastest exact formulation. Fewer variables or
Hessian entries alone do not establish a faster solve; normalized residuals do
not establish physical accuracy. Full IVR remains the physical reference, and
all alternative coordinates remain experimental choices supported by explicit
contracts and tests.

A best-evidence recommendation must name its measured domain. The initial
feeder portfolio uses selected inputs with an explicit feasibility objective;
the subsequent dispatch studies use cost objectives. This cannot establish the
fastest formulation for general dispatch, different optimizers, nonlinear-load
mixtures or untested transformers. The repeated-update evidence covers manufactured single-phase/delta dispatch
and selected external feeder demand sequences, not arbitrary operating histories.
Broader mixed-port certificates and factorization-aware selection remain
separate priorities.
