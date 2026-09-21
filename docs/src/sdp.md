# IVR semidefinite relaxation

`IVRSDP` builds a semidefinite relaxation in **current--voltage rectangular
(IVR)** coordinates. Its defining choice is to retain physical terminal
voltages and component currents long enough to assemble every linear electrical
law, eliminate those laws, and only then lift the remaining state.

This differs from a textbook bus-injection SDP, which eliminates branch
currents analytically, and from [`BranchFlowSDP`](branch_flow_sdp.md), which
retains a separate ``W/S/L`` block on each line. See the [formulation
guide](formulations.md) for the comparison and [shared notation](notation.md)
for symbols, signs and terminal ordering.

## Physical state before lifting

Let ``z`` collect scaled complex phasors:

```math
z=\begin{bmatrix}
U\\ I^{line}\\ J^{load}\\ J^{generator}\\ J^{transformer}\\ \vdots
\end{bmatrix}.
```

The entries are not generic auxiliary variables. Each current belongs to a
declared line endpoint, connection coil, winding, switch, source or grounding
branch. Connection matrices map coil voltage and current to the ordered bus
terminals. Consequently wye, delta, single terminal-pair and explicit-neutral
devices all enter KCL through their physical return paths.

The following equations are homogeneous and linear in ``z``:

- line voltage drops and endpoint shunt-current laws;
- KCL at every non-grounded terminal;
- fixed source-phasor ratios;
- fixed switch equalities;
- constant-impedance device laws; and
- fixed transformer winding, leakage, tap, grounding and galvanic-bond laws.

They are assembled as

```math
Az=0.
```

Perfectly grounded voltage coordinates are removed exactly. Ideal-ground
currents remain free where the physical model requires them.

## Eliminate, then lift

Let ``N`` be a basis for the nullspace of ``A``. Every state satisfying the
linear electrical core can be written

```math
z=Ny.
```

The exact lifted state is ``H=yy^H`` and therefore satisfies

```math
H\succeq0,\qquad \operatorname{rank}(H)=1.
```

`IVRSDP` drops the rank constraint. A physical product selected by rows ``a``
and ``b`` of the original state is evaluated as

```math
\widehat{(az)(bz)^H}=(aN)H(bN)^H.
```

This “lift after elimination” construction has two useful consequences. First,
all linear electrical equations hold throughout the relaxed moment space, not
only for a recovered phasor candidate. Second, connection and transformer
currents can share one moment matrix without inverting singular delta incidence
matrices or allocating delta power to fictitious phase-to-ground channels.

The cost is that ``H`` may be large. The default numerical profile uses sparse
electrical preprocessing and chordal PSD representations where applicable;
`profile=:reference` retains the dense reference representation. See
[SDP numerical profiles](sdp_numerics.md).

## Sources and the voltage reference

All supplied fixed source phasors are related by exact complex ratios in ``A``.
One nonzero source coordinate anchors the squared magnitude of the lifted state.
This avoids exposing a singular multiphase fixed-source face directly to the
PSD cone while retaining relative angles between multiple sources and islands.

An exact source phasor is still checked against bus voltage limits. Source
current allocation among multiple ideal grounding paths is not inferred, and
current ratings on an explicitly grounded source terminal remain outside the
supported contract.

## Lines and endpoint quantities

For a pi-section line ``\ell:i\to j``, the physical equations are

```math
U_j=U_i-Z_\ell^s I_{\ell ij}^s,
```

```math
I_{\ell ij}=I_{\ell ij}^s+Y_{\ell ij}^{sh}U_i,
\qquad
I_{\ell ji}=-I_{\ell ij}^s+Y_{\ell ji}^{sh}U_j.
```

Both endpoint currents enter terminal KCL. Declared `i_max` and `s_max` bounds
therefore apply to total endpoint quantities, including shunt current, rather
than silently bounding only ``I_{\ell ij}^s``. Parallel lines retain distinct
branch identities and limits.

Squared current limits are affine in ``H``. Apparent-power limits are
second-order-cone constraints on the real and imaginary parts of the appropriate
diagonal voltage-current products. Optional bounds inferred from power and
voltage limits retain their provenance in diagnostics.

## Connection-aware devices and lifted KCL

For device ``d`` at bus ``i``, let ``D_d`` map terminal voltages to coil
voltages and let ``J_d`` be coil current into a passive device:

```math
U_d=D_dU_i,\qquad I_d^{term}=D_d^T J_d.
```

The moment matrix supplies every product needed for coil power,
``\operatorname{diag}(D_dU_iJ_d^H)``, and for the full bus contribution
``U_i(I_d^{term})^H``. P/Q boxes, costs and public quantities remain in the
component's `terminal_map` or coil order; they are not reindexed by the bus
terminal list.

