# Branch-flow SDP

`BranchFlowSDP` is an experimental multiphase branch-flow semidefinite
relaxation. It is a separate mathematical formulation, not an `IVRSDP`
numerical profile. It combines classic line ``W/S/L`` blocks with full matrix
current balance, component-local voltage/current moments, and—when the network
requires it—a voltage-closure Gram for cycles and cross-bus products.
Unsupported electrical fields are rejected rather than dropped.

This page uses the package-wide [``U/I/S/W/L`` notation](notation.md). The line
identity ``\ell`` is retained in subscripts so the equations remain meaningful
for parallel branches. Superscript ``s`` means the series element of a pi
section; endpoint quantities include the corresponding shunt.

## When to use it

Use this formulation when line sending power, receiving power, endpoint shunt
power and current moments should remain explicit, or when comparing a
branch-flow relaxation with `IVRSDP`. Radial and meshed networks, multiple fixed
sources, fixed switches, capacitors and general multiwinding transformers are
accepted. Use `IVRSDP` instead when static IBR filters/capabilities are required.

The formulation returns an optimization relaxation, not an AC power-flow
solution. For a minimization objective it supplies a lower-bound model for the
declared problem domain. An explicit `VoltageLNC(origin=:operating_limit)`
restricts that domain and must be interpreted accordingly. A low
local rank ratio and small recovered physical residuals are useful diagnostics,
but neither changes that mathematical distinction.

At a high level, the build proceeds in five steps:

1. identify connected components and a recovery spanning forest;
2. create one voltage moment matrix per bus and one ``W/S/L`` block per line;
3. attach load and transformer moment blocks to their bus voltage matrices;
4. add a voltage-closure Gram when cycles, multiple sources, multiwinding
   hyperedges, switches or cross-bus LNCs require shared voltage products;
5. impose full lifted current balance at every bus and minimize the requested
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
to 10 kVA. BMOPF input remains in SI units. Internally, the voltage base is the
largest fixed-source magnitude, ``I_b=S_b/V_b``, and ``Z_b=V_b^2/S_b``; result
voltages, currents, powers, and objectives are converted back to SI. Changing
`s_base` is therefore a coordinate change, not a physical-data transformation,
although finite-precision solver behavior can depend strongly on that choice.
`lnc=:lines` derives conservative line cuts from declared voltage
and current bounds. These automatic cuts use each line block's existing
cross-voltage product and do not by themselves activate the global voltage
closure. Explicit `VoltageLNC` objects may be passed through `voltage_lncs`.
`implied_current_limits=true` adds valid endpoint- and
series-current bounds inferred from apparent-power and voltage bounds; set it
to `false` only for formulation ablations. It also derives matching current
bounds for closed switches and `n_winding` coils carrying an `s_max` rating.
`port_rlt=true` adds valid voltage-current RLT/LNC pairs when a dispatch P/Q box
excludes the origin and finite voltage bounds prove its current-magnitude and
power-angle domain. It may be disabled independently for ablations.
No standalone nonnegative-loss row is added: the branch-flow line and winding
moments already retain their physical current-loss identities, so that row
would be redundant here.

The conditional global voltage closure has its own representation controls:

- `voltage_decomposition=:auto` uses a dense voltage Gram through 32 live
  voltage coordinates and chordal PSD completion above that threshold;
- `:dense` and `:chordal` force a representation for controlled comparisons;
- `chordal_ordering=:minimum_degree` is the deterministic default, while
  `:minimum_fill` greedily minimizes fill edges at each elimination step; and
- `voltage_clique_size=32` caps adjacent-clique amalgamation. It does not split
  an indivisible maximal clique.

The cap of 32 is a solver-agnostic default. In the repeated Mosek controlled-mesh
panel, a cap of 12 produced smaller models and faster solves on every optimal
BFM case; use it as a measured tuning option rather than a universal setting.
See the [SDP structure study](sdp_performance.md) for the protocol, numerical
agreement checks, and the remaining Clarabel validation gap.

These options affect only the voltage closure. The physical line, transformer,
switch and device moment blocks remain local and unchanged. If no closure is
required—normally a single-source radial feeder without a closed switch,
multiwinding hyperedge or explicit cross-bus LNC—the options create no cone.

The builder sorts bus and source records before emitting variables and
constraints. This does not change the formulation, but keeps the solver matrix
independent of Julia dictionary hash order, which matters for numerically
sensitive SDP factorizations.

