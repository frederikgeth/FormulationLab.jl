# Exact IVR: equations and equivalence domain

This chapter states the mathematical problem implemented by `IVRNLP` and the
assumptions under which its conductor specialization is equivalent to the full
model. [The contract reference](ivr_nlp.md) specifies accepted fields and
exceptions; [the tutorial](tutorial_exact_ivr.md) tests the equations on small
networks. Symbols follow [the shared notation](notation.md). All quantities in
this chapter are in SI units unless a per-unit variable is explicitly indicated.

## 1. Network state and signs

Let ``U_i\in\mathbb C^{|\mathcal T_i|}`` contain bus terminal-to-ground voltages.
Each component uses its declared terminal ordering. For a device with real
connection matrix ``D_d``, define its coil voltages and terminal currents by

```math
U_d=D_d U_i,\qquad I_d^{\mathrm{term}}=D_d^T I_d.
```

A single-phase pair has ``D_d=\begin{bmatrix}1&-1\end{bmatrix}``, a four-wire wye has
``D_d=[I_3\; -\mathbf1]``, and an ordered three-terminal delta has

```math
D_\Delta=\begin{bmatrix}1&-1&0\\0&1&-1\\-1&0&1\end{bmatrix}.
```

Here ``[I_3\;-\mathbf1]`` denotes horizontal concatenation, i.e. a ``3\times4``
matrix. A terminal-to-earth coil instead has a single ``+1`` row; its current
need not sum to zero across declared conductors.

Load, capacitor and shunt currents are positive into the consuming device.
Generator, inverter and source currents are positive when injected into the
network. Line endpoint currents are positive from the bus into the line.
KCL sums these signed **terminal** currents at each ungrounded bus terminal.
Ideal grounds impose ``U_{i,t}=0`` and omit that terminal's KCL equation in the
common-earth model. Finite grounding impedances retain their voltage and current
law. The resulting source-versus-earth current ambiguity at ideal grounds is
reported, not reconstructed as a uniquely known source-neutral current.

## 2. Electrical and operating equations

For an oriented line with aligned endpoint vectors, the full pi model is

```math
U_i-U_j=Z_\ell^s I_\ell^s,\qquad
I_{\ell ij}=I_\ell^s+Y_{\ell ij}^{sh}U_i,\qquad
I_{\ell ji}=-I_\ell^s+Y_{\ell ji}^{sh}U_j.
```

The matrices may contain mutual coupling and unequal endpoint shunts. Physical
current limits apply to ``I_{\ell ij}`` and ``I_{\ell ji}``, not merely to the
series current. Public endpoint currents follow the input orientation.

For a coil/channel power ``s=u\overline\iota=p+\mathrm j q``, rectangular
coordinates give

```math
p=u_r\iota_r+u_i\iota_i,\qquad
q=u_i\iota_r-u_r\iota_i.
```

These products are retained exactly. A constant-power load fixes ``p,q`` to its
nominal values. A constant-impedance load uses

```math
\iota=\frac{\overline{s^{\mathrm{nom}}}}{(u^{\mathrm{nom}})^2}u.
```

Generator P/Q are explicit auxiliary variables equated to the products and
bounded by the declared boxes. This separates reusable bounds/prices from the
fixed electrical expressions. Exact products make the problem nonconvex;
“exact” classifies the formulation, not a solver's optimality guarantee.

For a physical voltage map ``c^T U`` and current map ``a^T I``, supported limits
have the forms

```math
(u^{\min})^2\le |c^T U|^2\le(u^{\max})^2,\qquad
|a^T I|^2\le(i^{\max})^2,\qquad
p^2+q^2\le(s^{\max})^2.
```

