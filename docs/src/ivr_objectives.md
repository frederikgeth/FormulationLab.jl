# Objectives expressed in physical power

## Existing evidence and the expanded contract

Earlier transformer, grounding and power-base timing studies used
`objective=:source_import`: minimize the **signed** sum of voltage-source active
powers. Export has negative cost in that objective; it is not a positive-part
import tariff or loss minimization when generation can change. Earlier external
feeder studies often used `:feasibility`. The regression suite also exercised
linear `:cost`, price updates, negative generation prices and IBR availability.
Those studies do not establish performance under quadratic dispatch costs or
reactive-power tracking.

`objective=:power` adds explicit affine/quadratic objectives in physical power
channels. The existing three modes remain unchanged:

| Mode | Physical expression | Reported objective units |
|---|---|---|
| `:feasibility` | Zero | Dimensionless |
| `:source_import` | Sum of source active powers | W |
| `:cost` | Sum of source, generator and IBR active powers times linear energy prices, divided by 1000 | Currency/h |
| `:power` | Sum of explicitly supplied `IVRPowerTerm` expressions | User-defined by coefficients |

Legacy cost includes each device's native connection channels, with the existing
`cost` / `energy_cost_rate` alias rules. A snapshot cost has no time integration.
`:power` replaces that objective; it does **not** silently add legacy prices.

## Definition and units

For a term \(t\), choose active power \(P\) or reactive power \(Q\), a channel
list \(C_t\), weights \(w_{tk}\), target \(r_t\), and coefficients \(a_t,b_t\):

```math
x_t=\sum_{k\in C_t}w_{tk}X_k-r_t,\qquad
F=\sum_t(a_tx_t+b_tx_t^2),\qquad b_t\ge0.
```

Here \(X_k\) is in W for `quantity=:p` or var for `quantity=:q`. Targets have
the same units as their weighted sums. The coefficients must make the terms
dimensionally compatible. A quadratic price stated per kW squared therefore
needs a factor of \(10^{-6}\) when supplied as a coefficient on W squared.
The target offset remains part of the reported objective, including in affine
terms. Squaring an aggregate is different from summing individual squares; the
API preserves the distinction. P and Q are selected separately per term.

Each channel is `(family, id, index)`, with a **one-based native power-channel
index**, as in `result.powers[(family,id)][index]`. Generator delta indices are
coils. THREE_LEG IBR terminal powers use their existing conductor convention;
`:ibr_internal` uses the modeled internal winding/filter channels. Source and
line indices follow their declared terminal maps. Transformer IDs include their
kind, for example `"delta_wye/downstream1"`. Inspect `build.powers` for available
families and channel counts; a finite-ground shunt stamped directly in KCL need
not have a separate entry there. Unknown families, IDs, out-of-range indices,
empty/mismatched channel lists, nonfinite data and negative quadratic
coefficients are refused. Duplicate channels are summed with their supplied
weights. Supplying `power_terms` in another objective mode is refused.

```julia
terms = [
    # Generation cost: 0.10 currency/kWh plus 0.02 currency/(kW² h).
    IVRPowerTerm(channels=[(:generator,"g",1)],
        linear=0.10/1000, quadratic=0.02/1e6),
    # Total source reactive exchange tracking; weight chosen by the user.
    IVRPowerTerm(channels=[(:voltage_source,"grid",k) for k in 1:3],
        quantity=:q, target=0., quadratic=1e-6),
]
formulation = IVRNLP(objective=:power, power_terms=terms, objective_scale=1.)
```

The example's two terms are an explicit weighted trade-off; its reactive penalty
is not an energy price inferred by the package. Nonnegative quadratic coefficients
do not make the AC OPF convex. No global certificate follows from local Ipopt
acceptance.

## Scaling, exact reformulations and reuse

The solver minimizes \(F/d\), where `d=objective_scale` or, if omitted,
`d=s_base`. The same positive scalar is reversed during solve extraction and
supplied-point evaluation. Changing \(d\) preserves mathematical minimizers,
but may change numerical stopping behavior. Fix it when comparing electrical
power bases for a given objective; do not equate different objectives' values
or choose a normalization by comparing their timings directly.

The compiler reconstructs physical power as \(S_{\mathrm{SI}}=S_bS_{\mathrm{pu}}\)
through the existing inverse coordinate maps. Generator terms use the existing
explicit dispatch P/Q variables. Other selected ports use their exact power
expressions. With lifting off, squared power can be quartic in phasor variables.
With `lifting=:powers` or `:bounded_observations`, selected non-generator powers
use the existing exact P/Q definitions and caches. Objective lifts participate
in start encoding and supplied-point validation. This is an exact graph
extension, not a relaxation, and can increase rather than decrease solver time.

The build owns a deep copy of term lists, channel lists and weights. Supported
load and generator-bound updates preserve the objective definition. A `cost`
update changes only legacy `:cost`; it does not rewrite a custom power term.
Targets, weights and coefficients are fixed for the build: rebuild to change
them through this API. Direct mutation of `build.options` is unsupported.
In particular, an affine curtailment term `available - P` does not automatically
change its declared availability when a dispatch bound changes, and it is not
the nonsmooth expression `max(available-P,0)`.

SI JSON output keeps the same physical variables and recovery rules. Under
`:power`, `_formulationlab.objective_units` is `"user_defined"`, and
`objective_definition` records the physical terms in the solve snapshot. User
coefficients determine whether the result represents currency/h, W, a normalized
tracking penalty, or another compatible measure. The network hash alone cannot
identify a custom objective; retain this definition alongside the input.

## Six motivating workloads

`examples/benchmark_ivr_power_objectives.jl` supplies these cases on the
manufactured unbalanced transformer-leakage network:

| Workload | Objective | Purpose |
|---|---|---|
| `:linear_cost` | Source and generator linear prices | Economic dispatch under the legacy contract |
| `:quadratic_cost` | Source linear price plus generator linear/quadratic prices | Marginal-cost dispatch |
| `:dispatch_tracking` | Individual P/Q target errors | Controllable generator setpoints |
| `:exchange_tracking` | Aggregate source P/Q errors plus weaker individual dispatch penalties | Grid-interface exchange control |
| `:curtailment` | Sum of available-minus-generated active power, plus Q penalties | Generation utilization with reactive effort |
| `:losses` | Source plus generator P minus load P | Total passive-network active losses |