When Clarabel is selected implicitly, the BranchFlow profile uses static
regularization `1e-7` and permits up to 30 iterative refinement steps. The
formulation's automatic voltage-closure decision is made before solver
selection. Explicit optimizer factories remain caller-owned, and
`solver_options` can override the solver defaults.

## Physical line model and lifted variables

Consider a physical line ``\ell:i\to j``. Its series and total endpoint currents
satisfy

```math
U_j=U_i-Z_\ell^s I_{\ell ij}^s,
```

```math
I_{\ell ij}=I_{\ell ij}^s+Y_{\ell ij}^{sh}U_i,
\qquad
I_{\ell ji}=-I_{\ell ij}^s+Y_{\ell ji}^{sh}U_j.
```

No diagonal approximation is made to ``Z_\ell^s`` or the endpoint shunts. The
model introduces

```math
W_i=U_iU_i^H,\qquad
S_{\ell ij}^s=U_i(I_{\ell ij}^s)^H,\qquad
L_\ell^s=I_{\ell ij}^s(I_{\ell ij}^s)^H.
```

The lifted voltage-drop equation is

```math
W_j=W_i-S_{\ell ij}^s(Z_\ell^s)^H
       -Z_\ell^s(S_{\ell ij}^s)^H
       +Z_\ell^sL_\ell^s(Z_\ell^s)^H.
```

The series receiving product, expressed in the sending-voltage coordinates, is

```math
R_{\ell ji}^s=S_{\ell ij}^s-Z_\ell^sL_\ell^s.
```

The total endpoint power matrices used by KCL, limits and public results are

```math
S_{\ell ij}=S_{\ell ij}^s+W_i(Y_{\ell ij}^{sh})^H,
```

```math
S_{\ell ji}=-R_{\ell ji}^s+W_j(Y_{\ell ji}^{sh})^H.
```

Their diagonals are the public endpoint conductor-power outputs. Endpoint
current limits use the corresponding affine current Grams, so a declared
`i_max` rates total endpoint current rather than silently rating only the series
current.

The matrices have direct physical readings. ``W_i`` contains squared terminal
voltage magnitudes on its diagonal. ``S_{\ell ij}^s`` contains series conductor
powers on its diagonal and the cross-terminal voltage/current products needed
by mutual coupling off the diagonal. ``L_\ell^s`` contains squared series-current
magnitudes and mutual current products.

At an exact AC point,

```math
M_{\ell ij}=
\begin{bmatrix}
W_i&S_{\ell ij}^s\\
(S_{\ell ij}^s)^H&L_\ell^s
\end{bmatrix}
\succeq0,
\qquad \operatorname{rank}(M_{\ell ij})=1.
```

The SDP drops the rank constraint. Every child voltage matrix is the affine
image of its edge block, and a parent shared by several children uses the same
``W_i`` in each block. Voltage, series-current and endpoint apparent-power
limits are affine or second-order-cone consequences of these moments.

### Declared and implied line-current limits

Let ``L_{\ell ij}`` and ``L_{\ell ji}`` denote the affine total endpoint-current
Grams. For each rated phase conductor, a positive lower voltage bound and endpoint
apparent-power rating imply

```math
\overline I_{\ell ij}=\frac{S_{\ell ij}^{max}}{\underline U_i},\qquad
\overline I_{\ell ji}=\frac{S_{\ell ji}^{max}}{\underline U_j}.
```

A fixed source phasor supplies an exact voltage magnitude. If an explicit
`i_max` also exists, the tighter declared or derived endpoint limit is used:

```math
(L_{\ell ij})_{kk}\le\min(I_{\ell ij,k}^{max},\overline I_{\ell ij,k})^2,
```

and analogously at the ``j`` endpoint.

For coupled endpoint shunts, finite terminal-voltage upper bounds give the safe
row-wise bounds

```math
\overline I_{\ell ij,k}^{sh}=\sum_h |(Y_{\ell ij}^{sh})_{kh}|\overline U_{i,h},
\qquad
\overline I_{\ell ji,k}^{sh}=\sum_h |(Y_{\ell ji}^{sh})_{kh}|\overline U_{j,h}.
```

The series-current moment is then strengthened by

