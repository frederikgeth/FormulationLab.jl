# Explicit-neutral no-load current–voltage approximation

`LinIVR` is an experimental approximation assembled from a linear passive
no-load circuit. It retains every ungrounded conductor voltage, component
current, and explicit active/reactive power decision variable. It never invokes
Kron reduction or requests a loaded AC starting point. BMOPFTools remains the
optional nonlinear comparison engine; no nonlinear IVR solver is duplicated.

```julia
using FormulationLab, Clarabel
f = LinIVR(objective=:cost)
build = build_opf(input, f; optimizer=nothing)
result = solve_opf(input, f; solver_options=(verbose=false,))

# A declared neighborhood of the passive reference, not an AC certificate:
local_result = solve_opf(input, LinIVR(voltage_radius=0.1))

# Quadratic passive losses, including transformers and inverter filters:
loss_result = solve_opf(input, LinIVR(objective=:losses))
```

## Equations and reference

The solver-independent electrical assembler is shared with IVRSDP/IVRSOC.
It stamps the full coupled line equations, endpoint shunts, fixed transformer
equations, grounding and conductor KCL before any lifting or approximation.
Ideal grounds have prescribed zero voltage; finite grounds remain admittances.
Meshes do not require a separate approximation.

Let ``u=C^T v`` be a device's physical connection voltages and ``Ci`` its
terminal currents. Wye phase-to-neutral connections include a negative neutral
row in ``C``; delta connections use phase differences. The exact power law is
``s=\operatorname{diag}(u)\overline i``.

The reference sets constant-power load, generator and inverter PCC currents to zero while
retaining impedance loads, shunts, excitation and fixed source phasors. A sparse
QR circuit solve produces ``(v^0,i^0)``. Conductor voltages must be unique;
floating voltage modes and inconsistent references are refused. Current-only
freedom, such as ideal delta circulation or redundant neutral bonds, is allowed.
The builder chooses minimum-norm reference currents in its per-unit state
coordinates, without imposing that choice on operating currents. This is an
expansion-point convention, not a claim that those internal currents are physically
unique. Diagnostics expose the nullity, reference choice and ambiguous current
channels. Internal inverter power approximations can depend on this convention
when internal currents and voltage drops are ambiguous.

Every reported power variable uses the affine product

```math
\widehat s=u^0\overline i+\overline{i^0}u-u^0\overline{i^0}.
```

At a switched-off power port ``i^0=0``, this reduces to
``\widehat s=u^0\overline i``. With ``u^0=a+\mathrm jb`` and
``i=x+\mathrm jy``, ``p=ax+by`` and ``q=bx-ay`` are linear equalities.
Nonzero connection voltage is required, not nonzero neutral-to-ground voltage.
Passive current laws remain exact. An impedance load's power uses the same
affine product with its nonzero reference current.

## Limits and objectives

- Upper physical voltage magnitudes, including neutral and sequence voltages,
  and conductor currents use SOC norm limits. Zero upper limits become two
  linear equalities. These remain meaningful at zero reference neutral voltage.
- Positive lower voltage limits use the supporting halfspace
  ``\Re(\overline{u^0}u)/|u^0|\ge u_{\min}``. It is conservative for the
  approximate phasor, not a guarantee about nonlinear replay. Positive lower
  bounds on zero-reference voltage maps are refused.
- Apparent-power limits constrain affine powers. Actual ``u\overline i`` may
  violate those limits and must be checked separately.
- Optional `voltage_radius=ρ` imposes ``|u-u^0|\leρ|u^0|`` on constant-power
  load/generator/inverter PCC connection voltages. It changes the approximation's domain;
  it does not bound nonlinear solution error or guarantee feasibility.
- `:cost` uses the existing linear generator/inverter/source energy-cost convention;
  `:source_import` sums fixed-source active power; `:feasibility` uses zero.
- `:losses` minimizes quadratic line-series, endpoint-shunt, bus-shunt,
  transformer copper/excitation/finite-neutral-grounding and inverter-filter
  dissipation at the approximate phasors. Passive matrices are required.
  Capacitors and ideal switches have no active loss in this contract.
- Static inverter capability includes PCC P/Q boxes, availability, terminal and
  neutral current limits, apparent-power limits and affine internal active-power
  bounds for a coupled DC link. Those internal bounds omit second-order filter
  losses; actual internal powers must be checked separately. They do not model
  a DC network.

The model is an LP/SOCP approximation with affine objectives, or a convex
quadratic conic approximation with `:losses`. In a series-only circuit with zero
no-load current, first-order source import omits incremental losses. The
quadratic objective can improve dispatch selection, but does not repair power
balance between modeled powers and physical voltage–current products.

## Supported scope

