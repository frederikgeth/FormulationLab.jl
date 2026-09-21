# Branch-flow SDP

`BranchFlowSDP` is an experimental multiphase branch-flow semidefinite
relaxation. It is a separate mathematical formulation, not an `IVRSDP`
numerical profile. It combines classic line ``W/S/L`` blocks with full matrix
current balance, component-local voltage/current moments, and—when the network
requires it—a voltage-closure Gram for cycles and cross-bus products.
Unsupported electrical fields are rejected rather than dropped.

## When to use it

Use this formulation when line sending power, receiving power, endpoint shunt
power and current moments should remain explicit, or when comparing a
branch-flow relaxation with `IVRSDP`. Radial and meshed networks, multiple fixed
sources, fixed switches, capacitors and general multiwinding transformers are
accepted. Use `IVRSDP` instead when static IBR filters/capabilities or its
chordal/numerical profiles are required.

The formulation returns an optimization relaxation, not an AC power-flow
solution. For a minimization objective it supplies a lower-bound model. A low
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
`tcr_voltage=true` adds a Tight-and-Cheap-inspired first-order voltage skeleton.
It is off by default pending broader numerical evaluation; see the construction
below. The option is a strengthening and recovery aid, not a different input
model or a claim that the resulting voltage candidate is AC feasible.
No standalone nonnegative-loss row is added: the branch-flow line and winding
moments already retain their physical current-loss identities, so that row
would be redundant here.

The builder sorts bus and source records before emitting variables and
constraints. This does not change the formulation, but keeps the solver matrix
independent of Julia dictionary hash order, which matters for numerically
sensitive SDP factorizations.

When Clarabel is selected implicitly, the BranchFlow profile disables chordal
decomposition, uses static regularization `1e-7`, and permits up to 30 iterative
refinement steps. Explicit optimizer factories remain caller-owned, and
`solver_options` can override these defaults.

## Variables and relaxation

For every bus ``i`` and oriented line ``i\to j``, the model introduces

```math
W_i=v_i v_i^H,\qquad S_{ij}=v_i i_{ij}^H,\qquad
L_{ij}=i_{ij}i_{ij}^H.
```

With the complete coupled series impedance ``Z_{ij}``, the series voltage equation
``v_j=v_i-Z_{ij}i_{ij}`` becomes

```math
W_j=W_i-S_{ij}Z_{ij}^H-Z_{ij}S_{ij}^H
       +Z_{ij}L_{ij}Z_{ij}^H.
```

For a pi model with endpoint admittances ``Y^f,Y^t``, endpoint currents are

```math
i^f=i_{ij}+Y^fv_i,\qquad i^t=-i_{ij}+Y^tv_j.
```

The series receiving product is ``R_{ij}=S_{ij}-Z_{ij}L_{ij}``, while the
endpoint power matrices used by KCL, limits and public results are

```math
M^f_{ij}=S_{ij}+W_i(Y^f)^H,\qquad
M^t_{ij}=-R_{ij}+W_j(Y^t)^H.
```

Their diagonals are the public endpoint conductor-power outputs. Endpoint
current limits use the corresponding affine current Grams, so a declared
`i_max` rates total endpoint current rather than silently rating only the series
current.

### Optional first-order voltage skeleton

The standard branch-flow relaxation stores second-order voltage products but
does not retain a shared first-order voltage vector. With `tcr_voltage=true`,
the model introduces one complex representative ``u_{i\phi}`` for every bus
terminal and fixes source and ideal-ground entries to their prescribed values.
For each line, transformer, and closed switch local voltage moment ``X_e``, it
adds the small PSD block

```math
\begin{bmatrix}
1 & u_e^H\\
u_e & X_e
\end{bmatrix}\succeq0,
```

where ``u_e`` selects the shared terminal representatives incident to that
component. A multiwinding transformer uses all of its winding-terminal voltage
coordinates in one such block. A physical AC point satisfies these constraints
with ``u=v`` and ``X_e=v_ev_e^H``, so the construction is a valid strengthening.
Sharing ``u`` across local blocks transfers the fixed source reference and
first-order consistency through the network.

This is inspired by the first/second-moment coupling used in Tight-and-Cheap
relaxations, adapted to the multiphase component-local BranchFlow blocks. It is
not a literal implementation of a single-phase polar TCR model: no nominal-angle
linearization is introduced, and the existing full multiphase voltage products
are retained. The construction adds one local cone of order ``1+dim(X_e)`` per
energized network component, not a dense network-wide voltage cone. When it is
enabled, the public voltage candidate comes directly from ``u``; rank and
physical-residual diagnostics still determine whether that candidate is useful.

### Declared and implied line-current limits

Let ``J^f`` and ``J^t`` denote the affine total endpoint-current Grams. For
each rated phase conductor, a positive lower voltage bound and endpoint
apparent-power rating imply

```math
\bar I^f=\frac{S_{max}}{\underline V_f},\qquad
\bar I^t=\frac{S_{max}}{\underline V_t}.
```

