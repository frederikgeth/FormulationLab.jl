# Radial branch-flow SDP

`BranchFlowSDP` is an experimental multiphase branch-flow semidefinite
relaxation. It is a separate mathematical formulation, not an `IVRSDP`
numerical profile. The first implementation deliberately covers radial
series-line networks and rejects every unsupported electrical field.

```julia
using FormulationLab, Clarabel

report = check_branch_flow_sdp_applicability(input)
is_branch_flow_sdp_applicable(report) || error(join(report.findings, "\n"))

build = build_opf(input, BranchFlowSDP(objective=:source_import);
                  optimizer=nothing)
result = solve_opf(input, BranchFlowSDP(objective=:source_import);
                   solver_options=(verbose=false,))
```

## Variables and relaxation

For every bus ``i`` and line ``i\to j``, oriented away from the unique source,
the model introduces

```math
W_i=v_i v_i^H,\qquad S_{ij}=v_i i_{ij}^H,\qquad
L_{ij}=i_{ij}i_{ij}^H.
```

With the complete coupled series impedance ``Z_{ij}``, the voltage equation
``v_j=v_i-Z_{ij}i_{ij}`` becomes

```math
W_j=W_i-S_{ij}Z_{ij}^H-Z_{ij}S_{ij}^H
       +Z_{ij}L_{ij}Z_{ij}^H.
```

Sending and receiving conductor-power vectors are

```math
s^{\mathrm{send}}_{ij}=\operatorname{diag}(S_{ij}),\qquad
s^{\mathrm{receive}}_{ij}=\operatorname{diag}(S_{ij}-Z_{ij}L_{ij}).
```

The rank-one edge identity is relaxed to

```math
\begin{bmatrix}W_i&S_{ij}\\S_{ij}^H&L_{ij}\end{bmatrix}\succeq0.
```

Every child voltage matrix is the Gram image of that edge block. A parent
shared by several children uses the same ``W_i`` in every edge block. Power
balance is imposed per declared conductor. Voltage, series-current and endpoint
apparent-power limits are affine or second-order-cone consequences of these
moments.

The root voltage matrix is fixed to the supplied source phasor Gram. Tree
recovery starts from the supplied root phasors, estimates each branch current
from ``S_{ij}^H v_i/(v_i^H v_i)``, and propagates ``v_j=v_i-Z_{ij}i_{ij}``.
The recovered state is diagnostic and is not certified AC feasible.

## Implemented component slice

The current implementation accepts:

- one fixed voltage source and one connected radial island;
- full coupled line series R/X matrices, aligned complete terminal maps and
  optional `length`, `i_max` and `s_max`;
- explicit terminal and neutral conductors in the line matrices;
- fixed phase-to-ground source phasors and bus `v_min` / `v_max` limits;
- ground-referenced `WYE` devices and `SINGLE_PHASE` devices with one energized
  terminal and an optional perfectly grounded return;
- constant-power and constant-impedance loads;
- generator and source P/Q boxes, S/I limits and linear costs;
- fixed full-matrix bus shunts; and
- `:cost`, `:source_import` and `:feasibility` objectives.

An explicit grounded return is supported as a zero-voltage terminal, but ideal
earth-current allocation is not reconstructed. Floating phase-to-neutral
devices require local device voltage-current moments and are therefore outside
this first slice.

The implementation refuses line endpoint shunts, partial or permuted line maps,
delta devices, switches, capacitors, IBRs, transformers, multiple sources,
meshed networks, voltage-dependent laws other than constant impedance, control
profiles, DC tables and time-series references. This conservative boundary
prevents a successful build from silently discarding supplied physics.

## Relationship to IVRSDP

`IVRSDP` builds one homogeneous current-voltage system, eliminates its linear
equations, and then lifts the remaining coordinates. `BranchFlowSDP` instead
uses bus and edge moments directly. The branch-flow variables expose losses and
receiving powers locally and naturally produce one PSD block per tree edge.

The two relaxations are tested for objective and recovered-voltage agreement on
their common radial series-line subset. This does not establish universal
equivalence: component-local lifts, shunts, bounds and future transformer
extensions can change relaxation strength. Performance must likewise be
measured rather than inferred from cone counts.

## Planned extensions

1. Endpoint line shunts with rated endpoint currents.
2. Delta loads, generators and capacitors using local connection-incidence
   voltage/current moments.
3. Fixed switches and two-winding transformer edge blocks.
4. Center-tap, Yd/Dy, regulator and general multiwinding component blocks.
5. Static IBR filters and shared-link capability constraints.

Those extensions should use component-local PSD blocks whose voltage submatrices
overlap the corresponding bus ``W_i``. General multiwinding devices are
hyperedges rather than ordinary binary branches; treating them explicitly is
preferable to disguising them as a series impedance.
