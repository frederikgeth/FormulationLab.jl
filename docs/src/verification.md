# Verification

## Physical circuit-row residuals — 6 October 2026

The [read-only circuit-row diagnostic](ivr_circuit_residuals.md) passes
**12,193 new targeted assertions**. Tests verify ampere/volt provenance,
retained versus implied rows, KCL-only capping, independent SI line/winding
residuals, precision restoration and unchanged native solutions. Production
formulation equations, options and defaults are unchanged.

The matched 32-endpoint trace retains two failed KCL controls and admits the
other 30 endpoints. All 38,144 classified row evaluations and three unclassified
ordinary-transformer voltage equations per endpoint remain explicit. Full
regression and documentation logs are archived with the source, input and
native-coordinate records in `CIRCUIT_ROW_RESIDUALS_20261006` outside Git.

A separate monitored timing attempt completed 16 exploration cells before
external Julia computation appeared. Its entire campaign is excluded; no
confirmation or eligible speed ranking is reported. The monitor stopped only
its own benchmark session. Negative timing evidence is retained in
`NWINDING_COORDINATE_TIMING_20261006`.

## Multiwinding nominal-coordinate contract, 6 October 2026

Full regression passes **164,684/164,684 assertions**, including 530 new
assertions, in 6m57.6s. This correctness runtime is not optimizer timing evidence.

The opt-in `transformer_scaling=:nominal_multiwinding` has focused tests for
coil-nominal units, single-phase dispatch, mixed delta/wye connections, nominal
graph conflicts, unchanged floating-reference refusal, reversible maps,
original current/power bounds, and recovered SI JSON. The ordinary-only policy
and default remain unchanged. The [scientific guide](ivr_nwinding_coordinates.md)
records the units convention, equivalence argument, usage and limits.

The matched capped preflight admits 96/96 endpoints; 96 independent SI export
audits and 96 comparisons through both result readers pass. A distinct 96-row
coordinate/cap preflight retains the two failed ordinary-only uncapped controls,
while both multiwinding arms pass 24/24 cells. All these runs are excluded from
speed evidence. Plans, full input/result records, negative outcomes and hashes
remain outside Git.


## KCL residual tracing and optional row-unit cap — 6 October 2026

The [residual study](ivr_kcl_residuals.md) compares twelve matched solves and
96 originally violated row locations. It reproduces all three uncapped
rejections and distinguishes a conversion factor of 3.866 million A after
current elimination from about 10.05 A with explicit currents. Compared
arithmetic effects remain below ``1.8\times10^{-11}`` A.

The optional `kcl_row_max_base=1000.0` admits **96/96** original regional cases,
versus the retained uncapped **93/96**. All 96 SI export audits and both-reader
comparisons pass; maximum independently audited KCL is below
``5.247\times10^{-11}`` A. The 328 diagnostic and 457 cap assertions pass.
The complete regression log is archived alongside these checks. Only retained
KCL equality normalization changes; solver tolerances, physical bounds, maps
and defaults are unchanged. Iterations improve in 20 cases and worsen in 17;
no isolated wall-time claim follows. Source snapshots before and after the
intervention, failed controls and original development errors remain outside
Git in `NWINDING_KCL_RESIDUAL_TRACE_20261006`.

## Regional multiwinding current units — 6 October 2026