A fixed source phasor supplies an exact voltage magnitude. If an explicit
`i_max` also exists, the tighter declared or derived endpoint limit is used:

```math
J^f_{kk}\le\min(I_{max,k},\bar I^f_k)^2,\qquad
J^t_{kk}\le\min(I_{max,k},\bar I^t_k)^2.
```

For coupled endpoint shunts, finite terminal-voltage upper bounds give the safe
row-wise bounds

```math
\bar I^{sh,f}_k=\sum_h |Y^f_{kh}|\bar V^f_h,\qquad
\bar I^{sh,t}_k=\sum_h |Y^t_{kh}|\bar V^t_h.
```

The series-current moment is then strengthened by

```math
L_{kk}\le\left[\min\left(\bar I^f_k+\bar I^{sh,f}_k,
                                  \bar I^t_k+\bar I^{sh,t}_k\right)\right]^2.
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

## Mesh and source voltage closure

On a single-source tree, local edge overlaps have the running-intersection
structure needed to propagate a voltage candidate from the root. A cycle does
not: independently completed edge blocks can otherwise choose incompatible
angle rotations around the loop. Multiple fixed sources similarly need their
declared relative phasors to share one lifted voltage state.

For those cases the model creates a global voltage-only Gram ``G=vv^H`` and
drops its rank-one requirement. Every bus ``W_i`` is a principal submatrix of
``G``. For a line, the adjacent cross-voltage block is constrained by

```math
G_{ij}=W_i-S_{ij}Z_{ij}^H.
```

Transformer and closed-switch cross-voltage blocks overlap ``G`` in the same
way. Products between fixed source coordinates are prescribed from their input
phasors. Thus cycles and relative source angles use one PSD-completable voltage
state while current and power remain in local branch-flow blocks. The same Gram
is enabled for explicit cross-bus LNCs. Automatic line LNCs instead use the
line-local product ``W_i-S_{ij}Z_{ij}^H`` and need no additional voltage Gram.
This is a relaxation—rank-one voltage recovery and AC residual checks remain
necessary.

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

### Ordering conventions

Three orderings meet in these equations and must not be conflated:

- bus moment matrices use `bus.terminal_names` order;
- a component's declared limits, costs, terminal currents and terminal powers
  use its own `terminal_map` order; and
- coil quantities use the connection rows induced by that `terminal_map`.

The connection matrix ``D`` is the explicit bridge: its columns are embedded in
bus-terminal order, while its rows remain in component coil order. For a WYE
device with a neutral, a phase-only limit vector follows the non-neutral entries
of `terminal_map`; a complete-map vector is accepted and its neutral entry is
omitted locally. Scalar declarations broadcast over the resulting channels.
Permuting or selecting terminals therefore changes only the embedding in bus
KCL—it never reorders the component's own arrays.

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

Constant-current, mixed ZIP and exponential loads use the same local
voltage/current block as constant-power loads. If
``x=|u|^2/v_{nom}^2``, auxiliary factors approximate ``x^a`` with power-cone
hypographs or epigraphs and, when finite engineering voltage bounds exist, the
opposite secant inequality. Active and reactive lifted powers are then fixed to
their respective voltage-law factors. This is an additional convex envelope
beyond dropping moment rank; affected load IDs are returned in
`load_envelopes`. An all-impedance ZIP law or exponent-two law is recognized
and stamped with the exact affine admittance instead.

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

Delta generators use the same coil-current block, but three-wire dispatch
quantities are terminal powers ``\operatorname{diag}(CD)`` and terminal
currents ``D^Tj``. Consequently P/Q boxes, costs, ratings, relaxed powers and
recovered currents all retain `terminal_map` order, even when that order differs
from the bus terminal list. The recovered terminal currents sum to zero. A
two-terminal delta remains a single coil channel.

Fixed capacitors are exact connection-aware admittances. With rated reactive
power ``q`` and nominal coil voltage ``v_{nom}``, their current is
``j(q/v_{nom}^2)Dv``; consumed coil power is therefore negative reactive power.
A closed switch has a local block enforcing equal mapped endpoint voltages and
opposite through currents, including endpoint current/apparent-power ratings.
An open switch has zero endpoint current and no voltage equality. Merely
declaring an open switch does not activate the dense global voltage closure;
another requirement such as a mesh, multiple sources, a source-free island or
an explicit voltage LNC may still activate it independently.

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
each branch current from ``S_{ij}^H v_i/(v_i^H v_i)``, and propagates
``v_j=v_i-Z_{ij}i_{ij}``. With a global closure, recovery instead uses a fixed
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
- explicit voltage LNCs and optional line-derived LNCs;
- an optional TCR-inspired first-order voltage skeleton over line, transformer,
  and closed-switch local moments; and
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
4. Sparse/chordal alternatives to the dense voltage closure on large meshes.
5. Broader TCR-skeleton and state-recovery performance studies on larger feeders.