Constant-power and constant-impedance loads (including all-Z ZIP and exponent-2
aliases), wye/single-phase generation, two-/three-terminal delta generation,
delta loads, fixed sources, full matrix lines, shunts and fixed capacitors/switches
use the existing electrical assembly. All seven fixed transformer families are
covered: single-phase, center-tap, wye-delta, delta-wye, single-phase
autotransformer, open-delta regulator and general multiwinding. Static
`SINGLE_PHASE`, `THREE_LEG` and `FOUR_LEG` inverters retain filter circuits and
explicit neutral connections where applicable. Each circuit must pass the
no-load voltage-uniqueness check.

Delta generators and three-leg inverters use coil P/Q and coil current ratings,
matching the inspected BMOPFTools implementation. Their connection voltages are
phase differences, and terminal currents are the differences of adjacent coil
currents. This differs from the existing FormulationLab SDP conductor-power
convention, which remains unchanged. Raw power/current arrays cannot be compared
across those formulations without converting conventions. Unequal delta coil
powers are explicitly tested.

Evaluated controls, grid-forming/internal-voltage regulation, variable taps,
general constant-current/ZIP/exponential loads, DC networks and time series are
outside this prototype. Unsupported physics raises `LinIVRInapplicableError` (malformed data
may raise ordinary input errors). No capabilities are silently projected.

Input/output physical quantities use SI. `build.state`, `build.reference`, and
`build.powers` use per-unit coordinates; `s_base` defaults to 10 kVA. The model
objective is divided by `s_base` and unscaled in the result. Dictionary input
is copied. Prepared inputs can be supplied, but prior reduction remains the
caller's responsibility; `kron_reduction=false` describes this builder only.

## Interpretation and experiment

`result.powers` contains affine powers; `result.physical_powers` contains actual
products from `voltage_candidate` and `current_candidate`. Diagnostics report
maximum device power mismatch, relative connection-voltage displacement,
reference-current ambiguity and quadratic losses split into line/shunt,
transformer and inverter-filter contributions. Solver failure returns NaN objective and empty
candidate dictionaries. No AC bound or feasible dispatch is certified.

For a nonzero constant-power port the diagnostic identity is

```math
\frac{|s_{\mathrm{physical}}-\widehat s|}{|\widehat s|}
=\frac{|u-u^0|}{|u^0|}.
```

Use `physical_residuals(input, result)` to check independent circuit equations
with LinIVR's coil-current convention. For a manually constructed `ACPoint`,
pass `delta_dispatch=:coil` to the checker; its default preserves the existing
SDP conductor convention.
For dispatch usefulness, pin modeled generator/inverter powers in BMOPFTools and replay
its nonlinear power flow, then check the original operational limits. Small
affine-state KCL residual alone cannot establish usefulness. The inspected
BMOPFTools revision checks inverter PCC capability but does not stamp
FormulationLab's inverter filters or internal-power budgets. Those extensions
are verified independently in the SI regression tests, not by the PCC replay.

Run the exploratory panel with the optional integration environment:

```sh
julia --project=test/integration examples/benchmark_linivr.jl
# Additional files, parsed once and never Kron-reduced by the runner:
julia --project=test/integration examples/benchmark_linivr.jl output.json case.json
# Transformer accuracy and static-inverter/delta-generator comparisons:
julia --project=test/integration examples/benchmark_linivr_coverage.jl
```

The synthetic panel varies loading and grounding on coupled four-wire feeders,
includes delta loads, and replays cost/loss-driven dispatches. Timings are single
warmed observations, not a speedup claim. Raw results retain statuses, input
hashes, versions and reference provenance. The initial report and raw data are
in `examples/results/linivr_2026-09-30.md` and its JSON companion.
The expanded panel is in `examples/results/linivr_coverage_2026-09-30.md`
and its JSON companion. Its transformer references are independently constructed
loaded AC states checked in SI; they are used only for validation and never enter
the no-load approximation builder.
For external files, private underscore-prefixed parser/reduction metadata is
detached into the report. Both engines receive identical electrical data. A file
from an existing reduced-data collection retains that collection's prior changes;
the runner does not reconstruct the original topology or undo earlier reductions.

## Generation-cost comparison on ENWL

`examples/benchmark_enwl_cost.jl` compares all 128 ENWL reduced-topology files
against Kron-reduced LinDist3Flow and four-wire BMOPFTools IVR. It retains original
DER costs, consolidates the duplicate priced grid device with the unpriced
voltage source in documented copies, and separately audits five unmodified
economic cases. Both approximate dispatches are replayed on the original
four-wire circuit. Reported model objectives, replayed costs, voltage differences
between optima, and voltage errors at fixed dispatch are distinguished.

The 30 September report finds much smaller fixed-dispatch voltage errors for
LinIVR, but both first-order objectives understate nonlinear costs by a median
4.20%. Omitting loss costs leaves flat reactive-dispatch directions in these
files, which declare no reactive capability bounds. Voltage-model accuracy
therefore does not establish economic optimality or realistic inverter
capability. See the [verification results](verification.md) and
`examples/results/enwl_cost_comparison_2026-09-30.md` for the populations,
failures, operational violations and complete experiment protocol.
