# Local reactive transfer at inherited line limits

The [transformer-boundary experiment](ivr_equipment_boundaries.md) reaches
inherited nameplate caps, but leaves at least 325.9 A of line-current slack.
Increasing aggregate export therefore does not provide an independent test of
active line limits. This experiment instead adds reactive dispatch at opposite
ends of one original line. It asks whether exact reductions preserve the
original feasible set and recover the same physical outputs at a current boundary.

## Declared intervention and objective

Reuse the 70-bus `DSuite_SPM_Rural` input. Before solving, select line `9244553`,
from bus `17582384` to `17582385`: the smallest length times first diagonal
impedance magnitude among its LV lines after excluding connector and busbar
linecodes. The line has length 0.117 in the input's length convention and uses
`unknown_lv_ohline_m`. Its three original current ratings are 600 A. This is a
structural choice intended to limit voltage drop, not representative sampling
or an independently selected feeder. Retain the full coupled impedance matrix.

Add an ideal delta-connected generator at each end, with zero active power,
per-coil reactive bounds ±400 kvar and per-coil apparent-power caps 400 kVA.
These are declared research devices, not inferred installed assets. Preserve
all original buses, loads, sources, lines, linecodes and transformers exactly.
No voltage limits or voltage-dependent loads are added. The scenario helper
also supports single-phase devices across two explicitly selected conductors.

Let ``q_{sk}`` be the recovered native-coil reactive injection, with
``s\in\{f,t\}``, ``\sigma_f=1``, ``\sigma_t=-1`` and ``m`` coils per device.
For total target ``Q`` per device, minimize

```math
F(q)=\sum_{s\in\{f,t\}}\sum_{k=1}^{m}
\left(\frac{q_{sk}-\sigma_s Q/m}{1000\;\mathrm{var}}\right)^2.
```

Test ``Q=+600`` and ``-600`` kvar, declared before feeder solves. Opposite targets
are soft requests; they impose neither zero net source exchange nor equality
of achieved injections. Source reactive exchange may supply their mismatch.
This distinction matters when interpreting the results below.

## Formulations, acceptance and independent reconstruction

Cross both transfer directions with six retained arms—full powers, reduced
powers, reduced generator reuse, signed block observations, signed block reuse,
and signed cap-four reuse—and both Ipopt `none` and `gradient-based` policies.
Use the existing 10 kVA assembly/generator units, 1 kVA lifts, nominal transformer
scaling, composed circuit rows and voltage-scaled grounding. Every formulation
uses per-unit coordinates and the BMOPFTools nameplate policy. No new scaling
rule or package default is introduced.

All 24 admissions use the common unloaded physical start and existing strict
solver settings. Require optimal termination, own- and full-model membership,
reverse membership of the first accepted endpoint, independent physical
residuals, independently recovered power objective, and SI JSON reader round
trip. Compare objectives within each direction and policy; this is numerical
agreement of local solutions, not a global-optimality certificate.

A separate Python audit reads the exported voltages and currents. It verifies
all 9,792 inherited line-port margins and 72 transformer margins, reconstructs
the delta coil powers and objective, and checks the selected line's coupled
matrix voltage-drop equation. It also verifies original bytes, field preservation,
addition-manifest replay and equal physical/native-device output structures.
For each of the 24 endpoints, a separate copy with the selected line's rating
reduced by 1% rejects that unchanged point in both the physical and model audits.
This negative witness supplements the original-bound activity measurement.

## Results and scope

All **24/24 admissions pass**. All three selected conductors reach their
inherited 600 A cap at both ends: six active port constraints per endpoint,
counted with nonnegative slack at most ``10^{-5}`` A. No other line limit or
transformer nameplate cap is active.

| Requested from-end total Q (kvar) | Source P (kW) | Source Q (kvar) | Minimum transformer cap slack (kVA per phase) | Active line ports |
|:--|--:|--:|--:|--:|
| +600 | 38.397 | 154.241 | 15.679 | 6 |
| −600 | 38.162 | −148.893 | 13.475 | 6 |

Values summarize all six arms and both policies. The independent objective
error is at most ``4.92\times10^{-11}``; native-power reconstruction error is
at most ``5.89\times10^{-11}`` VA and the selected line's voltage-drop residual
at most ``1.10\times10^{-13}`` V. Both directions retain substantial transformer
slack, while their achieved source exchanges differ because losses, demand,
network geometry and the soft dispatch requests remain in the model.

This closes an active inherited line-current witness for the retained six-arm
panel. Manufactured single-phase and delta regressions additionally exercise
both directions, both solver policies, original 200 A caps, SI exports and
tightened-bound rejection. The study does not establish coverage of every
active-bound combination, shunt-loaded line endpoint asymmetry, transformer
configuration, or feeder. No timings from this correctness panel are ranked.
All previous transformations and slower alternatives remain available.

A subsequent [shunt-loaded endpoint study](ivr_shunt_boundaries.md) supplies
manufactured witnesses with unequal endpoint currents and independently audits
the inherited shunt-current recovery in these archived feeder exports.

## Reproduction and next experiments

Use `examples/benchmark_ivr_line_transfer.jl` and the executable
[tutorial](tutorial_exact_ivr.md#58.-Stress-an-inherited-line-current-bound).
The example accepts an explicit line identifier, corresponding conductor
indices, total device capability and signed reactive target. The addition
manifest records exact new devices; the objective records native power channels.

The protocol, source bytes, scenario, manifests, 24 SI exports, admission and
independent-audit scripts, and validation logs are archived outside Git under
`LINE_BOUNDARY_20261006`. Revised handover and roadmap documents remain outside
Git. There is no speed recommendation from this panel. Further useful tests
are nonzero line shunts with unequal endpoint currents, simultaneous current
and voltage activity, and independently selected feeders. An explicit constraint
on net reactive exchange would define a different physical dispatch experiment
and should be recorded separately from these soft targets.
