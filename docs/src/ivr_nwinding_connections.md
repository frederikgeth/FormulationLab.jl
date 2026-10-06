# Live mixed-winding transformer comparison

The [scalar winding-limit study](ivr_nwinding_limits.md) established live
BMOPFTools agreement for lossless all-wye circuits. This extension introduces
finite leakage, wye/delta connections and both delta orientations. It separates
physical correspondence from strict convergence and objective agreement.
**All 240 native solves converge and pass their physical/model checks.**
The complete live comparison admits 114/120 rows under the baseline stopping
settings and 57/120 under additional absolute dual/complementarity tolerances.
Rejected comparisons remain in the report. No speed ranking is made.

## Circuit and scope

`_nwinding_connection_case` in `test/ivr_nwinding_limit_fixtures.jl` constructs
three windings with connections YYY, YDY or DYY. Each delta connection is tested
with `delta_roll=+1` and `-1`; YYY has one orientation, giving five configurations.
The reference winding is supplied by fixed balanced 230 V phase phasors.
Wye nominal coil voltages are ``230,115,57.5`` V; a delta winding's nominal
coil voltage is multiplied by ``\sqrt{3}``. These are unequal nominal turns,
with no tap fields. The winding resistances are ``0.02,0.005,0.00125`` Ω on
their respective coil bases. Pairwise short-circuit reactances, referred to
winding 1, are ``x_{12}=0.04``, ``x_{13}=0.06`` and ``x_{23}=0.05`` Ω.

All excitation is zero. Wye neutrals are perfectly grounded. A delta secondary
explicitly grounds terminal `c` to fix its common-mode voltage; the fixture
does not infer a missing earth connection or eliminate a coil circulation mode.
Three single-phase load/generator pairs connect to the secondary phases or
phase pairs. Their signed loads are ``\pm(200,160,120)`` W, with zero reactive
power. Each generator has zero Q and either ``0\leq P\leq300`` W or
``-300\leq P\leq0`` W. Linear prices have the corresponding sign, so the
cost minimizes the magnitude of local active generation. Single-phase dispatch
devices isolate transformer-connection behaviour from delta-generator export
conventions. The third winding remains unloaded.

The bounded treatment puts a scalar 300 VA limit on winding 2: 100 VA per
coil under the explicit `:bmopftools` nameplate policy. The control omits this
limit. Cross five configurations, both flow directions, bounded/unbounded
windings and 1/100 kVA assembly bases: **40 physical/base cases**. Each native
comparison uses off, power or bounded-observation lifting, giving 120 rows per
stopping panel. Nominal coordinates, composed circuit rows, signed observation
sharing and the existing reduction options are retained. General multiwinding
currents themselves remain explicit; ordinary-transformer current elimination
does not eliminate them.

The live dependency is BMOPFTools revision
`a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`. Both implementations solve in
per-unit coordinates and export SI quantities. The reference checkout is clean;
relevant source hashes are recorded. This is a manufactured three-winding
comparison, not a feeder transfer or a four-winding non-star leakage test.

## Stopping settings and retained diagnostic stages