All cases permit bounded generator Q and retain original voltage, current and
capability limits. The loss-only case additionally caps each generator at 70%
of its colocated load so that local supply cannot trivially eliminate every
feeder current. This declared input change is specific to that workload; rankings
are always within one workload. The balance loss expression includes line,
transformer and finite-ground dissipation on this passive circuit. For a circuit
with converters or additional devices, include every relevant port with its
documented sign and distinguish converter losses from network losses. Do not
infer a general loss expression from an incomplete source-minus-load sum.

Six retained candidates combine common 1/10 kVA and regional current bases with
full IVR or conductor/passive-block/transformer-current reductions and optional
power/observation lifting. They are formulation bundles: differences do not
isolate the causal effect of a single option. The runner checks the entire power
objective definition before comparing candidates, not merely the `:power` label.
See the [executable tutorial](tutorial_exact_ivr.md) and
[verification record](verification.md) for analytic and physical checks.

## Confirmed workload comparison — 5 October 2026

The six workloads each receive six excluded warm-ups followed by twelve balanced
rotated/reversed sweeps, with every candidate appearing twice in every position.
A fresh process repeats the complete panel; results are not pooled. All
**864 measured solves and 72 warm-ups** pass original SI feasibility, own/full
model checks, reverse-anchor membership and physical-objective agreement. For
custom objectives, recomputation from recovered SI powers agrees with the
reported objective within 1.7e-9 in the declared objective units. Maximum
within-workload disagreement is below 1.2e-11. These tiny differences are numerical
agreement, not proof of global AC optimality.

Settings are MUMPS AMD, one Julia thread, one BLAS thread, explicitly disabled
Ipopt automatic NLP scaling, strict tolerance 1e-10 and the shared unloaded SI
start. Electrical coordinates are per unit. The objective divisor is 1 for
costs/tracking/curtailment and 10,000 for losses, fixed across formulations within
each workload. Tests, diagnostics and documentation builds never overlap timing.
Only Ipopt wall time ranks candidates; compilation, extraction and audits are
excluded. The raw environment and all solver options are recorded in JSON.

Confirmation median Ipopt wall time, milliseconds:

| Workload | Full 10 kVA | Full 1 kVA | Full regional | Reduced 10 kVA | Reduced 1 kVA + powers | Reduced regional + observations |
|---|---:|---:|---:|---:|---:|---:|
| `linear_cost` | 11.591 | 11.882 | 11.498 | 10.676 | 10.503 | 9.382 |
| `quadratic_cost` | 10.220 | 10.893 | 10.058 | 9.384 | 9.948 | 8.484 |
| `dispatch_tracking` | 10.772 | 10.862 | 9.428 | 9.933 | 9.912 | 9.615 |
| `exchange_tracking` | 8.922 | 8.394 | 9.098 | 8.388 | 7.706 | 8.391 |
| `curtailment` | 9.200 | 9.270 | 9.085 | 7.181 | 8.206 | 7.496 |
| `losses` | 9.042 | 9.733 | 8.925 | 8.281 | 8.910 | 7.218 |

Relative to full 10 kVA, the fastest bundle improves linear cost by **19.1%**,
quadratic cost by **17.0%**, individual dispatch tracking by **12.5%**, aggregate
exchange tracking by **13.6%**, curtailment by **21.9%**, and losses by **20.2%**.
The winner depends on the workload: reduced regional with observation lifting
for cost and losses; full regional for individual tracking; reduced 1 kVA with
power lifting for exchange tracking; reduced 10 kVA without lifting for
curtailment. In particular, source-import scaling results cannot select the
fastest economic-dispatch formulation automatically.

The three full candidates have 486 real variables and reduced 10 kVA has 116.
Power lifting gives 128–146 variables and observation lifting gives 320–338,
depending on the selected objective ports. More reduction does not always win:
full regional is fastest for individual tracking, while the larger observation
lift beats the 116-variable reduction on cost. Iterations alone also mis-rank
these candidates: the winning linear-cost observation lift takes 18 iterations
versus 16 for full 10 kVA. These are measured bundle effects; no individual
scaling/lifting mechanism or KKT-factorization cause is established.

All tails remain. Exchange-tracking winner/baseline paired timing ratios range
from 0.490 to 1.545 despite unchanged per-profile iteration counts; no cause is
assigned and neither extreme is presented as representative. All twelve paired
ratios for the other workload winners are below 0.923. No default is promoted
from this manufactured single-network panel or single automatic-scaling policy.

Reproduce with `IVRPowerObjectiveStudy.benchmark`. Protocol, frozen code/input,
raw trials, confirmation, objective audits and validation logs are retained
outside Git in `POWER_OBJECTIVES_20261005`. An export-only correction found after
these timings fixes explicit objective normalization for **unaccepted diagnostic
primals**. Every timed solve was accepted, so that branch was never used by the
campaigns. Final regression tests cover both paths.

## Matched formulation factors

The earlier six-profile comparison changes several options together. To separate
their effects, `examples/benchmark_ivr_objective_factors.jl` crosses regional
current units, passive-block elimination, transformer-current elimination and
three lifting policies. These give 24 candidates for each of quadratic cost and
exchange tracking, under both `none` and `gradient-based` Ipopt scaling.

All candidates use the same 12-section unbalanced leakage circuit, physical
objective, unloaded physical start, 10 kVA assembly base and objective divisor 1.
Conductor-region specialization, nominal transformer voltage coordinates,
composed row normalization, voltage-ground scaling and exact observation sharing
are fixed. The regional-current arm seeds source/MV/LV current-unit power bases
at 1 MVA/100 kVA/1 kVA; it does not change generator or lifted-power units.
The common 1 kVA assembly candidate from the earlier experiment is absent here.
Thus this study isolates the regional-current intervention at 10 kVA; it does
not select the best assembly base or supersede the earlier 1 kVA exchange result.

Each process excludes one warm-up per candidate and measures eight sweeps per
workload/policy cell. Four seeded random permutations are each followed by their
reverse. Every candidate has mean position 12.5 in each two-sweep block, but does
not occupy every position: this is not a fully position-balanced design. Realized
orders are saved. Exploration and a fresh-process confirmation together admit
**1536 measured solves and 192 warm-ups**, with no relaxed retries or removed
tails. Timings use one Julia/BLAS thread, MUMPS AMD and tolerance 1e-10. Compilation,
extraction and audits are excluded; timing batches do not overlap tests,
documentation builds or diagnostics. Physical objective discrepancies are below
1.30e-12, and within-cell objective spreads below 1.82e-9. Acceptance also requires
SI physics, original bounds, full-model membership and reverse representability;
it does not certify a global AC optimum.