The [regional-current panel](ivr_nwinding_network.md#Regional-current-units-across-transformer-boundaries)
passes **3,796/3,796 targeted assertions** and admits **93/96 preflight endpoints**.
All 96 exports pass both result readers. Independent SI audits reject the same
three endpoints as the original physical checks: 24 KCL violations above 1 μA,
despite `LOCALLY_SOLVED`. All options and failed endpoints are retained.
All three reproduce with identical iterations/objectives in a fresh process,
while native constraint violations remain below ``5\times10^{-13}``.
No relaxed tolerances or timing promotion are used.

In the ordinary-only nominal policy used by this historical panel, multiwinding
voltage propagation is skipped; secondary circuits retain the global base. This study
preserves that fallback while varying only regional current-power seeds, with
assembly/generator/auxiliary units fixed. Composed linear row normalization may
respond. The unchanged high/high controls reproduce all 24 preceding factorial
iteration counts and objectives. Raw data, test-development failures and
independent validation live outside Git in `NWINDING_REGIONAL_CURRENT_20261006`.

## Independent multiwinding assembly/generator units — 6 October 2026

The [crossed-base preflight](ivr_nwinding_network.md#Separating-assembly-and-generator-units)
passes **96/96 physical cases**, **96/96 independent SI export audits** and
**96/96 BMOPFTools/FormulationLab reader comparisons**. The new targeted regression
passes **1,010/1,010 assertions**; the preceding complete suite remains the
158,563-assertion checkpoint below, rather than an unexecuted cumulative claim.
Only assembly and explicit generator units vary within each fixed representation.
Physical data, objective divisor, auxiliary units and strict settings are fixed.
All sixteen settings per size/objective share a physical start and feasible anchor.

At 243 buses, tracking with 100 kVA assembly units needs 49/50 iterations for
explicit/eliminated power lifting with 100 kVA generator units, versus 23/23
with 1 kVA generator units. Cost behaves differently; the conditional iteration
comparisons show an interaction, not a universal scaling rule. Preflight wall
times are excluded. Raw evidence and original test-comparison failures remain
outside Git in `NWINDING_SCALING_FACTORIAL_20261006`.

## Coupled mixed-device multiwinding networks — 6 October 2026

Full regression passes **158,563/158,563 assertions**, including **242 new
network assertions**. The [manufactured network extension](ivr_nwinding_network.md)
uses 2/8/24 live non-star units, ordinary transformer boundaries, pi-lines,
voltage-dependent loads, filtered IBRs and two explicit power objectives.
The tests preserve individual winding bounds and verify cross-unit supply
coupling. Voltage-law load changes retain the existing rebuild requirement.

All **48 preflight cases** pass strict status, physical and full-model membership,
independent winding equations, live-port and objective checks. All 48 SI exports
pass both readers. Independent checks include 19,200 KCL balances, 14,688 voltage
bands, 29,760 line-current bounds, 6,528 coil powers, 8,304 recovered winding
terminal currents, 3,264 coil caps and 1,088 IBR internal-power channels.

Three isolated timing attempts were interrupted by competing Julia work. All
entire campaigns are retained and excluded from performance claims. Sixteen
separate structural diagnostic solves and sixteen warm-ups pass, with actual
MUMPS order 2 for request 7; their concurrent wall times are also excluded. Correctness
and structural evidence do not require an uncontended timing window. Raw data,
source snapshots, development failures and validation scripts remain outside Git
in `NWINDING_FEEDER_TRANSFER_20261006`. Despite the archive name, this is
manufactured-network evidence; the plain-JSON external inventory contains no
explicit multiwinding records.

## Isolated lifted multiwinding timing — 6 October 2026

The [four-arm comparison](ivr_nwinding_timing.md) passes **7,168/7,168 measured
solves and 896/896 warm-ups** in two fresh processes. All 224 batch/case cells
pass strict physical, own/full/reverse membership, independent transformer
equations and cost checks. Inputs equal the preceding 112-case panel; all 260
frozen source/environment hashes remain unchanged. A two-second monitor records
54 samples without observing competing Julia work, subject to sampling limits.

All 448 start preflights pass, and the raw-report audit verifies every trial's
encoding, admission, objective, unchanged input and balanced schedule. Maximum
within-case objective spread is below 1.181e-12. Sixteen separate verbose solves
and sixteen excluded diagnostic warm-ups pass; actual MUMPS order is 2 for
request 7. Native factorization timers are too coarsely rounded to resolve costs
on these tiny models. All raw evidence remains outside Git in
`NWINDING_ELIMINATION_TIMING_20261006`.

This checkpoint adds a benchmark runner and scientific documentation. Production
code and the full-suite checkpoint remain **158,321/158,321**; the full suite was
not repeated for this example/documentation change. Focused benchmark admission,
timing and ordering regression checks pass **68/68 assertions**. It does not add a new
physical JSON export audit or rerun BMOPFTools.

## Optional multiwinding current elimination — 6 October 2026

Full regression passes **158,321/158,321 assertions**, including **5,375 new
elimination assertions**. The [optional block pass](ivr_nwinding_elimination.md)
preserves full-model witnesses, every coil bound, taps, finite grounds,
excitation, load updates and SI recovery. Singular, structurally unsuitable or
numerically unsafe blocks retain their original coordinates and equations.

The 672-attempt four-winding diagnostic admits 336/336 explicit-current controls
and 280/336 eliminated-current cases. Both lifted variants admit 112/112.
Unlifted elimination admits 56/112: all active-cap cases fail strict termination
(55 `ALMOST_LOCALLY_SOLVED`, one `ITERATION_LIMIT`). Every failed model admits
the original feasible point. Failed statuses remain excluded, without relaxing
tolerances or claiming nonequivalence.

All 616 strict SI exports pass independent auditing and both result readers.
Checks cover 7,040 KCL balances, 1,680 coil caps, 924 excitation contributions,
9,328 terminal channels, 7,392 coil channels, 560 cap-tightening certificates
and 616 pair-change certificates. All agree with retained prior equality-treated
BMOPFTools endpoints; those reference solves were not rerun. New JSON policy and
block diagnostics are additive metadata. No timing ranking or default change
follows. The initial serialization/test failures, corrections and all outcomes
remain outside Git in `NWINDING_ELIMINATION_20261006`.

## Four-winding non-star correspondence — 6 October 2026

Full regression passes **152,946/152,946 assertions**, including **15,461 new
non-star leakage and recovery assertions**. The [four-winding study](ivr_nwinding_nonstar.md)
admits all 336 native solves and 112/112 equality-treated reference cases on
passive pair data that provably cannot be represented by an ordinary star.
Original paired-Q reference controls admit 109/112; two miss cost/current
agreement and one returns `OTHER_ERROR`. Every endpoint remains archived.

Independent SI auditing covers 560 exports, 6,400 KCL balances, 1,680 coil caps,
840 excitation contributions, 5,088 native terminal channels and 4,032 native
coil channels. All 557 admitted endpoints pass. The two economically excluded
controls also pass; the solver-error endpoint exceeds the stricter fixed-Q
threshold with a 1.843e-4 var residual. Its failure and the 1e-5 var threshold
are retained. All 336 native exports pass the on-disk BMOPFTools reader check.

Native physical/model checks verify 336 pair-change and 336 bound-tightening
rejections; the independent audit verifies 560 of each across its larger
native/reference set. This adds regression and correspondence evidence without
changing production transformer equations, removing options or ranking timings.
Raw evidence and version-pinned reference sources remain outside Git in
`NONSTAR_FOUR_WINDING_20261006`.

## Isolated single-phase timing confirmation — 6 October 2026

The [fourth timing attempt](ivr_singlephase_transfer.md#Isolated-confirmation-—-6-October-2026)
completes **1,944/1,944 measured solves and 216/216 warm-ups** with strict
solver, physical, own/full/reverse membership, objective and expected voltage
active-set checks. All 276 frozen hashes remain unchanged. A two-second monitor
records 142 process snapshots without detecting competing Julia work; it does
not exclude all system load or shorter jobs. All prior contaminated campaigns
remain excluded from speed statistics.

The raw-report audit verifies complete common-start encoding, declared numerical
policies and power-objective reconstruction (maximum error below 1.78e-15).
Maximum within-cell objective spread is below 2.44e-13. Timing uses Ipopt.jl
optimizer-call wall time and excludes construction, extraction and audit costs.
Both batches and every raw tail are retained outside Git in
`SINGLEPHASE_ISOLATED_R4_20261006`. This checkpoint changes documentation only;
production code and tests remain at the preceding **137,485/137,485** regression
checkpoint. It does not claim a new independent SI-current export audit.

## Guarded voltage equalities under power costs — 6 October 2026

Full regression passes **137,485/137,485 assertions**, including **1,162 new
dependency and power-cost assertions**. The [guarded voltage option](ivr_voltage_dependencies.md)
uses exact normalized affine identity and structural circuit propagation; it
changes no default or declared engineering limit.

The diagnostic panel retains all 432 solve attempts. Guarded equalities and
separate inequalities each admit 144/144 cases. Plain equalities admit 116/144:
12 solver errors and 16 strictly solved, physically feasible endpoints that fail
objective agreement. All exclusions occur with duplicate declarations. These
are local optimizer comparisons, not global-optimality certificates or timings.

Independent SI auditing passes for all 420 strict endpoints, including the 16
economically excluded controls. It checks 1,632 current margins, 1,656 KCL
balances, 828 fixed-voltage channels, 432 switch channels and 840 two-sided
restriction certificates. All 420 exports pass the BMOPFTools reader comparison.
Raw failures, the unlifted preflight and the corrected initial test parse error
remain in the external `VOLTAGE_EQUALITY_TRANSFER_20261006` archive.

## Coincident voltage bounds — 6 October 2026

Full regression passes **136,323/136,323 assertions**, including **1,490 new
voltage-representation assertions**. The optional
[`coincident_voltage_bounds=:equality` policy](ivr_voltage_equalities.md) preserves
the default separate inequalities and records each exact matched pair.

The 192-solve manufactured comparison admits 96/96 equality treatments and
95/96 separate controls under standard physical/model/objective gates. All
solves converge strictly. The additional independent export audit flags three
separate-control π-loss identity discrepancies, including the objective-discrepant
control; combined admission is 93/96 separate and 96/96 equality. Its stricter
threshold is retained, and the original report flags remain visible.

The SI audit covers 192 exports, 960 current margins, 864 KCL balances and 384
fixed-voltage observations. All 384 two-sided voltage-rejection certificates pass,
and all 192 exports pass the BMOPFTools reader comparison. These results neither
certify global optimality nor change the speed shortlist. The third isolated
single-phase timing attempt is excluded after detecting another Julia process;
882 saved measured trials and 99 warm-ups remain as partial validation evidence.

## Fixed-Q equalities and explicit excitation — 6 October 2026

Full regression passes **134,833/134,833 assertions**, including **4,320 new
excitation assertions**. The optional fixed-Q diagnostic hook passes 32 separate
checks; 300 archived native exports pass the live BMOPFTools reader comparison.

The [equality intervention](ivr_nwinding_equalities.md) admits all **200/200
equality-treatment reference solves** against three native formulations each.
Original opposing-inequality controls remain: 38/40 and 19/40 admissions without
excitation, 55/60 and 32/60 with explicit excitation, under baseline and absolute
stopping respectively. All 300 native solves pass. These are manufactured
physical-correspondence and mechanism experiments, not timing measurements.

Independent auditing covers 700 exports, 6,020 nodal balances, 1,680 coil-cap
observations and 1,260 excitation contributions. One excluded reference endpoint
fails fixed-Q and KCL checks; its raw results remain. All admitted reference and
all native exports pass. Equalities remove the tested multiplier redundancy;
this does not establish global optimality or universal constraint regularity.

## Live mixed-winding comparison — 6 October 2026

Full regression passes **130,513/130,513 assertions**.

The [connection transfer](ivr_nwinding_connections.md) adds **2,700 native
assertions** and an optional live measurement runner. All 240 native live-panel
solves converge strictly and pass physical/model checks. Of 120 comparisons per
stopping panel, 114 are fully admitted under baseline settings and 57 under
additional absolute dual/complementarity tolerances. All rejected statuses and
objective discrepancies remain explicit; feasible reference endpoints do not
override these gates.

An independent SI audit checks 80 reference and 240 native exports, 2,752 nodal
balances, 480 coil-cap observations and the coupled leakage/ampere-turn equations.
All 120 bounded native cases reject separately tightened caps. The reference
JSON reader accepts all native exports. No speed or general excitation/tap
parity claim follows.

## Inherited MV shunt boundaries — 6 October 2026

The [independent external-feeder panel](ivr_external_shunts.md) admits **24/24
comparisons** across six formulations, two directions and both Ipopt scaling
policies. A separately selected French feeder preserves all original fields;
its selected cable reaches the inherited 428 A limit at opposite endpoints
under opposite reactive requests. All **48 tightened-rating certificates**
reject only the intended selected-line endpoint family, including 24 cases
where the series current remains below the tightened cap.

An independent audit checks all 24 SI exports, 576 line-port margins, 360 KCL
balances, 360 voltage intervals, π-line equations, powers, objective and exact
manifest replay. Tiny signed slacks and cross-language roundoff differences
remain explicit. This documentation/evidence checkpoint changes no package or
test code; the last full regression remains 127,813/127,813 assertions at
`cebc919`. These external admissions are reported separately from that count.
No new speed ranking follows.

## Joint current/voltage restrictions — 6 October 2026

The [joint-boundary panel](ivr_joint_boundaries.md) passes **144/144 manufactured
admissions** and **96 restriction certificates**. Relaxing voltage alone or
current alone improves the objective and violates only that original bound
family; joint points remain feasible in both controls. All six formulations,
both Ipopt policies, both directions and single-phase/delta devices are covered.
The focused suite passes **1,985 assertions**.

The independent audit checks 144 SI exports, 720 line-port margins, 288 selected
voltage margins, π-line equations, P/Q products, objectives and manifest replay.
Every joint result is near both boundaries; tiny negative slacks remain labelled
violations rather than being counted as strict activity. The study and a
self-contained [tutorial](tutorial_joint_boundaries.md) state this qualification.
No global-optimality or speed claim follows from these correctness checks.

## Shunt-loaded line endpoint boundaries — 6 October 2026

The [shunt-boundary extension](ivr_shunt_boundaries.md) passes **96/96
manufactured admissions** across single-phase/delta devices, inline/linecode
matrices, both target directions, both solver policies and six retained arms.
Only one endpoint is active in each case. All 96 separately tightened-rating
witnesses reject the active end while the opposite end remains below the cap.
The focused suite passes **1,669 assertions**, including rating precedence,
permuted terminal names, invalid observations and exact shunt/series recovery.

Independent SI export auditing verifies 480 manufactured port margins, 1,632
archived real-feeder line records and 9,792 external port margins. It checks
the full π-line equations, complex losses, objective, original fields and
matching output structures. The inherited source-branch shunts are recovered
but their ratings remain inactive. This distinction prevents manufactured
activity from being misreported as new real-feeder active-shunt evidence.
All existing options remain; no performance ranking is changed.

## Inherited line-current boundaries — 6 October 2026

Full regression passes **124,159/124,159 assertions**, including **654 new
assertions** for source-preserving additions, explicit objectives, single-phase
and delta active-current boundaries, both directions and both solver policies.

The [local reactive-transfer study](ivr_line_boundaries.md) passes **24/24
real-feeder admissions** across six retained formulations, two directions and
both Ipopt policies. Each endpoint reaches all three inherited 600 A conductor
limits at both line ends. Transformer caps remain inactive, with at least
13.47 kVA per-phase slack. All original electrical fields and ratings remain.

An independent Python audit reconstructs native delta powers, the objective and
the selected line's coupled voltage-drop equation from SI exports. It verifies
9,792 line-port margins, 72 transformer margins, exact addition-manifest replay,
source bytes and matching physical/native-device output structures. All 24
separately tightened line-rating witnesses reject the unchanged recovered
point in both the physical and model audits. These are correctness results;
there is no new timing ranking or global-optimality claim.

## Inherited transformer export boundaries — 6 October 2026

Full regression passes **123,505/123,505 assertions**; all **59 executable
tutorial blocks** pass. The single-phase runner
suite passes **898 assertions**, including 446 new checks for physical capacity
scaling, unchanged equipment and numerical units, inherited/domain-floor voltage
policies, invalid scales, active two-wire nameplates and tightened-bound
rejection. Every existing numerical option remains available.
The capacity multiplier is checked in floating point before integer-valued
ratings are multiplied, preventing silent machine-integer overflow.

The [equipment-boundary study](ivr_equipment_boundaries.md) passes all **72
supported real-feeder admissions** and retains **36 expected voltage-domain
refusals**. Export tracking reaches all three inherited nameplate caps across
all nine arms and both Ipopt policies. Wide-band tracking also reaches five
upper-voltage limits; positive-floor tracking has no active added voltage bound.
The independent SI export audit checks 29,376 inherited line-current margins,
216 nameplate margins, power objectives, filter losses and output structure.
All 72 tightened-nameplate witnesses and eight additional voltage/current
rejection witnesses pass. Original line ratings remain inactive. No timing or
global-optimality conclusion follows from this correctness panel.

## Single-phase voltage-bound transfer — 6 October 2026

Full regression passes **123,059/123,059 assertions**; all **58 executable
tutorial blocks** pass. The 452 new assertions check source-preserving scenario
construction, exact addition manifests, preservation of existing bounds,
activity/violation reporting, numerical factor isolation and full/reduced
single-phase solve agreement. Every transformation and package default remains.

All **108 real-feeder admissions** pass across nine numerical arms, three
voltage bands, two power objectives and two Ipopt policies. The first two bands
are inactive; a separately declared sequential extension reaches two upper
voltage bounds for cost and five lower bounds for tracking. All numerical
treatments reproduce those active sets. The independent export audit verifies
108 matching physical structures and objective/filter-loss identities, 44,064
inherited line-current margins and 324 nameplate margins. Equipment bounds
remain loose. See the [single-phase study](ivr_singlephase_transfer.md) for the
selection exclusions, sequential design, exact claim and timing protocol.

The attempted timing campaign passes **1,944 trials and 216 warm-ups**, including
all expected active sets. Its process monitor detects a competing Julia job,
so the entire campaign is **excluded from performance claims**. Raw timings
and isolation failures remain outside Git; the speed-analysis script refuses
the contaminated campaign. No default or fastest-profile recommendation changes.

## Scalar multiwinding power-limit parity — 6 October 2026

Full regression passes **122,607/122,607 assertions**; all **57 executable
tutorial blocks** pass.

The [multiwinding limit study](ivr_nwinding_limits.md) closes the scalar
winding-total/per-coil discrepancy under the opt-in BMOPFTools policy. The
native per-coil policy, explicit vectors, current limits and every numerical
option remain available. **974 targeted assertions** cover analytical active
dispatch, exact recovery, SI exports, non-star mixed-winding witnesses, unequal
vectors, zero/absent caps and invalid declarations. The optional live suite
passes **1552 assertions** across 16 per-unit BMOPFTools solves and 48 exact-IVR
comparisons, including single/three phases, forward/reverse flow, two power bases,
active/absent caps and three lifting modes. Scalar cap and SI export parity
is established for that declared panel; full multiwinding device-law parity
remains outside the claim. Tutorial section 55 constructs the 180 W analytical
dispatch example. Raw evidence and reference hashes are stored outside Git.

## Multiple-MV-site scaling transfer — 6 October 2026

Full regression passes **121,633/121,633 assertions**. The 53 new checks verify
explicit row/column subsets, preservation of default controls, invalid
declarations, benchmark forwarding and position-balanced evidence. The targeted
runner suite passes 166 assertions; all **56 executable tutorial blocks** pass.
See the [six-MV-site transfer](ivr_mv_scale_transfer.md) for scientific scope,
selection and results. Package defaults and all transformation options remain.

All **48 admission solves**, **192 tightened-bound rejection witnesses**,
**576 measured solves** and **96 warm-ups** pass. QA reproduces 112 paired
contrasts and 32 interactions; SI objective discrepancy is below 2.49e-9 and
within-cell spread below 1.94e-9. Original physical fields and limits are
preserved. No inherited network limit is active in these endpoints, so this
panel does not establish performance near active voltage, line or nameplate
bounds. After isolated timing, 24 NLPDiagnostics evaluations verify the complete
Jacobian row/column identity at common SI points to scaled error below 2.23e-16,
without derivative failures or finite-difference fallback.

## Independent load-power rows — 6 October 2026

Full regression passes **121,580/121,580 assertions**, including **21,531 new
checks** for selective residual multiplication, unchanged primal coordinates,
all unselected constraints and bounds at off-manifold points, single-phase/delta/
wye loads, signed/zero demand, full/reduced coordinates, independent row/column
units, original-model membership, SI JSON recovery, declaration ownership and
invalid/composed-unit guards. The eight-arm study isolates columns and row
groups on the prespecified objective-specific finalists. All **55 executable
tutorial blocks** pass. See the [row/column study](ivr_load_power_rows.md).

The frozen row/column campaign passes all **1024 measured solves and 128
warm-ups**. QA verifies **160 paired contrasts and 48 paired interactions**,
with objective reconstruction error below 4.53e-10 and within-cell spread below
6.22e-11. Timing is isolated and ranks only Ipopt wall time. NLPDiagnostics
checks 32 evaluations at common SI points; every complete Jacobian matches the
predicted row/column transformation to a maximum scaled discrepancy below
2.23e-16. No derivative-evaluation failure occurs. Row-norm improvement alone
does not establish a faster formulation; the assembly-row control remains.

## Independent load-power units — 6 October 2026

Full regression passes **100,049/100,049 assertions**, including **2826 new
checks** for independent load-unit inverses, exact physical recovery, signed/zero
demand, single-phase/delta/wye connections, full/reduced coordinates, unchanged
other auxiliaries, SI JSON round-trips, bound rejection, option precedence and
ownership, invalid declarations and isolated study factors. All **54 executable
tutorial blocks** pass. Defaults and all previous transformation options remain.

The [independent-unit study](ivr_load_power_units.md) isolates load-power columns
from electrical, generator and other lifted-power units. Its declared MV/LV and
nominal-power rules are experimental profiles, not automatic compiler policies.

The two isolated batches pass all **2304 measured trials and 192 warm-ups**.
Independent QA verifies frozen source, input preservation, per-load assignments,
complete starts, option isolation, objective agreement and **272 paired
contrasts**. Maximum objective reconstruction discrepancy is below 5.04e-10;
within-cell spread is below 1.81e-10. Every candidate remains eligible. The
[results](ivr_load_power_units.md) qualify the limited and objective-dependent
speed effects; only Ipopt wall time ranks.

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