```math
(L_\ell^s)_{kk}\le
\left[\min\left(\overline I_{\ell ij,k}+\overline I_{\ell ij,k}^{sh},
                 \overline I_{\ell ji,k}+\overline I_{\ell ji,k}^{sh}\right)\right]^2.
```

Missing lower bounds prevent only the corresponding `s_max`-derived endpoint
bound; missing upper bounds prevent only a shunt-corrected series bound. The
model never substitutes a phase-ground bound for an ungrounded phase-neutral
quantity. These constraints are valid for the original AC equations but can
tighten the lifted relaxation, following Geth and Liu's
[*Notes on BIM and BFM Optimal Power Flow With Parallel Lines and Total Current
Limits* (2022)](https://doi.org/10.1109/PESGM48719.2022.9917005).

Line `s_max` arrays select phase conductors using the declared `bus_from`
terminal roles. Tree orientation may reverse a line internally, but never
changes the rating channels or their implied-current bounds.

## Mesh and source voltage closure

On a single-source tree, local edge overlaps have the running-intersection
structure needed to propagate a voltage candidate from the root. A cycle does
not: independently completed edge blocks can otherwise choose incompatible
angle rotations around the loop. Multiple fixed sources similarly need their
declared relative phasors to share one lifted voltage state.

For those cases the model creates a global voltage-only Gram ``G=UU^H`` and
drops its rank-one requirement. Every bus ``W_i`` is a principal submatrix of
``G``. For a line, the adjacent cross-voltage block is constrained by

```math
G_{ij}=W_i-S_{\ell ij}^s(Z_\ell^s)^H.
```

Transformer and closed-switch cross-voltage blocks overlap ``G`` in the same
way. Products between fixed source coordinates are prescribed from their input
phasors. Thus cycles and relative source angles use one PSD-completable voltage
state while current and power remain in local branch-flow blocks. The same Gram
is enabled for explicit cross-bus LNCs. Automatic line LNCs instead use the
line-local product ``W_i-S_{\ell ij}^s(Z_\ell^s)^H`` and need no additional
voltage Gram.
This is a relaxation—rank-one voltage recovery and AC residual checks remain
necessary.

### Chordal voltage completion

Writing the complete closure as one Gram ``G\succeq0`` costs quadratically many
scalar variables and gives an interior-point solver one cone whose real
embedding has order twice the number of live voltage coordinates. The network
equations use only a sparse subset: within-bus blocks, cross-bus blocks for
lines, closed switches and transformers, all-source reference products, and
products named by explicit voltage LNCs.

On the chordal path, these supports define an undirected aggregate sparsity
graph. A minimum-degree or minimum-fill elimination heuristic adds fill until
the graph is chordal. If ``C_1,\ldots,C_q`` are its maximal cliques, the dense
constraint is replaced by

```math
G[C_k,C_k]\succeq0,\qquad k=1,\ldots,q,
```

plus equality of the shared entries on clique-tree separators. The tree is a
maximum-weight spanning tree weighted by clique-intersection size, so it has the
running-intersection property and supplies a nonredundant set of overlap
equalities. The positive-semidefinite matrix-completion theorem then guarantees
that these consistent clique matrices admit a global PSD completion. This is an
equivalent representation of the voltage-closure relaxation, not an SOC
approximation and not a topology assumption.

`build.voltage_global` is therefore either a dense matrix or a partial chordal
Gram container with the same indexing interface for declared products.
`value.(build.voltage_global)` computes a dense numerical completion for
recovery and rank diagnostics. A voltage LNC added *after* a sparse build can
only use products already covered by its clique graph; declare new cross-bus
LNCs in `BranchFlowSDPOptions(voltage_lncs=...)` before building so their support
is included.

## Matrix current balance and connection moments

Let ``r_i`` be the vector current-balance residual at bus ``i`` with currents
into passive devices positive. Instead of retaining only the diagonal products
``U_{i,t}\overline{r_{i,t}}``, the model imposes

```math
U_i r_i^H = 0.
```

Let ``\delta(i)`` contain every branch endpoint incident on ``i`` and let
``S_{\ell i}`` denote the corresponding **total endpoint** power matrix defined
above. In moment variables, KCL is the affine matrix equation

```math
\sum_{(\ell,i)\in\delta(i)}S_{\ell i}
+M_i^{load}+M_i^{shunt}+M_i^{capacitor}
-M_i^{generator}-M_i^{source}
+M_i^{transformer}+M_i^{switch}=0.
```

For an outgoing line term, ``S_{\ell i}=S_{\ell ij}^s+
W_i(Y_{\ell ij}^{sh})^H``. For an incoming term it is
``S_{\ell i}=-(S_{\ell hi}^s-Z_\ell^sL_\ell^s)+
W_i(Y_{\ell ih}^{sh})^H``. Writing KCL in endpoint form keeps the pi-section
shunts visible and prevents accidental series/total-current substitutions.

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

### Ordering conventions

Three orderings meet in these equations and must not be conflated:

- bus moment matrices use `bus.terminal_names` order;
- a component's declared limits, costs, terminal currents and terminal powers
  use its own `terminal_map` order; and
- coil quantities use the connection rows induced by that `terminal_map`.

The connection matrix ``D_d`` is the explicit bridge: its columns are embedded in
bus-terminal order, while its rows remain in component coil order. For a WYE
device with a neutral, a phase-only limit vector follows the non-neutral entries
of `terminal_map`; a complete-map vector is accepted and its neutral entry is
omitted locally. Scalar declarations broadcast over the resulting channels.
Permuting or selecting terminals therefore changes only the embedding in bus
KCL—it never reorders the component's own arrays.

For device connection matrix ``D_d`` and coil current ``J_d``, the local block
is

```math
\begin{bmatrix}W_i&C_d\\C_d^H&K_d\end{bmatrix}\succeq0,
\qquad C_d=U_iJ_d^H,\quad K_d=J_dJ_d^H.
```

The coil powers and terminal injection matrix are

```math
s_d^{coil}=\operatorname{diag}(D_dC_d),\qquad
M_i^d=C_dD_d.
```

For a three-terminal delta, ``D_d`` is the cyclic phase-to-phase incidence
matrix. For a two-terminal delta it has one difference row. The implementation
never inverts ``D_d`` and therefore retains delta circulating-current degrees of
freedom. Constant-impedance loads use the exact affine specialization
``C_d=W_iD_d^T\operatorname{Diag}(\overline{y_d})`` without an unnecessary current
Gram.

Constant-current, mixed ZIP and exponential loads use the same local
voltage/current block as constant-power loads. If
``x=|U_d|^2/(v^{nom})^2``, auxiliary factors approximate ``x^a`` with power-cone
hypographs or epigraphs and, when finite engineering voltage bounds exist, the
opposite secant inequality. Active and reactive lifted powers are then fixed to
their respective voltage-law factors. This is an additional convex envelope
beyond dropping moment rank; affected load IDs are returned in
`load_envelopes`. An all-impedance ZIP law or exponent-two law is recognized
and stamped with the exact affine admittance instead.

For example, a three-terminal delta ordered ``a,b,c`` uses

```math
D_\Delta=\begin{bmatrix}
1&-1&0\\
0&1&-1\\
-1&0&1
\end{bmatrix},
\qquad D_\Delta U_i=
\begin{bmatrix}U_a-U_b\\U_b-U_c\\U_c-U_a\end{bmatrix}.
```

If ``J_d=(J_{ab},J_{bc},J_{ca})``, the bus current is ``D_\Delta^TJ_d``.
Consequently ``C_dD_\Delta=U_i(D_\Delta^TJ_d)^H`` is exactly the delta load's
contribution to lifted KCL.
This construction also explains why the model does not invent a neutral for a
delta device and does not invert the rank-deficient incidence matrix.

Delta generators use the same coil-current block, but three-wire dispatch
quantities are terminal powers ``\operatorname{diag}(C_dD_d)`` and terminal
currents ``D_d^TJ_d``. Consequently P/Q boxes, costs, ratings, relaxed powers and
recovered currents all retain `terminal_map` order, even when that order differs
from the bus terminal list. The recovered terminal currents sum to zero. A
two-terminal delta remains a single coil channel.

Fixed capacitors are exact connection-aware admittances. With rated reactive
power ``q`` and nominal coil voltage ``v^{nom}``, their current is
``\mathrm j(q/(v^{nom})^2)D_dU_i``; consumed coil power is therefore negative
reactive power.
A closed switch has a local block enforcing equal mapped endpoint voltages and
opposite through currents, including endpoint current/apparent-power ratings.
An open switch has zero endpoint current and no voltage equality. Merely
declaring an open switch does not activate the global voltage closure;
another requirement such as a mesh, multiple sources, a source-free island or
an explicit voltage LNC may still activate it independently.

## Transformer component blocks

Every supported two-side transformer or fixed regulator is a topology edge but
uses a component-local moment block rather than pretending to be a series line.
With winding incidence matrices ``D_f,D_t``,

```math
U_f^w=D_fU_i,\quad U_t^w=D_tU_j,
\qquad E_f=U_f^w-Z_fJ_f,\quad E_t=U_t^w-Z_tJ_t,
```

```math
E_t=RE_f,\qquad J_f+R^HJ_t=0.
```

The local state contains both complete bus-voltage vectors, both winding-current
vectors, and any galvanic bond or ideal-ground currents. These homogeneous
linear winding equations are eliminated before creating the local PSD cone.
The surviving voltage blocks overlap the corresponding bus ``W`` matrices;
terminal current maps then contribute complete ``UI^H`` matrices to KCL.
Fixed source ratios and zero-voltage ground coordinates are also eliminated
locally to avoid exposed PSD faces. Delta winding currents stay in winding
coordinates; terminal currents are obtained only through ``D^T``.

This is the same connection principle as for a delta load, applied on both
sides of the transformer. KCL sees only terminal-current moments at each bus;
the component block enforces the winding voltage ratio, leakage drops,
ampere-turn balance, excitation current, grounding and galvanic bonds. Thus a
delta winding never needs an artificial phase-to-ground power allocation.
Transformer terminal currents and powers returned in a result follow
`terminal_map_from` and `terminal_map_to`, even when a map is partial or
permuted relative to its bus. On a delta side, `i_max_from` or `i_max_to`
instead rates the winding-coil currents, in winding incidence-row order.

General `n_winding` transformers are genuine hyperedges. One local state
contains every complete bus-voltage vector and every winding coil current. For
each coil position it enforces the coupled leakage equations and ampere-turn
balance from the full pairwise short-circuit matrix; excitation, finite/ideal
neutral grounding, fixed taps and winding `i_max`/`s_max` are retained. Every
winding voltage block overlaps its bus ``W`` and the voltage closure when it is
active. Results use `:transformer_winding` and `:transformer_coil` keys matching
`IVRSDP`. Each winding's terminal current and power vectors have exactly its
`terminal_map` arity and order, including partial or permuted maps on a bus with
additional terminals; the full-bus terminal moment remains internal to KCL.

## Physical voltage maps and LNCs

All bus voltage bounds are affine in ``W_i``. Besides phase/all-terminal
`v_min`/`v_max`, the formulation supports phase-neutral `vpn_*`, phase-pair
`vpp_*`, neutral `vn_max`, and positive-, negative- and zero-sequence bounds.
Scalar `v_min` or `v_max` values broadcast across phase terminals; vectors may
instead describe the phases or every bus terminal. Terminal and sequence
ordering rules are shared with `IVRSDP`.

An explicit `VoltageLNC` evaluates its phasor maps in the voltage-closure Gram,
adds the declared magnitude/angle domain, and records its provenance. With
`lnc=:lines`, each line uses physical voltage bounds, endpoint current ratings,
the complete coupled series impedance and endpoint shunts to derive a safe
voltage-drop sector. Its products come directly from ``W_i``, ``W_j`` and the
line-local cross moment, including on radial feeders without a global voltage
closure. A cut lacking the required finite bounds is recorded as `:skipped`
with a reason; it is never guessed from nominal angles or a solved power-flow
sample.

Every source voltage matrix is fixed to its supplied phasor Gram. Without a
global voltage closure, tree recovery starts from the source phasors, estimates
each branch current from ``(S_{\ell ij}^s)^H U_i/(U_i^H U_i)``, and propagates
``U_j=U_i-Z_\ell^sI_{\ell ij}^s``. With a global closure, recovery instead uses
a fixed
source coordinate as an anchor column of ``G``; a source-free disconnected
component uses an arbitrary leading-eigenvector anchor. Component currents are
then recovered conditionally from their local moment blocks. These candidates
are diagnostics and are not certified AC feasible.

## Reading a result

For a successful solve, the most useful fields are:

- `objective` and `solver_objective_bound`: the unscaled relaxation objective
  and the solver's bound;
- `voltage_moments`, `branch_power_moments` and
  `branch_current_moments`: the physical-unit relaxed matrices;
- `voltage_candidate` and `current_candidate`: tree- or global-anchor-recovered
  phasors used for diagnostics and reconstruction;
- `relaxed_powers`: component coil/conductor powers in physical units;
- `load_envelopes` and `lnc_diagnostics`: the nonlinear load envelopes and
  applied/skipped lifted nonlinear cuts;
- `numerical_diagnostics[:line_bound_diagnostics]`: declared, derived and
  effective endpoint-current bounds plus the implied series-current bounds;
- `numerical_diagnostics[:device_bound_diagnostics]`: declared, inferred and
  effective closed-switch and multiwinding-coil current bounds;
- `numerical_diagnostics[:port_rlt_diagnostics]`: applied or skipped
  operational-box voltage-current cuts and their derived domains;
- `rank_ratio`: the largest topology-block (line, transformer, closed switch or
  global voltage closure) second-to-first eigenvalue ratio; and
- `solve` / `numerical_diagnostics`: termination status, cone/scaling metadata
  and all local block rank ratios.

Load and dispatch component blocks are included in
`numerical_diagnostics[:local_rank_ratios]` but not in the headline
`rank_ratio`: their auxiliary current completions can have free higher-rank
modes even when the voltage/branch topology relaxation is exact. If a model has
no topology block, the headline ratio is `NaN` rather than an apparent exact
zero.

Always check `result.solve.optimal` before reading numerical values. To assess
the recovered candidate, pass its voltage and current dictionaries to
`physical_residuals`; this tests the candidate, not the validity of the SDP
bound itself.

## Implemented component slice

The current implementation accepts:

- radial or meshed AC components, multiple fixed voltage sources, and
  source-free components isolated by open switches;
- full coupled line series R/X matrices, aligned complete terminal maps and
  optional endpoint shunts, `length`, `i_max` and `s_max`, including implied
  total/series-current strengthening from `s_max` and voltage bounds;
- explicit terminal and neutral conductors in the line matrices;
- fixed phase-to-ground source phasors and the complete family of physical bus
  voltage maps and sequence limits;
- `WYE` and one- or two-terminal `SINGLE_PHASE` devices;
- `WYE`, two-terminal delta and three-terminal delta constant-power,
  constant-impedance, constant-current, ZIP and exponential loads;
- wye and delta generators, plus source P/Q boxes, S/I limits and linear costs;
- fixed full-matrix bus shunts, connection-aware capacitors and fixed
  open/closed switches;
- fixed single-phase, center-tap, Yd/Dy, autotransformer and open-delta
  regulator winding networks, including fixed taps, winding leakage,
  excitation, neutral grounding, galvanic bonds and declared current limits;
- general fixed `n_winding` transformer hyperedges with pairwise leakage,
  excitation, neutral grounding and winding ratings;
- explicit voltage LNCs and optional line-derived LNCs; and
- `:cost`, `:source_import` and `:feasibility` objectives.

An explicit grounded return is supported as a zero-voltage terminal. Ideal
earth currents internal to transformer grounding stamps are reconstructed;
external bus earth-current allocation is intentionally free.

The implementation still refuses partial or permuted line endpoint maps, IBRs,
adjustable transformer taps, active control profiles, DC tables and time-series
references. Geometry metadata may be retained, but electrical line coefficients
must already be compiled. This boundary prevents a successful build from
silently discarding supplied physics.

## Relationship to IVRSDP

`IVRSDP` builds one global homogeneous current-voltage system, eliminates its
linear equations, and then lifts the remaining coordinates. `BranchFlowSDP`
uses bus, line-edge and component-local moments. The branch-flow variables
expose losses and receiving powers locally. A conditional voltage-only closure
Gram coordinates cycles, sources, switches, multiwinding hyperedges and
cross-bus LNCs, but it does not introduce the full global current-voltage Gram
used by `IVRSDP`.

The two relaxations are tested for objective and recovered-voltage agreement on
radial and meshed lines, endpoint shunts, multiple sources, connection-aware
devices, nonlinear load envelopes and fixed transformer families. This does not
establish universal equivalence: their different PSD completions and local
auxiliary-current lifts can change relaxation strength. Performance must
likewise be measured rather than inferred from cone counts.

## Planned extensions

1. Static IBR filters and shared-link capability constraints.
2. Partial or permuted line endpoint maps.
3. Adjustable controls and taps with explicit convex relaxations.
4. Stronger state recovery and performance studies on larger feeders.