KCL itself was already imposed as a linear current equation before lifting.
Multiplying that exact equation by any lifted state coordinate therefore gives
the corresponding matrix current-balance identities automatically. This is the
IVR counterpart of the explicit full matrix KCL in `BranchFlowSDP`.

## Device laws and additional envelopes

Constant-power loads fix lifted coil powers. Constant-impedance loads use the
exact linear law

```math
J_d=\operatorname{Diag}(\overline{s_d^{nom}}/(v_d^{nom})^2)U_d,
```

including at zero voltage. Generator and source P/Q boxes and linear costs are
affine in lifted powers.

Constant-current, mixed ZIP and exponential loads require power-cone envelopes
in normalized squared voltage. These are **additional relaxations** beyond
dropping ``\operatorname{rank}(H)=1``. A rank-one voltage submatrix does not by
itself prove that a recovered point satisfies the original nonlinear load law.
Affected device IDs and missing finite secant domains are reported through
`load_envelopes` and `solve_diagnostics`.

Static switches, shunts, capacitors, generators, IBR capability/filter models,
and fixed transformers are documented in [static AC components](sdp_static.md)
and [fixed transformers and regulators](sdp_transformers.md). Unknown
electrical fields are rejected rather than ignored.

## Voltage maps and strengthening

For any physical voltage row ``c``, squared magnitude is the affine lifted
quantity

```math
\widehat{|cU|^2}.
```

This supports terminal, phase-to-neutral, phase-to-phase, neutral and sequence
voltage limits without changing the core lift. Optional [lifted nonlinear
cuts](lnc.md) use two such voltage maps and a justified magnitude/angle domain.
`lnc=:lines` derives conservative line domains from declared bounds;
`voltage_lncs` supplies explicit domains. Cuts lacking the required bounds are
skipped and reported rather than completed with nominal-angle assumptions.

Independently, `port_rlt=true` derives voltage-current RLT/LNC pairs when a
finite dispatch P/Q box excludes the origin and finite voltage bounds establish
the associated magnitude and angle domains.

## Units and scaling

BMOPF data enter in SI units and public results return SI units. Internally,
`s_base` supplies the VA base and the largest fixed-source magnitude supplies
the voltage base. The remaining bases are

```math
I_b=S_b/V_b,\qquad Z_b=V_b^2/S_b.
```

Changing `s_base` changes numerical coordinates, not physical data. It can
nevertheless materially affect finite-precision solver behavior. The selected
bases and representation are included in numerical diagnostics.

## Building and solving

```julia
using FormulationLab, Clarabel

build = build_opf(input, IVRSDP(objective=:source_import);
                  optimizer=nothing)

result = solve_opf(input,
    IVRSDP(objective=:source_import, profile=:clarabel);
    solver_options=(verbose=false,))
```

`objective` may be `:cost`, `:source_import` or `:feasibility`. Optional Mosek
can be supplied explicitly by the caller. Solver choice does not change the
electrical formulation.

## Reading a result

`SDPBuild` exposes the reduced moment matrix, nullspace, original-state indices,
physical product maps and lifted power expressions. In `SDPResult`:

- `relaxed_powers` contains lifted W+jvar quantities in documented component
  order;
- `voltage_candidate` and current candidates are reconstructed phasors in SI;
- `rank_ratio` is an eigenvalue diagnostic, not a feasibility test;
- `solver_objective_bound` is the solver's numerical bound report; and
- `load_envelopes`, LNC diagnostics and numerical diagnostics identify every
  additional approximation and skipped strengthening opportunity.

The default voltage candidate uses a source-anchored voltage Gram column;
the reference profile uses a dominant-eigenvector path. Auxiliary current
directions can affect the global rank ratio independently of voltage recovery.

Do not interpret a solver status, objective bound or small rank ratio as a
certified AC solution. Validate reconstructed voltages, currents, device laws,
KCL and operational bounds against the original network. Failed or
non-publishable solves return `NaN` numerical fields rather than plausible
zeros.

## Evidence and scope

The analytical suite includes loaded two-bus circuits, floating neutrals with
mutual impedance, delta loads, reversed orientation, generator capability,
endpoint current infeasibility, impedance loads and fixed transformer cases.
The same mathematical tests can run with Clarabel or optional Mosek.

These tests establish implementation consistency for their covered cases. They
do not prove universal relaxation exactness, exhaustive schema coverage or AC
feasibility of every recovered candidate. See [verification](verification.md),
[AC containment](ac_validation.md), and [literature and
lineage](literature.md).