For a matched pair, define the same-sweep ratio
\(r_k=t_{\mathrm{on},k}/t_{\mathrm{off},k}\). Its median over eight sweeps is
computed separately for every setting of the remaining factors. The table gives
the **range of these context-specific medians** in confirmation; values below 1
favor the added option. Binary factors have 12 matched contexts, lifting contrasts
have eight. These are descriptive paired measurements, not confidence intervals;
repeated solves and reversal blocks are not independent network samples.

| Change | Quadratic, none | Quadratic, gradient | Exchange, none | Exchange, gradient |
|:--|--:|--:|--:|--:|
| Regional current units | 0.980–1.029 | 0.974–1.021 | 0.992–1.025 | 0.997–1.075 |
| Passive-block elimination | 0.722–0.951 | 0.723–0.958 | 0.726–0.956 | 0.729–0.952 |
| Transformer-current elimination | 0.971–1.011 | 0.975–1.013 | 0.945–0.996 | 0.940–1.001 |
| Power lifting versus off | 0.974–1.015 | 0.965–1.007 | 0.973–1.009 | 0.928–1.016 |
| Observation lifting versus off | 0.877–1.153 | 0.887–1.154 | 0.984–1.299 | 0.992–1.312 |
| Observation versus power lifting | 0.884–1.155 | 0.887–1.163 | 1.007–1.317 | 1.013–1.389 |

Passive-block elimination improves all 12 contexts in every cell, in both
processes. Regional current scaling offers little consistent benefit here;
transformer-current elimination has a smaller effect, most favorable on exchange
tracking. Lifting interacts strongly with the reductions. With common current
units and transformer-current elimination, observation lifting changes quadratic
time by factors 1.133/1.146 without passive blocks and 0.877/0.887 with them
(`none`/`gradient-based`). An aggregate average would conceal this reversal.
For exchange tracking, observation lifting is slower than power lifting in every
matched context under both policies, although the closest differences are small.

The smallest confirmation medians among these 24 candidates are common-current
passive-block plus transformer-current elimination, with observation lifting for
quadratic cost (8.295/8.377 ms) and power lifting for exchange (8.229/8.313 ms).
Exploration selected the same profiles. However, the nearest competitors differ
by only 0.9–1.4% for cost and 0.4–0.8% for exchange; these fine rankings should not
be treated as robust preferences. The stronger evidence concerns passive blocks
and context-dependent lifting, not a universal winning profile. No native
factorization mechanism is established by these wall-time comparisons.

The next transfer experiment needs external feeders with controllable dispatch.
A read-only inventory found no generators or IBRs in the DSuite 265/1220-bus or
French 529-bus inputs inspected. Their fixed-load operation cannot establish
economic dispatch performance. An augmented LV input has bounded generators;
larger cases need an explicitly documented derived scenario. Preserve source
hashes and physical limits, and validate the declared objectives before timing.
All earlier formulation options remain available. See
[tutorial section 34](tutorial_exact_ivr.md) for a matched comparison.

## External LV dispatch transfer

The next panel uses `BMOPFDraftData/output/LV/augmented/LV1_14bus_augmented.json`
(source SHA-256 `37b42fa0c761e2c7279ab9b4a836787051ab6582baafdab1529afebf6232f2a7`).
Despite its filename, the supplied, previously simplified network has seven
buses. It has two single-phase loads totaling 20 kW and 10 kvar, three generators
with five bounded P/Q channels, one delta–wye transformer with leakage, finite
neutral grounds, line charging and negative-sequence voltage limits. All physical
fields and limits are retained. Known legacy provenance is relocated on an owned
copy and saved, not erased. This tests the supplied BMOPF dictionary; it is neither
a schema-validation nor an original pre-simplification-network certificate.

`examples/benchmark_ivr_external_objectives.jl` declares two objectives independent
of the input's legacy prices. With source aggregate powers and generator native
channel powers in **kW/kvar**, the illustrative economic objective is

```math
F_{\mathrm{cost}}=0.25P_s+\sum_g(0.10P_g+0.02P_g^2+0.002Q_g^2).
```

Its coefficients carry the corresponding currency/h units. The tracking objective
is \((P_s-10)^2+Q_s^2+0.01\sum_g[(P_g-m_g)^2+Q_g^2]\), with \(m_g\) the midpoint
of each original active-power box in kW. Coefficients are converted to W/var in
`IVRPowerTerm`; the physical objective divisor remains 1 at every electrical
base. The targets/prices are benchmark declarations, not market estimates. The
battery-named generator remains static bounded dispatch without energy coupling.

The input yields substantial capacitive source exchange. In the full-reference
preflight, economic dispatch gives approximately 2.056 kW and −82.807 kvar source
exchange. Tracking gives 11.569 kW and −74.883 kvar: all five generator Q lower
bounds are active, so Q=0 is not attained. Three P channels approach their lower
bounds and one approaches its upper bound. These observed constraints make a
useful stress test, but no claim of typical LV operation follows. Charging and
bounds were not edited to improve target achievement or numerical behavior.

The six profiles keep nominal transformer voltage coordinates, composed rows,
voltage-ground scaling and an unloaded physical start fixed. Reduced bundles
combine conductor regions, passive blocks, transformer-current elimination and
exact sharing. The common 1 kVA candidate differs from common 10 kVA power lifting
only in assembly base. Regional observation lifting uses assembly 10 kVA with
explicit source/LV current-unit powers of 100/1 kVA; its common-current comparator
uses the same observation policy. Thus the lifting and unit comparisons are
matched interventions, while full versus reduced remains a bundle comparison.

Each process crosses both workloads with `none` and `gradient-based` Ipopt
scaling, excluding six warm-ups per cell and measuring twelve sweeps. Every
candidate occupies each position twice. Exploration and fresh-process confirmation
admit all **576 measured solves and 48 warm-ups**. Settings remain one Julia/BLAS
thread, MUMPS AMD and tolerance 1e-10. No timing overlaps tests, documentation or
diagnostics; compilation, extraction and audits are excluded. Original SI bounds,
physical objective evaluation, full/reverse point maps, unchanged source/input
hashes and actual order balance pass. Maximum physical objective discrepancy is
below 2.73e-12 and within-cell spread below 1.46e-9. There is no global AC certificate.

Confirmation median **Ipopt milliseconds**:

