# Radial branch-flow SDP

`BranchFlowSDP` is an experimental multiphase branch-flow semidefinite
relaxation. It is a separate mathematical formulation, not an `IVRSDP`
numerical profile. It combines classic line ``W/S/L`` blocks with full matrix
current balance and component-local voltage/current moments. Unsupported
electrical fields are rejected rather than dropped.

## When to use it

Use this formulation when the network is a single radial island, its source
voltage is fixed, and the component set fits the contract below. It is useful
when line sending power, receiving power and current moments should remain
explicit, or when comparing a branch-flow relaxation with `IVRSDP` on the same
radial network. Use `IVRSDP` instead when the case contains a mesh, multiple
sources, general multiwinding transformers, switches, capacitors or IBRs.

The formulation returns an optimization relaxation, not an AC power-flow
solution. For a minimization objective it supplies a lower-bound model. A low
local rank ratio and small recovered physical residuals are useful diagnostics,
but neither changes that mathematical distinction.

At a high level, the build proceeds in four steps:

1. orient the line/transformer tree away from the unique voltage source;
2. create one voltage moment matrix per bus and one ``W/S/L`` block per line;
3. attach load and transformer moment blocks to their bus voltage matrices;
4. impose full lifted current balance at every bus and minimize the requested
   objective.

```julia
using FormulationLab, Clarabel

report = check_branch_flow_sdp_applicability(input)
is_branch_flow_sdp_applicable(report) || error(join(report.findings, "\n"))

build = build_opf(input, BranchFlowSDP(objective=:source_import);
                  optimizer=nothing)
result = solve_opf(input, BranchFlowSDP(objective=:source_import);
                   solver_options=(verbose=false,))
```

The applicability check is intentionally separate from model construction so a
caller can report formulation-selection decisions before invoking a solver.
`objective` may be `:cost`, `:source_import` or `:feasibility`; `cone` may be
`:real` or `:hermitian`. `s_base` controls per-unit power scaling and defaults
to 10 kVA.

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

Sending and receiving power matrices are

```math
M^{\mathrm{send}}_{ij}=S_{ij},\qquad
M^{\mathrm{receive}}_{ij}=S_{ij}-Z_{ij}L_{ij}.
```

Their diagonals remain the public conductor-power outputs.

The three matrices have a direct physical reading. ``W_i`` contains squared
voltage magnitudes on its diagonal and cross-terminal voltage products off the
diagonal. ``S_{ij}`` contains conductor complex powers on its diagonal and the
cross-terminal voltage/current products needed by coupled lines off the
diagonal. ``L_{ij}`` similarly contains squared current magnitudes and mutual
current products.

The rank-one edge identity is relaxed to

```math
\begin{bmatrix}W_i&S_{ij}\\S_{ij}^H&L_{ij}\end{bmatrix}\succeq0.
```

Every child voltage matrix is the Gram image of that edge block. A parent
shared by several children uses the same ``W_i`` in every edge block. Voltage,
series-current and endpoint apparent-power limits are affine or
second-order-cone consequences of these moments.

## Matrix current balance and connection moments

Let ``r_i`` be the vector current-balance residual at bus ``i`` with currents
into passive devices positive. Instead of retaining only the diagonal products
``v_{i,\phi}\overline{r_{i,\phi}}``, the model imposes

```math
v_i r_i^H = 0.
```

In moment variables this is the affine matrix equation

```math
\sum_{i\to j} S_{ij}
-\sum_{h\to i}(S_{hi}-Z_{hi}L_{hi})
+M_i^{\mathrm{load}}+M_i^{\mathrm{shunt}}
-M_i^{\mathrm{generator}}-M_i^{\mathrm{source}}
+M_i^{\mathrm{transformer}}=0.
```

Columns belonging to perfectly grounded terminals are omitted because the
ideal earth current is free, matching the AC validator's KCL convention. The
root voltage Gram is prescribed and rank one, so one nonzero root-voltage row
is an exact basis for the otherwise dependent root matrix equations. All
voltage rows are retained at other buses.

Why retain the whole matrix? Diagonal balance only checks each terminal's own
complex-power equation. For a phase-to-phase device, it does not force all
terminal equations to describe one common current vector. The off-diagonal
equations couple those views of the current and rule out solutions that can
satisfy the per-terminal power equations independently. The regression suite
includes a three-phase delta case in which the diagonal-only relaxation obtains
a strictly smaller objective and leaves a nonzero off-diagonal residual.

For a load connection matrix ``D`` and coil current ``j``, the local block is

```math
\begin{bmatrix}W_i&C\\C^H&J\end{bmatrix}\succeq0,
\qquad C=v_i j^H,\quad J=jj^H.
```

The coil powers and terminal injection matrix are

```math
s^{\mathrm{coil}}=\operatorname{diag}(DC),\qquad
M_i^{\mathrm{load}}=CD.
```

For a three-terminal delta, ``D`` is the cyclic phase-to-phase incidence
matrix. For a two-terminal delta it has one difference row. The implementation
never inverts ``D`` and therefore retains delta circulating-current degrees of
freedom. Constant-impedance loads use the exact affine specialization
``C=WD^T\operatorname{diag}(\overline{y})`` without an unnecessary current
Gram.

For example, a three-terminal delta ordered ``a,b,c`` uses

```math
D=\begin{bmatrix}
1&-1&0\\
0&1&-1\\
-1&0&1
\end{bmatrix},
\qquad Dv_i=
\begin{bmatrix}v_a-v_b\\v_b-v_c\\v_c-v_a\end{bmatrix}.
```