Baseline settings are `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, `max_iter=500` and explicit `nlp_scaling_method="gradient-based"`.
The objective-agreement test uses `atol=1e-7, rtol=1e-6`; this is tighter than
the preceding all-wye comparison's absolute tolerance of `1e-5`.

An exploratory 40-case screen found two objective discrepancies. An initial
export-reader error also attempted to treat the transformer loss record as a
winding record; its script, log and results are preserved separately. Correcting
the reader did not change the circuits or solver settings.

Detailed logs for the two discrepancies show `LOCALLY_SOLVED` with small
scaled overall errors but unscaled dual residuals of approximately
``7.63\times10^{-6}`` and ``1.34\times10^{-6}``. The first also has
complementarity approximately ``2.42\times10^{-6}``. Both recovered points
pass the independent SI audit and the native full model. Explicitly switching
Ipopt gradient scaling off reproduces these diagnostic outcomes. Thus the
configured overall `tol` alone does not establish equally small unscaled dual
and complementarity residuals.

A subsequent, separately retained panel adds
`dual_inf_tol=compl_inf_tol=1e-10` to **both** solvers. It preserves the original
settings and every physical declaration. This is a diagnostic intervention
chosen after the initial discrepancies; it is not a prespecified held-out
confirmation or a new default. Tighter settings recover close objective
agreement for the two selected diagnostic points, but one returns
`SLOW_PROGRESS`. The complete panel reveals wider convergence regressions.

## Outcomes and admission

| Stopping panel | Strict reference solves | Strict native solves | Objective agreement | Fully admitted comparisons |
|:--|--:|--:|--:|--:|
| Baseline | 40/40 | 120/120 | 114/120 | 114/120 |
| Additional absolute tolerances | 19/40 | 120/120 | 114/120 | 57/120 |

Each reference solve supplies three native comparisons. Strict reference
admission requires `LOCALLY_SOLVED` or `OPTIMAL`; the reference's broader
`feasible` flag is insufficient. Every admitted row also requires independent
physical checks, reference-point membership in full and candidate native models,
native own/full membership, reverse membership of the first native anchor,
objective agreement, winding-current agreement, JSON round trip and the
tightened-cap rejection check where applicable.

The two baseline objective discrepancies are reverse-flow YDY cases: positive
roll with a cap at 1 kVA, and negative roll without a cap at 100 kVA. Their
maximum objective gap is approximately ``5.55\times10^{-6}`` currency/h.
All three native lifting modes fail the comparison gate for each case, while
their native solves and physical checks pass. These rows are not admitted by
loosening the comparison threshold.

Under additional absolute tolerances, the 21 non-strict reference statuses are
12 `SLOW_PROGRESS`, six `ALMOST_LOCALLY_SOLVED`, one `LOCALLY_INFEASIBLE`, one
`OTHER_ERROR` and one `ITERATION_LIMIT`. All 80 reference endpoints across both
panels pass the independent physical audit and native full-model membership;
all 240 candidate mappings also pass. The largest objective gap in the tighter
panel is approximately 0.170 currency/h, so physical feasibility cannot justify
reclassifying these outcomes as economic or solver agreement.

All 120 bounded native cases reject the recovered point after a separate input
copy tightens winding 2 from 300 to 270 VA, using both compiled-model and physical
audits. The unbounded cases do not contribute rejection certificates. The native
test suite independently exercises 120 solves and **2,700 assertions** covering
incidence-based export reconstruction, signed flow, both bases, all lifting
choices, matching objectives and unchanged input records.

## Independent SI audit

An independent Python reader audits all 80 reference and 240 native exports,
including rejected comparison rows. It forms coil voltages directly from bus
phasors and the declared winding orientation. With nominal ratios ``N_k``, it
checks

```math
\sum_k N_kj_k=0,\qquad
u_1-u_i/N_i+\sum_{k=2}^3 Z_{i-1,k-1}N_kj_k=0.
```

It constructs the leakage matrix from the declared resistances and pairwise
reactances, independently of either implementation's transformer helper. Coil
incidence supplies terminal currents for KCL; ideally grounded terminals are
excluded from the KCL equations, consistent with their possible earth current.
The audit also checks source phasors, load powers, generator boxes, fixed Q,
cost reconstruction and all 480 available coil-cap observations. It evaluates
2,752 ungrounded nodal balances. Maximum discrepancies are approximately
``2.81\times10^{-10}`` V for leakage, ``2.80\times10^{-10}`` A for ampere-turn
balance and ``1.45\times10^{-8}`` A for KCL.

The largest difference between exported winding apparent power and an SI phasor
product is ``2.12\times10^{-6}`` VA, below the existing independent physical
power tolerance of ``10^{-3}`` VA. Native output structures match across lifting,
base and stopping choices within each physical case. All 240 native exports
round-trip through BMOPFTools' JSON reader. These tests establish the declared
fixture's observable correspondence; they do not prove full device-law or
global-optimum equivalence.

## Reproduction and remaining scope

```sh
julia --project=test test/ivr_nwinding_connection_tests.jl
julia --project=test/integration test/integration/ivr_nwinding_connections_reference.jl /tmp/connections.json
```

The live runner writes all outcomes and SI exports beside the report. A successful
process exit means measurement completed; inspect each `accepted` flag and the
separate reference statuses before making a parity claim. The original all-wye
integration test remains available unchanged.

Non-unit tap fields, explicit excitation placement and four-winding non-star
leakage remain outside this new live panel. The inspected reference code rejects
multiwinding tap fields. Its legacy no-load fields place per-coil excitation on
winding 2, whereas the native legacy convention uses winding 1 and divides by
coil count. These conventions must be aligned explicitly in a future comparison;
identical field names are not enough. Do not reinterpret a native field silently
to manufacture agreement.

The results support further investigation of multiplier scaling and redundant
constraints before adopting tighter absolute tolerances broadly. Solver traces
should distinguish physical feasibility, stationarity, complementarity and
objective agreement. No timing, package-equation or default change follows.
Protocols, original/revised diagnostic stages, source snapshots and numerical
evidence remain outside Git in `NWINDING_CONNECTIONS_20261006`.

The subsequent [fixed-Q equality and excitation study](ivr_nwinding_equalities.md)
reproduces these controls, tests an exact constraint intervention and extends
live correspondence using explicitly located winding shunts. Its new results
do not replace the original outcomes above.
