# AC feasibility and relaxation containment

A useful relaxation must retain every feasible AC state. Solver status and a
plausible objective alone do not establish that property. FormulationLab provides
two separate checks:

* `physical_residuals(net, point)` independently evaluates electrical equations,
  device laws, ratings and KCL in SI units. It does not call the formulation's
  stamping or bound-propagation helpers. Missing observations or unsupported root
  components prevent a passing assessment.
* `containment_report(build, point)` reconstructs electrical coordinates, lifts
  the state to rank-one moments and evaluates every compiled JuMP constraint,
  including cuts and derived bounds. It does not call an optimizer or alter the
  model. Build with `audit=true` to retain the required coordinate maps.

```julia
build = build_opf(net, IVRSOC(audit=true); optimizer=nothing)
point = ACPoint(voltage=voltages_si, currents=currents_si)
physical = physical_residuals(net, point)
encoding = containment_report(build, point)
```

`voltage` maps `(bus, terminal)` to complex volts. `currents` maps
`(component_symbol, id)` to vectors of complex amperes: for example `:load`,
`:line_from`, `:line_to`, `:voltage_source`, `:transformer_coil_from` and
`:transformer_from`. Transformer IDs include their family, e.g.
`"delta_wye/tx"`. Currents follow the physical channel orientations used in the
component equations; transformer terminal currents enter the transformer.

Check **all** of `state_residual_pu`, `binding_residual`,
`max_bound_violation_pu`, `max_constraint_violation`, and `missing_voltage`.
Reconstruction uses dense linear least squares; a small cone residual cannot
excuse inconsistent observations or an inaccurate binding. This diagnostic is
intended for small verification circuits, not large-feeder production builds.
Audit capture is disabled by default.

`complete_ac_point(build, point)` fills missing current channels and returns the
reconstruction residual and the names of inferred channels. It preserves supplied
observations. Inferred winding currents are not independent evidence: physical
validation of completed points must be read together with the reconstruction
residual and the list of observed channels.

The physical checker uses separate voltage, current and power tolerances
(defaults: 10 μV, 1 μA, 1 mVA). It evaluates static components only; control laws
remain outside the model. It is a numerical verification tool, not a replacement
for PowerIO schema validation or a formal certificate of correctness.

## Coverage of the new containment suite

The suite constructs feasible states without solving the relaxation:

* All six two-port transformer/regulator families, with non-unity fixed taps,
  unbalance, reverse flow, a global phase rotation and binding current ratings.
* A coupled, non-star four-winding network with a delta winding and explicit
  excitation on that winding.
* Dense Hermitian SDP, local/shared chordal SDP, and fixed SOC profiles
  `:none`, `:linear`, `:kim`, at two power bases.
* Constant-power, constant-current, impedance, ZIP and exponential loads,
  including negative reactive exponents, and automatic line LNCs.
* Ideal/finite neutral grounding and three-/four-leg inverter filters and fixed
  internal voltage magnitudes.
* Deliberately corrupted voltage/current observations and tightened ratings,
  which must be rejected.

This adds evidence for the implemented equations, not exhaustive coverage of
all parameter combinations. Terminal permutations, every regulator connection,
all explicit excitation placements and external multiwinding NLP comparisons
remain useful extensions. Existing OpenDSS and analytical tests complement these
new checks.

## BMOPFTools / Ipopt findings — 11 September 2026

The optional `test/integration` environment loads the sibling BMOPFTools checkout
at revision `ddd588f7143ae218142e4176e8086199179722c3`, with Ipopt 1.16.0.
The retained JSON is `examples/results/transformer_reference_audit_2026-09-11.json`.
The 25 cases use fixed taps 0.94/1.06, constant-power loads and forward/reverse
operation, plus one legacy-excitation case.

| Cases | Result |
|---|---|
| Single phase, no excitation (4) | Physical and all four containment profiles pass |
| Single-phase autotransformer (4) | Physical and all four containment profiles pass |
| Open-delta regulator (4) | Physical and all four containment profiles pass |
| Center tap (4) | Reference state disagrees with the winding equations |
| Delta–wye with combined leakage fields (4) | Reference state disagrees with the winding equations |
| Wye–delta (4) | BMOPFTools initialization raises a terminal-index `BoundsError` |
| Single phase with legacy excitation (1) | Reference currents disagree with the excitation placement |

**Parser follow-up:** [BMOPFTools issue #393](https://github.com/frederikgeth/BMOPFTools.jl/issues/393)
retested the direct-dictionary findings through `parse_bmopf`. The delta–wye
combined-leakage case then passes: the parser migrates combined fields onto the
wye winding. It also materializes explicit `no_load_shunt` records, which raw
solve dictionaries bypass. The table above describes the retained **raw-input**
audit, not failures of the parsed-input Dy model. The Yd initialization crash and
center-tap convention discrepancy persist after parsing.

The incompatible cases are retained as findings, not counted as passing
validation. No model or input convention is silently changed to force agreement.
The accepted states pass dense SDP, chordal SDP, SOC-linear and SOC-Kim; their
Clarabel objectives are no larger than the feasible reference objective within
1 mW. This comparison uses numerical primal objectives, not certified dual bounds.
An Ipopt local solution supplies a feasible upper bound, not a global optimum.

Diagnostic re-encodings narrow two discrepancies: dividing the center-tap
primary leakage input by `tap²`, or removing the delta–wye combined leakage
fields, reduces the respective reconstruction residuals to approximately
`2.3e-15` and `5.1e-16` pu for the 1.06-tap forward case. These are
convention probes, not accepted corrections to the original input.

Before claiming cross-engine coverage for every transformer, resolve the tap /
leakage referral and excitation conventions and the wye–delta initialization
failure. BMOPFTools remains a useful reference, but cannot presently be treated
as an unquestioned oracle for those cases.

## Cone-distance detail

MOI's default rotated-SOC distance is an upper bound obtained by changing one
coordinate. Near a zero diagonal it can amplify roundoff into an order-one
reported violation for a rank-one point. The containment checker instead uses
an orthogonal rotation to a standard SOC and its Euclidean distance. It also
retains `raw_moi_distance_upper_bound` for diagnosis. This changes the audit
metric only; it does not weaken any model constraint.

```@docs
ACPoint
physical_residuals
containment_report
complete_ac_point
```