| Workload | Ipopt scaling | Full 10k | Reduced 10k | Reduced 10k powers | Reduced 10k observations | Reduced 1k powers | Regional observations |
|:--|:--|--:|--:|--:|--:|--:|--:|
| quadratic_cost | none | 4.218 | 5.672 | 5.695 | 4.655 | 6.175 | 4.748 |
| quadratic_cost | gradient-based | 4.116 | 5.854 | 6.120 | 4.468 | 6.627 | 4.507 |
| exchange_tracking | none | 5.068 | 6.984 | 6.949 | 5.393 | 7.072 | 5.462 |
| exchange_tracking | gradient-based | 5.129 | 7.374 | 7.308 | 5.465 | 7.810 | 5.471 |

Full IVR wins every cell in both processes. In confirmation, the reduced unlifted
bundle is 34–44% slower despite shrinking from 136 to 114 real variables, with
the same iteration counts: nine for cost and thirteen for exchange. The bundle
eliminates eight complex passive-block coordinates and three transformer currents;
this is a real structural intervention, not a fallback/no-op. It does not isolate
which reduction causes the regression, nor establish a native factorization
mechanism.

Observation lifting increases the reduced model to 290 variables but improves
its matched same-sweep median ratios to 0.826/0.766 for cost and 0.774/0.743 for
exchange (`none`/`gradient-based`). It remains 6–10% slower than full by ratios of
profile medians. Common 1 kVA power lifting is slower than its 10 kVA counterpart
in all four cells; regional current units offer no consistent benefit. This
external exchange result reverses the manufactured panel's observation-versus-power
lifting preference. Topology, charging, bound observations and operating point
therefore remain necessary transfer dimensions.

Slow trials are retained. For example, cost/no-scaling reduced/full paired ratios
range from 0.454 to 1.387 because of a slow full trial; exchange/gradient power-lifted
reduced/full ranges from 1.391 to 3.069. Do not replace the median comparison with
a favorable tail, pool processes, or treat repeated solves as independent feeder
samples. This is one small inherited external network, not validation at scale.

All 24 untimed preflight solutions have BMOPFTools-style physical SI JSON exports
with identical physical quantity keys across formulations and passing round trips.
Exactly recovered input-network quantities are preserved; unobservable ideal
source neutral current retains the established NaN convention. Recovering buses
removed by earlier preprocessing remains separate work. See
[tutorial section 35](tutorial_exact_ivr.md) for explicit external experiment setup.
Larger MV/LV cases with declared DER dispatch, broader objective cases and regional
generator/lifted-power units remain next; all earlier alternatives are retained.

## Derived DER transfer on 265 buses

The next panel uses DSuite's 265-bus suburban feeder as a physical network
(source SHA-256 `bcd85940fcc020fc3448797d78576c9c7014777cca19e2e3aa778f606c8f4366`).
Its 119 loads include 74 positive single-phase loads of 1 kW each and 45 zero-load
records; aggregate demand is 74 kW and zero kvar. It has 264 lines, one delta–wye
transformer with leakage, and no generator or IBR dispatch. Existing line and
transformer ratings are retained. No bus-voltage magnitude bounds were supplied;
this panel does not invent them or establish voltage-constrained OPF performance.

`examples/ivr_der_scenario.jl` creates an **explicitly different dispatch
scenario**. For every positive constant-power load it adds a generator on the
same native bus and terminal map. Channel bounds are
\(0\le P_g\le1.5P_d\), \(|Q_g|\le0.5P_g^{\max}\) and
\(P_g^2+Q_g^2\le(P_g^{\max})^2\). This adds 74 single-phase devices with 111 kW
active capacity. All original fields are retained exactly. The source file is
unchanged; a separate input and manifest record every addition, source-load
association, capability and hash. These static capabilities are illustrative,
not inferred DER nameplates, storage models or an equivalence-preserving cleanup.

The same six profiles and objective coefficients from the preceding external
study are retained. Source-exchange tracking targets half the original demand,
37 kW, and zero kvar, with generator midpoint/Q-effort regularization. Regional
current-unit seeds are 100 kVA at `sourcebus` and 1 kVA at `9108515`; assembly base
is 10 kVA in that arm. The physical objective divisor is 1 throughout. Every
profile uses the same unloaded physical start, nominal transformer voltage
coordinates, composed rows, voltage-ground scaling, MUMPS AMD and tolerance
1e-10. Source cost is signed exchange, including export credit; legacy input
prices are not implicitly added.

Untimed preflight separates two operating regimes. Economic dispatch reaches all
74 added apparent-power circles (slack below 2.1e-7 VA in the full reference),
with approximately 111.000 kW total generation and −36.950 kW source exchange.
Tracking leaves every circle slack by more than 998 VA, with approximately
37.053 kW generation and 36.998 kW source exchange. Its source-target mismatch is
about −2.49 W and −0.0043 var, consistent with a soft penalized target. Tightening
one active DER circle by 1% rejects the cost endpoint in both independent SI
checks and encoded-model membership, under both solver policies.

Exploration and fresh-process confirmation admit **576 measured solves and 48
warm-ups**. Each of the four workload/solver-policy cells excludes six warm-ups
and measures twelve rotated/reversed sweeps, with every candidate occupying each
position twice. Both batches use one Julia/BLAS thread, exclude construction,
extraction and audits from ranking, and finish before full tests or documentation
builds. No retries with relaxed tolerances, deleted tails or pooled processes.
The audit verifies unchanged raw/scenario files, original-field preservation,
all 74 additions, actual orders, SI physics, original bounds, full/reverse maps and
physical objective equality. Maximum objective discrepancy is below 5.33e-15;
maximum within-cell objective spread is below 3.58e-13. Neither agreement nor
local solver status establishes a global AC optimum.

Confirmation median **Ipopt milliseconds**:

| Workload | Ipopt scaling | Full 10k | Reduced 10k | Reduced 10k powers | Reduced 10k observations | Reduced 1k powers | Regional observations |
|:--|:--|--:|--:|--:|--:|--:|--:|
| quadratic_cost | none | 49.029 | 45.949 | 43.988 | 45.022 | 40.078 | 45.066 |
| quadratic_cost | gradient-based | 49.695 | 46.477 | 44.479 | 45.505 | 40.539 | 45.684 |
| exchange_tracking | none | 25.164 | 23.588 | 23.648 | 24.282 | 25.954 | 24.182 |
| exchange_tracking | gradient-based | 25.349 | 23.796 | 23.668 | 24.372 | 26.385 | 24.338 |

Reduced 1 kVA power lifting wins economic dispatch in both batches and under both
policies: **18.3%/18.4%** less wall time than the full 10 kVA control in confirmation.
Full IVR has 3726 variables and takes 16 iterations; reduced unlifted has 2922 and
also takes 16; reduced power lifting has 3076 and takes 15 at 10 kVA or 14 at
1 kVA. Observation lifting has 3220 variables and takes 15. These counts describe
the formulations before solver preprocessing, not KKT fill or memory.

