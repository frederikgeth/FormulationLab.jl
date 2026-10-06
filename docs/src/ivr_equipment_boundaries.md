# Export dispatch at inherited transformer limits

The [single-phase voltage-bound study](ivr_singlephase_transfer.md) established
strict agreement near added voltage limits, but its original equipment ratings
were inactive. This extension approaches the inherited transformer rating by
changing declared DER capacity and the power objective. It preserves every
original feeder field, including line-current and transformer limits.

## Physical intervention and domain qualification

Reuse the original 70-bus `DSuite_SPM_Rural` feeder and the same 35 selected LV
sites. Multiply only the added DER active/reactive boxes, apparent-power and
current limits, and IBR DC capability limits by ten. Original loads, the 10%
parallel voltage-dependent demand, filter impedances and shunts remain unchanged.
This is `dispatch_scale=10`; it is a physical capacity change, not numerical
power-base scaling. The default one preserves the preceding study.

The original delta-wye transformer remains 11 kV/415 V and 200 kVA. The
BMOPFTools policy applies 200/3 kVA to each LV phase port. Original 600 A line
ratings remain unchanged. The quadratic cost retains the preceding weights.
Source-exchange tracking requests **−300 kW**, fixed before feeder solves as
negative 1.5 times the original transformer rating, together with zero var and
the existing DER tracking terms. Negative exchange denotes export. An
unattainable target is a soft objective request, not a feasibility equality.
DER active-power tracking targets follow the midpoints of the enlarged boxes;
their reactive-power targets remain zero. Thus this extension does not isolate
DER capacity from the dispatch-tracking targets.

Initially declare two voltage policies: the previous 200–260 V band, and
`:inherited`, which adds no voltage bounds. A manufactured test then exposes a
domain requirement: these non-polynomial load laws need a positive lower bound
on their coil voltage or a fixed nonzero source phasor. The original feeder
provides neither at the selected loads. Retain that refusal; do not weaken the
compiler's domain check. Before any feeder solve, add a third, explicitly
sequential policy, `:positive_floor`: a missing 1 V lower bound and no added
upper bound. Existing voltage-bound fields remain unchanged under every policy.

The 1 V floor certifies the load-law domain. It is not a recommended operating
voltage or an assertion that arbitrarily low voltage is acceptable in practice.
Its activity must be checked independently. The resulting scenario is a
numerical research case whose physically meaningful equipment limits are still
those of the original input.

## Matched numerical panel and results

Keep the same nine arms: full powers, reduced powers and reduced generator
reuse, each with uniform 1 kVA/off-row, nominal-column/off-row, or
nominal-column/law-row load scaling. All models use per-unit coordinates and
exact load-power lifting. Assembly and generator units remain 10 kVA; other
power lifts remain 1 kVA. Cross both power objectives and both Ipopt scaling
policies, using unchanged strict solver, common-start, original-model,
independent SI and objective gates. No formulation or scaling option is removed.

All **72 supported admissions** pass. The **36 inherited-only combinations**
are refused for the expected voltage-law domain reason, before optimization;
these are applicability refusals, not solver-convergence failures. They remain
in the raw panel. Every accepted endpoint has an SI JSON export and reader
round trip, with matching physical and native-device output structures.

| Voltage scenario | Objective | Source active power (kW) | LV voltage range (V) | Active nameplate caps | Active added voltage bounds |
|:--|:--|--:|:--|--:|--:|
| wide | quadratic_cost | -81.389 | 242.598–251.152 | 0 | 0 |
| wide | exchange_tracking | -198.948 | 244.011–260.000 | 3 | 5 |
| positive_floor | quadratic_cost | -81.389 | 242.598–251.152 | 0 | 0 |
| positive_floor | exchange_tracking | -198.947 | 243.997–268.471 | 3 | 0 |

The table combines all nine formulations and both policies within each row.
Reported source active powers agree within 1e-5 kW; voltage ranges span the
selected buses and all accepted endpoints. Every tracking endpoint reaches all
three inherited transformer caps. Wide-band tracking additionally reaches five
upper-voltage limits. The positive-floor scenario isolates active transformer
nameplates from added voltage activity: its floor is over 242 V below the
smallest recovered coil voltage. No inherited line-current limit is active;
the smallest remaining margin exceeds 325 A.

An independent Python audit reconstructs objectives and filter losses from SI
exports and checks 29,376 line-current margins and 216 nameplate margins.
Maximum objective error is below 1.28e-11; maximum filter-loss error is below
6.37e-12 W. Each of the 72 accepted endpoints is rejected by both the model and
the independent physical auditor after a separately copied transformer rating
is tightened below its recovered loading. These rejection witnesses change
neither the admitted input nor the original source.

Four additional full/reduced export solves, across both Ipopt policies, test
the recovered positive-floor point against the wide-band model and against a
separately tightened line-current cap. Both the model and independent physical
auditor reject all eight altered-input witnesses. The recovered maximum voltage
is approximately 268.47 V, so restoring the 260 V bound must change feasibility.

This establishes strict primal agreement at inherited nameplate boundaries
for the declared panel. It does not establish multiplier accuracy, uniqueness,
global optimality, active line-limit coverage or a speed advantage. In particular,
Ipopt timings obtained during concurrent correctness work are not ranked.

## Reproduction and next tests

```julia
include("examples/benchmark_ivr_singlephase_transfer.jl")
S = IVRSinglePhaseTransferStudy
net, additions = S.scenario(original;
    voltage_band=:positive_floor,dispatch_scale=10.)
profiles = S.profiles(net,:exchange_tracking;
    exchange_target_W=-300_000.,nlp_scaling_method="gradient-based")
```

Save the original input and exact addition manifest. `dispatch_scale` must be
representable as a finite positive `Float64`; overflowing added limits are
refused. Conversion precedes multiplication to prevent machine-integer rating
overflow. It scales only newly
created DER capability fields. Filter physics, original records, parallel demand
and numerical units stay fixed. The `:inherited` option remains available when
the supplied network already provides adequate voltage-domain bounds.

The external `EQUIPMENT_BOUNDARY_20261006` archive retains initial and extended
protocols, the initial domain-refusal test log, all 108 applicability outcomes,
exports and independent audits. Remaining priorities are isolated Ipopt-wall
comparisons and a separate workload that activates inherited line-current
ratings. Transformer activity is not evidence of line-limit activity.