The lower voltage bound is nonconvex. Voltage maps distinguish phase-ground,
phase-neutral, phase-pair and sequence quantities. A line apparent-power bound
uses terminal-ground voltage and **total endpoint current**. The field-by-field
[bound inventory](ivr_nlp.md#Operating-bound-coverage) gives the actual arities,
phase selection, precedence and source-current exceptions. A nameplate or
nominal value introduces no additional operating limit unless the contract says
so. Unknown electrical fields are refused.

Fixed switches impose either equal mapped endpoint voltages with opposite
endpoint currents, or zero endpoint currents without a voltage tie. Capacitors
use ``I_d=\mathrm j B_d U_d``; positive rated vars therefore mean negative
reactive consumption. See [bank-rating conventions](sdp_static.md). Fixed
transformers and regulators retain the
[winding, leakage and excitation equations](sdp_transformers.md) for all seven
fixed-setting families in [the scope reference](ivr_nlp.md).

### Voltage-dependent demand

For nominal coil voltage ``u_0>0``, define ``r=|u|/u_0``. The active and
reactive powers are

```math
p=p_0 f_p(r),\qquad q=q_0 f_q(r),\qquad s=u\overline\iota.
```

| Law | ``f_p(r)`` | ``f_q(r)`` |
|:--|:--|:--|
| Constant power | ``1`` | ``1`` |
| Constant current | ``r`` | ``r`` |
| Constant impedance | ``r^2`` | ``r^2`` |
| ZIP | ``\alpha_z r^2+\alpha_i r+\alpha_p`` | ``\beta_z r^2+\beta_i r+\beta_p`` |
| Exponential | ``r^{\gamma_p}`` | ``r^{\gamma_q}`` |

Each ZIP triple is nonnegative and sums to one. Active and reactive fractions
or exponents may differ. “Constant current” denotes constant current magnitude
and power factor at nonzero voltage; the current phasor rotates with coil
voltage. It is not a fixed complex current injection.

For nonlinear voltage laws the implementation uses an auxiliary ``x=r^2``:

```math
x=\frac{u_r^2+u_i^2}{u_0^2},\qquad
\left(\frac{u^{\min}}{u_0}\right)^2\le x\le
\left(\frac{u^{\max}}{u_0}\right)^2.
```

A matched physical bound must establish ``u^{\min}>0``; a finite upper bound is
optional. Substituting ``r=\sqrt{x}`` gives smooth power functions on this domain,
including negative exponents. This auxiliary is uniquely determined by the
physical state, so adding it preserves the feasible set within the declared
domain. It provides an explicit positive variable domain for nonlinear solvers;
no regularization changes the equations. Solver trial points and convergence
still depend on the chosen solver and its bound-handling options.

A fixed nonzero source coil or equal matched engineering magnitude bounds need
no auxiliary: their power factors are constant on the declared domain. The
original physical voltage bounds remain enforced. Exactly pure impedance cases
use ``\iota=\overline{s_0}u/u_0^2`` directly, including at ``u=0``. Checking only
``u\overline\iota=s_0r^2`` would fail to enforce zero current at zero voltage;
both the compiled circuit and independent auditor therefore check the current
law for these cases. The contract deliberately does not define a deenergized
continuation for the other voltage-dependent load laws.

### Conductive bonds in fixed regulators

Let ``b`` denote current in a bond from terminal ``k`` on the from side to
terminal ``k`` on the to side. Its equations and contributions are

```math
U_{f,k}=U_{t,k},\qquad
I_f^{\mathrm{term}}=D_f^T(J_f+Y_fU_f^w)+e_k b,\qquad
I_t^{\mathrm{term}}=D_t^T(J_t+Y_tU_t^w)-e_k b.
```

Multiple bonds contribute additively; internal neutral-earth branches add their
own terminal current. The common conductor is an electrical connection, not a
choice of voltage gauge. An ideal earth branch fixes its voltage and leaves its
current free. Consequently, some combinations of ideal grounds and bonds admit
nonunique current allocations even with unique conductor voltages. Explicit
bond observations allow the supplied-point checker to test a particular
allocation. Independent physical validation without those observations tests
only observable relations. Neither procedure claims current uniqueness.

### Static inverter circuit and port quantities

With PCC coil voltage ``U_d`` and current ``I_d``, the internal filter state is

```math
J_f=I_d+\mathrm j B U_d,\qquad E=U_d+Z_fJ_f,\qquad
s^{\mathrm{int}}=E\circ\overline{J_f}.
```

``B`` is the declared scalar susceptance and ``Z_f`` is diagonal with declared
per-coil ``r_filter + j*x_filter``. SINGLE_PHASE and FOUR_LEG PCC powers use
coil quantities. THREE_LEG instead exposes conductor PCC powers
``U_i\circ\overline{D_\Delta^T I_d}``; its internal filters still use delta
coils. Delta **generators** retain coil powers. These distinctions affect
per-channel P/Q/S/I constraints even though total complex power is preserved.

With `dc_link_coupled=true`, scalar bounds constrain
``\sum_c\operatorname{Re}(s_c^{\mathrm{int}})``. For this pure-susceptance
shunt and real nonnegative filter resistances,

```math
\sum_c\operatorname{Re}(s_c^{\mathrm{int}})-P_{\mathrm{PCC}}
=\sum_c r_{f,c}|J_{f,c}|^2.
```

`p_avail` separately bounds total active PCC injection. A fixed internal
magnitude setpoint imposes ``|E_c|=v^{\mathrm{ref}}``; it supplies neither droop
control nor an island angle reference. THREE_LEG coil circulation lies in
``\ker D_\Delta^T`` and can affect internal losses while leaving PCC currents
unchanged. It remains part of the model. These are declared native circuit
semantics, not evidence that every manufacturer's inverter or external schema
uses the same filter interpretation.

### Objective and normalization

`:source_import` minimizes the sum of real source-port powers in watts.
`:cost` minimizes

```math
f=\frac{1}{1000}\sum_{d\in\{\text{sources, generators, IBRs}\}}
\sum_c c_{d,c}p_{d,c},
```

where ``c`` is currency/kWh and ``p`` is W. Thus ``f`` is a cost **rate** in
currency/h. A snapshot has no implicit integration interval. `:feasibility`
sets the objective to zero. Distinct colocated sources and generators retain
their own injections, bounds and prices; a legacy slack label does not merge
their accounting.

The implementation uses ``V_b`` equal to the largest prescribed source voltage
magnitude, ``S_b=\mathtt{s\_base}``, ``I_b=S_b/V_b`` and ``Z_b=V_b/I_b``.
Scaling changes numerical coordinates; returned voltages, currents, powers and
objectives recover their physical units. It does not relax any bound.

## 3. Conductor-difference identity

Let ``P\in\mathbb R^{(m-1)\times m}`` have full row rank and
``P\mathbf1=0``. For a current satisfying ``\mathbf1^T I=0``, define

```math
J=(PP^T)^{-1}PI,\qquad I=P^TJ,\qquad U^\Delta=PU.
```

**Power identity.** Substitution gives
``U^T\overline I=(PU)^T\overline J``. This preserves total complex power;
it does not identify individual conductor powers with individual transformed
channel powers. Every original per-conductor bound must still be evaluated
through reconstruction.

**Series-drop identity.** For a line without endpoint shunts,

```math
U_i^\Delta-U_j^\Delta=(PZ_\ell^sP^T)J_\ell.
```

The available bases are

```math
P_2=\begin{bmatrix}1&-1\end{bmatrix},\qquad
P_3=\begin{bmatrix}1&-1&0\\0&1&-1\end{bmatrix},\qquad
P_4=\begin{bmatrix}1&0&0&-1\\0&1&0&-1\\0&0&1&-1\end{bmatrix}.
```

For two wires, ``Z^\Delta=Z_{11}-Z_{12}-Z_{21}+Z_{22}``; only when
``Z_{12}=Z_{21}`` may this be written ``Z_{11}+Z_{22}-2Z_{12}``.
No balanced loading or phase-permutation symmetry is assumed.

### Why the network certificate is necessary

The algebra alone does not establish ``\mathbf1^T I_\ell=0``. The implemented
whole-section certificate requires one connected, source-rooted tree of complete, consistently
mapped two-, three- or four-conductor lines; no nonzero line shunts; no downstream
bus shunts or grounds; and downstream device connection rows summing to zero.
It also checks source boundary and neutral-role compatibility. Transformers and
switches currently cause conservative fallback, even when an enlarged proof
might admit them. Exact zero tests are used: a small earth admittance is not zero.

**Subtree argument.** At a leaf, summing terminal KCL eliminates all zero-sum
device currents, leaving zero total current on its parent line. Inductively,
all child-line totals vanish, so the parent-line total vanishes at every
nonroot bus. Root KCL stays in full. This proves the current identity for the
whole declared operating domain, including future demand and dispatch updates;
an accidental balance at one solution would not suffice.

### What is eliminated in the implementation

The implementation reconstructs line currents as ``I_\ell=P^TJ_\ell`` and
removes one implied complex KCL equation per nonroot bus. It retains **all**
original voltage-drop equations. At each nonroot bus it retains both ``PU_i``
and one physical reference-conductor voltage ``u_i^r``:

```math
\begin{bmatrix}PU_i\\u_i^r\end{bmatrix}
=\begin{bmatrix}P\\e_r^T\end{bmatrix}U_i.
```

This square map is invertible for the implemented bases. Neutral/phase-ground
voltages therefore remain observable and their bounds remain local. The code
does not substitute only the differential drop and discard its common-mode
counterpart. Delta coil currents, source equations and internal device freedoms
also remain. Exactly one complex line-current coordinate is removed per line;
a universal fraction of total OPF variables is not claimed.

**Conditional equivalence.** Under the certificate, every full feasible point
projects to a reduced feasible point and reconstructs to the same observable
physical state. Conversely, reconstructed reduced points satisfy the retained
line equations, all device/operating constraints and the omitted KCL equation,
which follows from the zero-sum identities and remaining terminal KCL. The
objective is evaluated on those reconstructed physical powers. This is an
algebraic equivalence statement within the declared domain; finite-precision
solves are checked separately. It is distinct from neutral Kron reduction and
from topology simplification.

### Pendant-region certificate

For ``R`` a tree interior with one retained boundary bus ``b``, let each
interior bus have a complete, consistently mapped conductor set, no ideal or
finite earth path, and only device connections whose terminal currents sum to
zero. Region lines have no endpoint shunts. No restriction is imposed on the
circuit outside ``R`` or on devices connected at ``b``.

**Leaf induction.** Sum conductor KCL at an interior leaf. Its devices contribute
zero to this sum, hence its parent-line current sums to zero. Remove that leaf
from the proof graph. At the next interior bus, already certified child-line
currents and local device currents all sum to zero, so its parent-line current
also sums to zero. Continue until reaching ``b``. The argument never sums or
removes boundary-bus KCL and does not assert zero-sum upstream current.

The implementation realizes this induction by removing unblocked degree-one
vertices from a multigraph. A removed vertex has only its certified descendants
and its one remaining parent edge. Cycles, parallel-edge cores and connections
between retained boundaries cannot be removed this way. Sources, earth paths,
transformer/switch ports, partial conductor ports and incompatible line maps
are explicitly retained. Thus no unobserved external connection can enter an
interior omitted-KCL equation. Trees sharing a boundary have disjoint interiors
and current coordinates; their transformations compose independently.

The same reconstruction ``I=P^T j`` and invertible retained-reference voltage
map apply within each region. All boundary voltages remain physical. The
remaining ``m-1`` conductor KCL equations, the device identities and zero-sum
incident line currents imply the omitted conductor equation at each interior
bus. Keeping every original KVL and operating expression under reconstruction
therefore gives the same conditional feasible-set and objective equivalence as
for the complete section. With ``L_R`` selected tree edges, the implementation
removes ``2L_R`` real current variables and ``2L_R`` real KCL equations.

The eligibility conditions are sufficient, not necessary. In particular, the
current pass does not combine proofs through a retained mixed-port junction,
transformer, switch or earth-connected bus, even when a broader identity might
exist. Arbitrary meshed-region reductions and full common-mode voltage
elimination require separate proofs.

## 4. Local linear elimination with retained observations

Let the current solver coordinates be ``y`` after any conductor specialization,
with the original physical state represented by ``z=Ry``. A defining equality
with a unit pivot can be written

```math
\alpha y_j + a^T y_{-j}=0,\qquad \alpha\in\{-1,1\}.
```

Substitution ``y_j=-a^Ty_{-j}/\alpha`` gives a reconstruction ``y=T\widehat y``.
Every remaining equality, inequality and objective is evaluated at
``z=RT\widehat y``. The defining equality alone is omitted. On its zero set,
dropping coordinate ``j`` and applying ``T`` are inverse maps; hence feasible
states and objective values correspond in both directions. This is an
algebraic equivalence statement, not a global optimality or numerical-speed
claim. Implementation uses sparse rows and unit pivots, with no small-pivot
tolerance or dense network nullspace.

For an impedance load coil, ``I-YU=0`` has unit coefficient on ``I``. Eliminating
that current is valid for zero, signed and complex admittance, including the
declared pure-Z ZIP and exponent-two cases. The current and power observations
remain ``I=YU`` and ``S=U\overline{YU}``. No division by ``Y`` occurs, and no
otherwise free delta-generator or inverter circulation is eliminated.

For a device-free, ungrounded degree-two bus between unshunted lines, conductor
KCL expresses one incident line's current through the other. The chosen line's
KVL then expresses the intermediate voltages through its retained neighbour's
voltages and the surviving currents. The required pivots are current/voltage
incidence coefficients, not impedance entries; even a zero or singular series
impedance needs no inverse. Terminal permutations and reversed line orientation
are taken from the actual assembled rows. The argument is local and remains
valid in a mesh. Distinct neighbouring buses and complete intermediate terminal
maps are required by this implementation.

Without conductor specialization, this removes ``2m`` complex coordinates and
equalities per selected ``m``-conductor bus: ``m`` currents and ``m`` voltages.
Where a conductor certificate already removed one current coordinate and KCL
equation, the additional removal is ``2m-1``. The two passes operate on composed
maps and never discharge the same equality twice. Only nonadjacent buses are
selected in one sorted pass, keeping substitutions local to retained boundaries.
Charged pi sections and device/ground boundaries are retained. No assertion
about positive dissipation is needed for these algebraic substitutions.

Physical observations are not removed. Intermediate phase/neutral/sequence
voltage bounds and every segment's endpoint current/apparent-power limits are
compiled on ``RT\widehat y``. Reconstruction performed only after solving
would not preserve those operating domains. Supplied-point validation encodes
the original full observations first and then verifies reconstruction; an
inconsistent eliminated current or voltage cannot be silently repaired.
The same argument preserves fixed equipment constraints and supported demand/
dispatch updates, provided their changes do not alter the defining linear laws.

## 5. Implementation and evidence map

| Responsibility | Implementation | Validation |
|:--|:--|:--|
| Exact circuit, maps and endpoint quantities | `src/formulations/ivr_electrical.jl` | manufactured SI states; component/OpenDSS tests |
| Power products, operating bounds, objectives and updates | `src/formulations/ivr_nlp.jl`, `src/formulations/ivr_loads.jl` | fixed-state negative-bound tests; fresh/reused comparisons |
| Local impedance/series elimination | `src/compilation/ivr_elimination.jl` | `test/ivr_elimination_tests.jl`: bidirectional physical points, retained bounds, modes, meshes, zero impedance and boundary refusals |
| Local difference identities | `src/compilation/conductor_difference.jl` | `test/compiler_algebra_tests.jl` |
| Applicability, projection and reconstruction | `src/compilation/ivr_structure.jl`, `src/compilation/ivr_regions.jl` | `test/compiler_network_tests.jl`, `test/compiler_region_tests.jl` |
| Supplied-point evaluation of the actual NLP | `src/validation/ivr_nlp.jl` | both mapping directions; deliberately perturbed states |
| Independent SI equations and assessed limits | `src/validation/physical.jl` | separate decoding and residual evaluation |

`ivr_nlp_point_report` evaluates the compiled model; it is not independent of
that model's equations. `physical_residuals` independently evaluates the declared
SI circuit and records unassessed dimensions. Neither establishes global
optimality or universal external-schema coverage. See [verification](verification.md)
for dated regression evidence and [the runnable tutorial](tutorial_exact_ivr.md)
for analytical checks, deliberately violated bounds and explicit fallback.