The matched 1 kVA/10 kVA power-lifted comparison has same-sweep median ratios
0.910/0.912 for cost but **1.101/1.113** for tracking. The lower base helps cost
and hurts tracking on the same physical scenario, with fixed objective divisor.
Tracking takes seven iterations at 10 kVA and eight at 1 kVA. Its best 10 kVA
reduced alternatives improve on full by about 6%; lifting off versus powers is
near a tie, with paired medians 1.000/0.993. Observation lifting slightly slows
tracking relative to reduced unlifted; regional current units remain near a tie.

The full-to-reduced comparison still changes a bundle of options. Full 1 kVA is
not in this shortlist, so the economic winner is best only among these six
candidates, not a proof that reduction beats every full formulation or that
1 kVA is universally preferable. Active-set changes accompany objective changes;
the experiment does not isolate either as the cause of the timing reversal.
Separate native traces would be required to explain factorization costs.

Retained tails qualify the median gains: cost/gradient reduced-1k/full paired
ratios span 0.520–1.046, and tracking/no-scaling observation/off spans
1.015–1.475. Do not present the fastest individual solve as the representative
benefit. Repetitions are timing observations on one derived feeder, not independent
network samples. Larger multi-transformer and voltage-constrained cases remain
open, alongside full-base controls and independent generator/lifted-power units.

All 24 untimed solution exports preserve matching physical SI quantity keys
across formulations and pass JSON round trips. Reconstruction applies to the
input scenario; earlier preprocessing and unobservable ideal-source currents
retain their existing limitations. The independent fixed-voltage regression
oracle predicts 3.75 kW generation and zero generator Q from these economic
coefficients; six profiles match it, and tighter capability bounds reject its
endpoint. Mixed single-phase/wye/delta tests include fixed-zero native channels.
See [tutorial section 36](tutorial_exact_ivr.md) for scenario creation and its
provenance contract. No existing transformation or default is removed.

## Matched full and reduced power bases

The preceding six-candidate study omitted full IVR at 1 kVA. To close that control
gap, `examples/benchmark_ivr_base_formulations.jl` crosses common assembly bases
1, 10 and 100 kVA, full/reduced representation, and power lifting off/on. These
12 profiles use the exact same derived 265-bus physical input, economic terms and
37 kW/zero-kvar tracking terms as the preceding study. Source, scenario and
addition-manifest hashes are retained; no generator, load or equipment bound changes.

The reduction switch jointly enables conductor regions, passive blocks and
transformer-current substitution. It remains a bundle; its internal contributions
are not separated. Exact observation sharing is fixed in every arm. Nominal
transformer voltage coordinates, voltage-ground scaling and composed linear rows
are also fixed policies; their numerical multipliers are recomputed at each base.
There are no regional-current seeds or bounded-observation lifts in this panel.
Changing the common base affects current and power-variable units together. The
physical objective divisor remains 1, so it does not change with electrical units.

The protocol crosses both objectives with explicit `none` and `gradient-based`
Ipopt scaling, using MUMPS AMD, tolerance 1e-10 and one Julia/BLAS thread. Each cell
excludes twelve warm-ups and measures twelve sweeps. A seeded random permutation
of candidate labels is cyclically rotated through all twelve offsets, and sweep
order is randomized. Every candidate occupies each position once. This is position
balance, not balance of every predecessor pair. Realized orders are saved; seeded
RNG behavior need not be identical across Julia versions. Repeated solves are
not independent network samples.

For matched comparisons, form same-sweep time ratios with one factor changed:
1/10 or 100/10 kVA at fixed reduction/lifting; reduced/full at fixed base/lifting;
and powers/off at fixed base/reduction. The primary score remains Ipopt wall time,
excluding compilation, extraction and audits. Fresh-process confirmation is kept
separate from exploration. Neither batch overlaps tests, documentation builds or
diagnostics; slow observations and failures remain part of the evidence.

All **1152 measured solves and 96 warm-ups** pass admission across exploration
and confirmation. Maximum physical objective discrepancy is below 5.33e-15 and
within-cell spread below 3.57e-13. All 48 separate preflight solves have matching
physical SI export keys and passing JSON round trips; original/scenario hashes
and the earlier 74-addition manifest remain unchanged. Two stricter-circle
witnesses reject cost endpoints in both independent SI and encoded-model checks.
These tests establish physical/representation agreement, not global AC optimality.