If ``j=(j_{ab},j_{bc},j_{ca})``, the bus current is ``D^Tj``. Consequently
``CD=v_i(D^Tj)^H`` is exactly the delta load's contribution to lifted KCL.
This construction also explains why the model does not invent a neutral for a
delta device and does not invert the rank-deficient incidence matrix.

## Transformer component blocks

Every supported two-side transformer or fixed regulator is a topology edge but
uses a component-local moment block rather than pretending to be a series line.
With winding incidence matrices ``D_f,D_t``,

```math
u_f=D_fv_f,\quad u_t=D_tv_t,
\qquad e_f=u_f-Z_fj_f,\quad e_t=u_t-Z_tj_t,
```

```math
e_t=Re_f,\qquad j_f+R^Hj_t=0.
```

The local state contains both complete bus-voltage vectors, both winding-current
vectors, and any galvanic bond or ideal-ground currents. These homogeneous
linear winding equations are eliminated before creating the local PSD cone.
The surviving voltage blocks overlap the corresponding bus ``W`` matrices;
terminal current maps then contribute complete ``v i^H`` matrices to KCL.
Fixed source ratios and zero-voltage ground coordinates are also eliminated
locally to avoid exposed PSD faces. Delta winding currents stay in winding
coordinates; terminal currents are obtained only through ``D^T``.

This is the same connection principle as for a delta load, applied on both
sides of the transformer. KCL sees only terminal-current moments at each bus;
the component block enforces the winding voltage ratio, leakage drops,
ampere-turn balance, excitation current, grounding and galvanic bonds. Thus a
delta winding never needs an artificial phase-to-ground power allocation.

The root voltage matrix is fixed to the supplied source phasor Gram. Tree
recovery starts from the supplied root phasors, estimates each branch current
from ``S_{ij}^H v_i/(v_i^H v_i)``, and propagates ``v_j=v_i-Z_{ij}i_{ij}``.
The recovered state is diagnostic and is not certified AC feasible.

## Reading a result

For a successful solve, the most useful fields are:

- `objective` and `solver_objective_bound`: the unscaled relaxation objective
  and the solver's bound;
- `voltage_moments`, `branch_power_moments` and
  `branch_current_moments`: the physical-unit relaxed matrices;
- `voltage_candidate` and `current_candidate`: the tree-recovered phasors used
  for diagnostics and reconstruction;
- `relaxed_powers`: component coil/conductor powers in physical units;
- `rank_ratio`: the largest line-block second-to-first eigenvalue ratio; and
- `solve` / `numerical_diagnostics`: termination status, cone/scaling metadata
  and all local block rank ratios.

Always check `result.solve.optimal` before reading numerical values. To assess
the recovered candidate, pass its voltage and current dictionaries to
`physical_residuals`; this tests the candidate, not the validity of the SDP
bound itself.

## Implemented component slice

The current implementation accepts:

- one fixed voltage source and one connected radial island;
- full coupled line series R/X matrices, aligned complete terminal maps and
  optional `length`, `i_max` and `s_max`;
- explicit terminal and neutral conductors in the line matrices;
- fixed phase-to-ground source phasors and bus `v_min` / `v_max` limits;
- `WYE` and one- or two-terminal `SINGLE_PHASE` devices;
- `WYE`, two-terminal delta and three-terminal delta constant-power or
  constant-impedance loads;
- generator and source P/Q boxes, S/I limits and linear costs;
- fixed full-matrix bus shunts; and
- fixed single-phase, center-tap, Yd/Dy, autotransformer and open-delta
  regulator winding networks, including fixed taps, winding leakage,
  excitation, neutral grounding, galvanic bonds and declared current limits;
- `:cost`, `:source_import` and `:feasibility` objectives.

An explicit grounded return is supported as a zero-voltage terminal. Ideal
earth currents internal to transformer grounding stamps are reconstructed;
external bus earth-current allocation is intentionally free.

The implementation refuses line endpoint shunts, partial or permuted line maps,
delta generators, switches, capacitors, IBRs, general `n_winding`
transformers, multiple sources, meshed networks, voltage-dependent laws other
than constant impedance, control profiles, DC tables and time-series
references. This conservative boundary prevents a successful build from
silently discarding supplied physics.

## Relationship to IVRSDP

`IVRSDP` builds one global homogeneous current-voltage system, eliminates its
linear equations, and then lifts the remaining coordinates. `BranchFlowSDP`
uses bus, line-edge and component-local moments. The branch-flow variables
expose losses and receiving powers locally; connection and transformer blocks
overlap only through bus voltage moments and matrix KCL.

The two relaxations are tested for objective and recovered-voltage agreement on
their common radial series-line subset. This does not establish universal
equivalence: component-local lifts, shunts, bounds and future transformer
extensions can change relaxation strength. Performance must likewise be
measured rather than inferred from cone counts.

## Planned extensions

1. Endpoint line shunts with rated endpoint currents.
2. Delta generators and capacitors using their schema-specific port-power
   conventions.
3. Fixed switches.
4. General multiwinding transformer hyperedge blocks.
5. Static IBR filters and shared-link capability constraints.

Those extensions should use component-local PSD blocks whose voltage submatrices
overlap the corresponding bus ``W_i``. General multiwinding devices are
hyperedges rather than ordinary binary branches; treating them explicitly is
preferable to disguising them as a series impedance.
