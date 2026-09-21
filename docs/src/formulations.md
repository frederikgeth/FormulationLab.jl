# Formulation guide

FormulationLab exposes several models of the same electrical network. They do
not differ only by solver or implementation detail: they retain different
variables, make different approximations, and provide different guarantees.
This page is the recommended starting point before choosing a constructor.

The common physical starting point is a multiconductor network. A bus ``i``
has terminal-voltage vector ``U_i``. A branch ``\ell:i\to j`` has a complete
series-impedance matrix ``Z_\ell^s`` and may have full endpoint shunt
admittances ``Y_{\ell ij}^{sh}`` and ``Y_{\ell ji}^{sh}``. Loads, generators,
capacitors, sources and transformer windings use explicit connection matrices;
there is no implicit conversion of delta devices into wye devices.

Read [notation and conventions](notation.md) for the symbols, orderings and
sign conventions used below.

## Four layers that should not be conflated

Every solve has four conceptually separate layers:

1. **Input contract.** BMOPF data are interpreted in SI units, with explicit
   terminal maps and fixed component parameters.
2. **Electrical model.** KCL, branch laws, winding equations and device laws
   describe an AC operating point.
3. **Optimization representation.** A formulation may linearize the electrical
   model or lift quadratic products and relax rank constraints.
4. **Returned candidate.** Voltage and current phasors reconstructed from a
   relaxation are diagnostics until the original AC equations and limits have
   been checked independently.

A solver status applies to layer 3. It does not by itself certify layer 4.
Similarly, per-unit scaling changes numerical coordinates, not the input
contract or physical units reported to the caller.

## Which formulation should I use?

| Formulation | Main variables | Mathematical class | Best use | Principal limitation |
|:--|:--|:--|:--|:--|
| [`LinDist3Flow`](lindist3flow.md) | voltage and power perturbations around a fixed reference | LP/SOCP approximation | fast fixed-reference studies on networks within its applicability contract | lossless linearization; not an AC relaxation or lower bound |
| [`IVRSDP`](sdp.md) | one reduced Gram matrix of terminal voltages and component currents | SDP relaxation | broad static-component coverage and a strong reference relaxation | global current--voltage state can produce large PSD blocks |
| [`IVRSOC`](soc.md) | the IVR electrical maps with pairwise and selected projected cones | SOCP outer relaxation, plus load power cones | scalable conic experiments and Clarabel-oriented profiles | weaker than the corresponding PSD constraint; strength depends on selected coordinates and cuts |
| [`BranchFlowSDP`](branch_flow_sdp.md) | bus ``W`` matrices and line ``S/L`` moments, plus local device blocks | SDP relaxation | explicit line-flow/current studies and comparison with classic multiphase BFM relaxations | no static IBR model; dense voltage closure is still needed for some meshes and cross-bus constraints |

`IVRSDP` and `BranchFlowSDP` are different formulations, even when they encode
the same rank-one AC point. `IVRSOC` is an outer relaxation of the IVR moment
structure, not a branch-flow SOCP. Numerical profiles, chordal decompositions
and optional cuts are choices *within* a formulation rather than additional
electrical formulations.

## From an AC state to lifted variables

The exact current--voltage state consists of physical phasors. For example,
the branch equations are

```math
U_j=U_i-Z_\ell^s I_{\ell ij}^s,
\qquad
I_{\ell ij}=I_{\ell ij}^s+Y_{\ell ij}^{sh}U_i.
```

An exact lifted model introduces outer products such as

```math
W_i=U_iU_i^H,\qquad
S_{\ell ij}^s=U_i(I_{\ell ij}^s)^H,\qquad
L_\ell^s=I_{\ell ij}^s(I_{\ell ij}^s)^H.
```

These identities imply a positive-semidefinite rank-one block:

```math
M_{\ell ij}=
\begin{bmatrix}
W_i&S_{\ell ij}^s\\
(S_{\ell ij}^s)^H&L_\ell^s
\end{bmatrix}
\succeq0,
\qquad \operatorname{rank}(M_{\ell ij})=1.
```

Dropping the rank constraint gives an SDP relaxation. Replacing selected PSD
conditions by necessary second-order-cone conditions gives a further outer
relaxation. LinDist3Flow instead approximates the original equations around a
fixed voltage reference; it does not arise by dropping rank.

## Topology and the two SDP viewpoints

The bus-injection viewpoint eliminates branch currents and expresses branch
power through voltage products. The branch-flow viewpoint retains current or
power-flow moments on each branch. `BranchFlowSDP` follows the latter for
lines. `IVRSDP` is neither a textbook BIM nor merely the same BFM written in a
dense matrix: it first assembles all homogeneous linear current--voltage laws
``Az=0``, eliminates them with ``z=Ny``, and then lifts ``yy^H``.

On a single-source tree, local branch-flow blocks overlap through bus voltage
matrices. Cycles and multiple fixed sources also require consistent cross-bus
voltage products. `BranchFlowSDP` adds a voltage-only closure Gram when that
information cannot be carried by a tree of local blocks. `IVRSDP` already has
global consistency through its reduced state; chordal decomposition changes
the PSD representation while retaining required overlaps.

## Bounds belong to physical quantities

The same numerical array can mean different things if its physical map is not
stated. The documentation therefore distinguishes:

- bus-terminal voltage magnitude bounds;
- phase-to-neutral, phase-to-phase and sequence-voltage bounds;
- series-current and **total endpoint-current** limits;
- terminal-map power/current limits for dispatch devices; and
- winding-coil limits for delta and transformer windings.

For example, with an endpoint shunt the rated branch current is
``I_{\ell ij}=I_{\ell ij}^s+Y_{\ell ij}^{sh}U_i``. Bounding only
``I_{\ell ij}^s`` is not equivalent. Both SDP implementations preserve this
distinction. See [static AC components](sdp_static.md),
[transformers](sdp_transformers.md), and [schema fields](schema_fields.md).

## A practical selection workflow

1. Read the [component coverage contract](coverage.md) and run the formulation's
   applicability check where one is provided.
2. Choose the electrical formulation before selecting a solver profile or cut
   family.
3. Inspect reduction and scaling diagnostics; input and output remain SI even
   though conic models are solved in per-unit coordinates.
4. Compare relaxation objectives only under identical physical bounds and
   component interpretations.
5. Inspect rank, cone-distance and recovery diagnostics, then validate any
   candidate against the original AC equations before treating it as feasible.

The [literature map](literature.md) explains how these choices relate to the
published BIM, BFM, IVR, chordal, SOC and strengthening results. The
[formulation decision record](formulation_choices.md) documents empirical
defaults and benchmark-specific lessons rather than redefining the mathematics.