Confirmation median **Ipopt milliseconds**:

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_1k_off` | 42.696 | 42.611 | 27.905 | 28.033 |
| `full_1k_powers` | 43.123 | 42.971 | 28.032 | 28.178 |
| `reduced_1k_off` | 39.775 | 39.970 | 26.088 | 26.076 |
| `reduced_1k_powers` | 40.038 | 40.419 | 26.051 | 26.214 |
| `full_10k_off` | 49.338 | 49.371 | 25.047 | 25.147 |
| `full_10k_powers` | 47.099 | 47.209 | 25.064 | 25.175 |
| `reduced_10k_off` | 46.103 | 46.297 | 23.509 | 23.719 |
| `reduced_10k_powers` | 44.160 | 44.313 | 23.578 | 23.584 |
| `full_100k_off` | 57.357 | 57.661 | 24.905 | 33.924 |
| `full_100k_powers` | 57.841 | 58.056 | 24.878 | 33.781 |
| `reduced_100k_off` | 54.242 | 54.297 | 23.497 | 31.734 |
| `reduced_100k_powers` | 54.618 | 54.879 | 23.557 | 31.772 |

The full-base gap is now closed within this candidate set. Full unlifted 1 kVA
improves cost by **13.5%/13.7%** relative to full unlifted 10 kVA (`none`/`gradient`),
with 14 rather than 16 iterations. Reduced unlifted 1 kVA improves on that same
10 kVA full control by **19.4%/19.0%**, while taking the same 14 iterations as its
matched full 1 kVA counterpart. Thus part of the earlier bundled gain transfers
to full IVR, and reduction contributes a further benefit at matched units.
These percentages have different denominators and should not be added.

The matched reduced/full same-sweep median ratios range from **0.929 to 0.949**
across all six base/lifting contexts and all four workload/policy cells in
confirmation. Every context improves in both batches. This is evidence for a
roughly 5–7% reduction-bundle benefit on this scenario, not a statement that
reductions always help: the earlier seven-bus case remains a counterexample.
At fixed base/lifting, full and reduced models have equal iteration counts.
Their unlifted real variable counts are 3726 and 2922; no KKT fill/memory or
factorization-time mechanism is inferred from those counts.

The matched 1/10 kVA median ratios are 0.862–0.915 for cost but 1.102–1.118 for
tracking. Tracking takes eight iterations at 1 kVA and seven at 10 kVA. At
100 kVA it takes seven without automatic scaling but ten with gradient-based
scaling. Corresponding 100/10 kVA tracking median ratios are 0.990–1.002 without
scaling and **1.339–1.352** with gradient scaling. The automatic-scaling policy
therefore belongs in the declared numerical profile. This experiment does not
identify which native solver scaling or regularization step causes the change.

Power lifting benefits cost at 10 kVA by about 4–5% at matched representation,
reducing 16 iterations to 15 in full and reduced models. At 1 kVA both lifting
choices take 14 iterations and differ by about 1%; at 100 kVA both take 20.
Tracking lifting contrasts are near a tie. The smallest cost medians use reduced
1 kVA without lifting, but the adjacent power-lifted candidate remains in the
shortlist. For tracking, reduced 10 kVA with lifting off or powers is the supported
shortlist across both policies. The marginal 100 kVA/no-scaling differences are
not a reason to promote a configuration that regresses under gradient scaling.
All previous options and package defaults remain available and unchanged.

Every outlier is retained. For example, tracking/no-scaling reduced-100k-off versus
full-100k-off has a paired ratio as high as 4.113, despite its median below 1;
its ratio to the full-10k control reaches 6.138. Cost/gradient matched reduction
ratios include a 0.248 tail caused by a slow full-power-lifted observation. These
extremes are not representative gains or grounds for selectively rerunning trials.
The confirmation table is not pooled with exploration, and no significance or
population-generalization claim is made.

This closes the full-base control gap on one declared DER scenario. The following experiment holds circuit-current units fixed while varying
generator P/Q units. Lifted-power units remain a separate next intervention,
with the same physical objective divisor, bounds, starts, updates and recovery
checks. Common-base results alone cannot
assign the benefit to one variable family. Larger multi-transformer and explicitly
voltage-constrained cases remain open. See [tutorial section 37](tutorial_exact_ivr.md)
for the matched-base and ordering contract.


## Independent generator dispatch units — 6 October 2026

`generator_power_bases` separates explicit generator P/Q coordinates from the
assembly power base. Each declared generator uses ``P_g/S_g,Q_g/S_g`` on all
native channels; unspecified generators use ``S_b``. Circuit coordinates remain
fixed. Its defining equations retain assembly-power units with coefficient
``S_g/S_b`` on the dispatch variables. Boxes, objectives, price/bound updates and
SI point encoding use the corresponding inverse factors. Physical result powers
still come from voltage/current products. The [API contract](ivr_nlp.md) gives
the equations, guards and effective-base diagnostics. This experiment introduces
no generator auxiliary reuse, power lifting or row renormalization.

`examples/benchmark_ivr_generator_units.jl` holds the assembly base at 10 kVA,
nominal transformer voltage coordinates, composed linear rows, voltage-ground
scaling, exact sharing and physical objective divisor 1. Regional-current seeds
are empty and lifting is off. It crosses dispatch bases 1/10/100 kVA on all
74 generators with full/reduced representations. The reduction bundle is the
same as above. Thus within each representation, the only option that changes is
`generator_power_bases`. Both objectives, the 37 kW/0 kvar soft source target,
physical input, DER addition manifest and all original limits are unchanged.

Each of four objective/solver-policy cells excludes six warm-ups and measures
twelve sweeps: two randomized cyclic blocks, each placing every profile in each
position once. Realized orders and seed are saved. Position balance does not
balance every predecessor pair. One Julia/BLAS thread, MUMPS AMD, strict 1e-10
settings, explicit `none`/`gradient-based` policies, and a fresh-process complete
confirmation match the earlier protocol. No timing overlaps tests, documentation
builds or diagnostics. The score is Ipopt wall time; construction/extraction and
audits are excluded. Batches are not pooled and tails are retained.

All **576 measured solves and 48 warm-ups** pass physical, own-model,
full-model and reverse-anchor admission across both batches. Maximum discrepancy
between recovered-power and model objectives is below 4.45e-15; within-cell
objective spread is below 5.33e-15. All 24 separate preflight solves pass SI JSON
round trips with matching physical quantity keys. The original/scenario hashes,
74 DER additions and all physical fields are unchanged. Cost binds all 74
capability circles, while tracking leaves them slack. Two tightened-circle
witnesses reject independently and in encoded constraints.

Confirmation median **Ipopt milliseconds**:

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_dispatch_1k` | 44.528 | 44.358 | 27.453 | 30.180 |
| `reduced_dispatch_1k` | 41.345 | 41.273 | 25.705 | 28.151 |
| `full_dispatch_10k` | 49.577 | 49.700 | 25.317 | 25.284 |
| `reduced_dispatch_10k` | 46.730 | 46.671 | 23.782 | 23.931 |
| `full_dispatch_100k` | 43.499 | 43.655 | 25.365 | 27.994 |
| `reduced_dispatch_100k` | 40.598 | 40.478 | 23.762 | 26.265 |

Changing only dispatch units provides a cost benefit: matched same-sweep 1/10 kVA
median ratios are **0.887–0.893** across full/reduced and both scaling policies;
100/10 kVA ratios are **0.865–0.878**. Iteration counts change from 16 at 10 kVA
to 15 at 1 kVA and 14 at 100 kVA. Both directions improve in exploration too.
The response is therefore nonmonotonic over these three bases: it does not
support choosing a smaller base merely because LV power ratings are smaller.
The smallest cost medians in this panel are reduced 100 kVA dispatch at
40.598/40.478 ms, with the assembly base still 10 kVA.

Tracking differs. The 1/10 kVA ratios are **1.078–1.094** with no automatic
scaling and **1.176–1.199** with gradient scaling. Iterations increase from seven
to eight/nine, respectively. At 100 kVA, ratios are **1.001–1.004** without
automatic scaling (seven iterations) and **1.095–1.108** with gradient scaling
(eight iterations). The no-scaling 100 kVA contrast is practically a tie, with
sub-percent changes in both directions between batches. Keep 10 kVA dispatch
for the tracking shortlist across both policies. No native factorization,
regularization or automatic-scaling mechanism is identified by these data.

At matched dispatch units, the reduction bundle improves all three context
medians in all four cells in both batches; confirmation ratios span
**0.927–0.951**. No assertion is made that every trial improves. Retained tails
include reduced-100k cost/no-scaling versus full-10k at 1.102 and reduced-10k
tracking/gradient versus full-10k at 1.603, despite median improvements. The new
candidate belongs alongside the earlier common-1k cost candidates; it has not
been compared with them in the same timing block.


This is evidence on one declared 265-bus DER scenario, not a population estimate
or global optimality certificate. Common-base and dispatch-only experiments alter
different coordinate families. Cross-batch absolute timings cannot establish a
winner between the earlier common-1k profile and a new dispatch-only profile;
the following shared randomized panel supplies that comparison and extends
to lifted-power units, a larger multi-transformer feeder and a voltage-constrained
DER scenario. All previous transformations and defaults remain available. See
[tutorial section 38](tutorial_exact_ivr.md) for the executable matched control.


## Matched finalists and external transfer — 6 October 2026

This study develops four distinct questions: can power-lift units improve solving
without changing other units; which previous cost finalist wins when measured
in the same block; do results transfer to larger or voltage-constrained dispatch;
and can exact generator-definition reuse or less aggressive condensation help?
The new `lifted_power_base` and `power_sharing=:generators` controls are described
in the [coordinate contract](ivr_nlp.md). Defaults and all earlier options remain.

Ten candidates retain nominal transformer voltage coordinates, composed circuit
rows, voltage-ground scaling, exact affine sharing, a fixed physical objective
divisor 1, and no regional-current seeds:

- `full_10k`, `full_1k`, `reduced_10k`, `reduced_1k`: matched full/reduced common bases.
- `reduced_dispatch_100k`: assembly 10 kVA with only generator dispatch at 100 kVA.
- `reduced_lifts_1k`, `reduced_lifts_10k`, `reduced_lifts_100k`: power lifting on,
  assembly/dispatch fixed at 10 kVA, differing only in power-lift units.
- `reduced_reuse`: the 10 kVA power-lift control with exact generator P/Q reuse.
- `reduced_nonadjacent`: the reduced-10k unlifted control with nonadjacent passive
  elimination instead of passive blocks. This existing conservative option retains
  more interior coordinates; it is not a new bound on condensation block size.

The reduction bundle otherwise retains conductor regions and transformer-current
substitution. Lift-unit comparisons keep generator reuse off; reuse is measured
against its own matched lifted control. No joint tuning is inferred from them.

Three physical scenarios have distinct manifests. `BASE265` preserves the previous
265-bus network and its 74 DER additions. `VOLTAGE265` additionally imposes
216–242.5 V phase-neutral magnitude bounds on every phase at every original load
bus. These are declared experimental operating limits, not claimed statutory
limits or equivalent preprocessing. Existing fields are retained and every new
bound is recorded. Its cost solution activates one upper-voltage limit.
`URBAN1220` starts from the 1,220-bus DSuite urban source with four transformers,
adding 268 generators at positive load connections using the same DER construction
rule. Its positive demand is 268 kW, versus 74 kW on the smaller feeder. Raw source
files remain unchanged. Neither unmodified feeder had these newly added DERs.

Both objectives retain the preceding physical coefficients. Exchange tracking
uses a soft source target equal to half positive demand—37 kW or 134 kW—and zero
kvar, plus the same generator regularization. Comparisons are within a scenario
and objective. Every cell tests `none` and `gradient-based` Ipopt scaling under
MUMPS AMD, one Julia/BLAS thread and strict 1e-10 settings. Ten excluded warm-ups
precede ten randomized cyclic sweeps; each profile occupies every position once.
Realized orders are saved, without claiming predecessor balance or independent
network samples. Every case receives a complete fresh-process confirmation;
batches remain separate and all tails remain. Timing excludes construction,
extraction and audits and never overlaps tests/docs/diagnostics.

All **2400 measured solves and 240 warm-ups** pass admission, as do **120
separate preflight SI export round trips**. Physical quantity keys match across
formulations. Maximum recovered-power objective discrepancy is below 4.98e-14;
within-cell spread is below 3.57e-13. Input/source hashes, additions, actual power
bases, reuse counts, complete starts, objective correspondence and cyclic order
balance pass the independent evidence audit. Six stricter capability witnesses
and two stricter voltage witnesses reject independently and in encoded models.

The following tables give confirmation median **Ipopt milliseconds**. They are
separate from exploration; the two batches are not pooled.

### Unchanged 265-bus DER scenario

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 50.128 | 49.856 | 25.425 | 25.423 |
| `full_1k` | 43.357 | 43.278 | 28.505 | 28.401 |
| `reduced_10k` | 46.747 | 46.960 | 23.762 | 23.964 |
| `reduced_1k` | 40.493 | 40.580 | 26.382 | 26.487 |
| `reduced_dispatch_100k` | 40.880 | 40.772 | 23.886 | 26.329 |
| `reduced_lifts_1k` | 39.994 | 40.097 | 23.679 | 23.551 |
| `reduced_lifts_10k` | 44.515 | 44.618 | 23.754 | 23.875 |
| `reduced_lifts_100k` | 59.201 | 59.422 | 23.709 | 30.912 |
| `reduced_reuse` | 40.369 | 40.478 | 22.995 | 23.314 |
| `reduced_nonadjacent` | 49.090 | 49.167 | 24.875 | 24.867 |

### 265-bus scenario with added voltage limits

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 86.432 | 86.019 | 34.382 | 39.893 |
| `full_1k` | 88.420 | 87.789 | 40.074 | 40.052 |
| `reduced_10k` | 81.390 | 79.801 | 31.866 | 37.313 |
| `reduced_1k` | 83.510 | 82.049 | 37.452 | 37.264 |
| `reduced_dispatch_100k` | 79.954 | 80.011 | 36.902 | 42.573 |
| `reduced_lifts_1k` | 71.284 | 71.279 | 31.701 | 31.767 |
| `reduced_lifts_10k` | 78.784 | 78.122 | 31.922 | 37.045 |
| `reduced_lifts_100k` | 87.059 | 86.553 | 37.195 | 50.417 |
| `reduced_reuse` | 74.339 | 73.797 | 30.894 | 36.223 |
| `reduced_nonadjacent` | 84.131 | 84.718 | 33.445 | 38.968 |

### 1,220-bus DER scenario

| Profile | Cost, none | Cost, gradient | Tracking, none | Tracking, gradient |
|:--|--:|--:|--:|--:|
| `full_10k` | 251.207 | 258.124 | 118.672 | 133.570 |
| `full_1k` | 262.875 | 267.291 | 143.793 | 152.113 |
| `reduced_10k` | 244.221 | 248.469 | 113.778 | 125.835 |
| `reduced_1k` | 240.116 | 246.042 | 128.855 | 140.370 |
| `reduced_dispatch_100k` | 244.705 | 247.282 | 114.196 | 138.196 |
| `reduced_lifts_1k` | 229.506 | 234.031 | 114.226 | 114.975 |
| `reduced_lifts_10k` | 234.496 | 235.867 | 113.314 | 126.505 |
| `reduced_lifts_100k` | 290.516 | 293.830 | 112.483 | 161.204 |
| `reduced_reuse` | 246.889 | 252.657 | 109.586 | 122.983 |
| `reduced_nonadjacent` | 253.594 | 257.599 | 117.673 | 131.269 |

### What transfers, and what does not

**Lifted-power units:** reducing only the lift base from 10 to 1 kVA improves
cost in both batches. Confirmation paired median ratios are 0.898 on BASE265,
0.904/0.913 on VOLTAGE265 and 0.979/0.988 on URBAN1220 (`none`/`gradient`). The
larger-feeder separation is modest, with paired ranges crossing one and unchanged
17-iteration counts. BASE265 drops from 15 to 14 iterations; VOLTAGE265 from
26 to 24. Increasing lift units to 100 kVA regresses cost by roughly 11–33% and
increases iterations on all three cases. Those alternatives remain available.

Tracking is different. With no automatic scaling, 1 kVA lifts are near 10 kVA
on all three scenarios; some small differences change sign between batches.
Under gradient scaling, the matched ratios are 0.990 on BASE265, **0.857** on
VOLTAGE265 and **0.904** on URBAN1220. The latter two decrease iterations from
11 to 9 and 8 to 7. The 100 kVA lifts regress under gradient scaling by roughly
28–36%. No native factorization or conditioning mechanism is established.

**Exact generator reuse:** the 74 or 268 matched native powers remove 148 or
536 redundant real variables and their defining equalities relative to the
matched 10 kVA power-lift control. Every original capability limit remains.
Tracking improves in all six scenario/policy median comparisons in both batches;
confirmation paired ratios are **0.970–0.974**, without fewer iterations than the
matched control. Cost improves about 9% on BASE265 and 6% on VOLTAGE265, but
**regresses 6–7% on URBAN1220**, where iterations rise from 17 to 19. This is a
new counterexample to treating auxiliary reuse or smaller dimension as a
universal speed improvement.

**Matched old finalists:** common-1k versus assembly-10k/dispatch-100k is now
measured in the same block. Their cost medians are close on BASE265 and URBAN1220;
paired dispatch/common ratios are 1.012/1.001 and 1.014/1.004. Dispatch-only scaling
beats common-1k by about 2–3% on VOLTAGE265, yet both lose to the new 1k-lift
candidate. Full common-1k also loses to full-10k on the constrained and urban cost
cases, despite its earlier gain on BASE265. Scaling recommendations do not
transfer automatically between these operating problems.

**Conservative condensation:** nonadjacent passive elimination is **3.6–6.8%
slower** than the matched block control in confirmation, with the same direction
in every exploratory context. Retaining more interior states does not help these
three scenarios. This does not test every selective or bounded-size strategy;
the existing option remains as negative evidence and a future comparator.

### Revised shortlist and limits

For cost, `reduced_lifts_1k` has the smallest median in all three scenarios under
both policies and in both batches. Relative to full-10k, confirmation median gains
are **19.6–20.2%** on BASE265, **17.1–17.5%** on VOLTAGE265 and **8.6–9.3%** on
URBAN1220. These are bundle gains. The isolated lift-unit gain on URBAN1220 is
only 1–2%, and BASE265's leading alternatives are close; the table does not prove
a universal or statistically separated optimum.

For tracking without automatic scaling, `reduced_reuse` leads all three cases.
Under gradient scaling it leads BASE265, while `reduced_lifts_1k` leads VOLTAGE265
and URBAN1220. Retain both in the tracking shortlist and state the solver policy.
No package default is changed. This panel does not rank combinations of smaller
lift units with generator reuse or different generator dispatch units; the
subsequent [controlled interaction study](ivr_power_interactions.md) tests those
combinations explicitly.

All outliers remain, including a BASE265/no-scaling tracking 100k/10k-lift ratio
of 6.602, an urban cost/gradient nonadjacent/block ratio of 1.831, and an urban
tracking/gradient 1k/10k-lift ratio of 1.495 despite its favorable median. Conversely,
a slow voltage-case lifted control produces a cost 1k/10k ratio of 0.343; that
extreme is not the representative gain. These results do not promise faster
every-run performance or explain the tails' causes.


The smaller/larger and constrained/unconstrained scenarios expand the evidence;
they do not establish a universal default or a global AC optimum. The candidate
set is explicit and omits combined lift/dispatch tuning. The nonadjacent control
explores conservative condensation, while bounded-size hybrid blocks and
signed/proportional observation sharing remain separate implementation questions.
The supplied-point/physical tests preserve original bounds and native channel
semantics. See [tutorial section 39](tutorial_exact_ivr.md) and
`examples/benchmark_ivr_power_finalists.jl` for reproduction. Raw inputs, manifests,
source snapshots, all trials and SI exports remain outside Git.


## Independent economic-dispatch oracle

A fixed-voltage, two-generator circuit supplies 3000 W and 600 var, with source
P/Q fixed to zero. Its objective is

```math
F=0.001P_1+10^{-6}P_1^2+2\,10^{-6}P_2^2
  +10^{-6}Q_1^2+3\,10^{-6}Q_2^2.
```

On the original boxes, eliminating the affine balances gives
\(P_1=(4\,10^{-6}P_D-0.001)/(6\,10^{-6})\), \(P_2=P_D-P_1\),
\(Q_1=3Q_D/4\), \(Q_2=Q_D/4\). Hence the optimum is
\((1833.333\ldots,1166.666\ldots)\) W and \((450,150)\) var.
The reduced Hessian is positive, and the stationary point lies inside the boxes;
this simple oracle has a global certificate independent of Ipopt. A subsequent
1000 W cap on generator 1 binds; a later load update changes both balances.
The tests verify the resulting analytic dispatches and objectives over assembly
bases of 1 and 1000 kVA, two objective divisors and all three lifting modes.
These guarantees apply to this affine fixed-voltage case, not to the coupled
unbalanced AC benchmark.

The present objective contract covers sums of affine terms and nonnegative
squared weighted P sums or Q sums. Piecewise import/export tariffs, P–Q cross
terms in a single square, and intertemporal objectives require further API work.

## API

```@docs
IVRPowerTerm
```
