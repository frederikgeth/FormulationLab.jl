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

The additive `:passive_chains` policy extends this argument by induction.
Suppose ``z=R_k y_k`` is already exact on the previously omitted linear rows.
Resolve a surviving equation in ``y_k`` and select an as-yet retained coordinate
with coefficient exactly ``+1`` or ``-1``. The elementary map ``T_k`` gives
``R_{k+1}=R_kT_k`` and an inverse retained-coordinate projection on that equation's
zero set. Every new substitution references only coordinates retained at its
creation. Dependencies on subsequently eliminated coordinates therefore follow
the elimination order and cannot form a directed cycle. Induction establishes
the composed inverse maps and feasibility/objective correspondence, regardless
of whether the original graph has a cycle.

For each bus transaction, only surviving incident-line equations are candidates;
previously omitted rows are never used again. The implementation requires all
local current and voltage targets to be eliminated and rolls back every newly
introduced substitution if a pivot or optional support check fails. KCL and KVL
rows are omitted only after the complete transaction succeeds. The original
sorted nonadjacent policy remains available as `:passive`; `:passive_chains`
tries the next surviving incident line after rejection. This is a sufficient,
order-dependent certificate, not a maximality result or a graph contraction.
Longer composed expressions can increase coefficient cancellation and derivative
coupling; algebraic exactness does not promise better floating-point conditioning.

Physical observations are not removed. Intermediate phase/neutral/sequence
voltage bounds and every segment's endpoint current/apparent-power limits are
compiled on ``RT\widehat y``. Reconstruction performed only after solving
would not preserve those operating domains. Supplied-point validation encodes
the original full observations first and then verifies reconstruction; an
inconsistent eliminated current or voltage cannot be silently repaired.
The same argument preserves fixed equipment constraints and supported demand/
dispatch updates, provided their changes do not alter the defining linear laws.

### 4.1. Conservative selection by operating-bound support

Let ``R`` be the current reconstruction and ``RT`` the tentative map after a
local unit-pivot elimination. For a bound on ``|az|`` define
``w(R)=|\operatorname{supp}(aR)|``. For a bound on
``|(az)\overline{(bz)}|`` use the cardinality of
``\operatorname{supp}(aR)\cup\operatorname{supp}(bR)``, or zero if either
factor vanishes. The optional bound-support policy accepts a candidate only if
``w(RT)\leq w(R)`` for every affected bound. These widths count complex
coordinates before splitting into real and imaginary parts.

The policy decides whether to apply an already-proved equivalence; it changes
no bound or feasibility condition. Rejecting a candidate restores its original
coordinates/equalities. Bus-voltage fields use the same row visitor as bound
compilation, and component limits use the assembler's existing records.
For the nonadjacent policy, only intermediate voltage coordinates and one
incident line's current coordinates change. In the chain policy, earlier
reconstruction rows can also change through composition, so the selector scans
all original voltage and physical current/apparent-power bound records. A
zero-impedance first substitution can preserve an earlier bound's support, while
a subsequent nonzero-impedance substitution expands it. The latter must be
rejected even if the current bus has no bounds. Device boundary voltages and
device-current coordinates remain retained.

Support cardinality is a deliberately limited proxy. Equal widths can connect
different coordinates; coefficient cancellations, repeated derivative entries,
fixed-variable removal, quartic power limits and factorization ordering prevent
interpreting this test as a bound on global Hessian/KKT fill or runtime. Actual
derivative structures and measured solves must be reported independently.

## 5. Invertible finite-ground scaling

After reduction, write the physical state as ``z=Ry`` with projection ``y=Pz``.
For selected free physical voltage coordinates, choose a finite real scale
``s_j\geq1`` from the largest one-terminal shunt admittance magnitude in per unit.
Let ``D=\operatorname{diag}(s_j)`` and ``w=Dy``. Then

```math
z=RD^{-1}w,\qquad w=DPz.
```

Since ``D`` is nonsingular, this changes neither the feasible physical states
nor objective values. Every bound and observation is composed with ``RD^{-1}``.
For a circuit row ``a^Tz=0``, nonzero row normalization uses
``\|a^TRD^{-1}\|_2``; identically cancelled rows use divisor one. This is a
numerical equivalence policy, not another dimension reduction. The physical
ground law remains ``I_g=Y_gV_g`` with its finite complex admittance.

For example, in ``Y_{g,pu}V_{g,pu}+\sum_k I_{k,pu}=0``, normalizing by a large
``|Y_{g,pu}|`` makes a finite current residual appear small. Choosing
``w=|Y_{g,pu}|V_{g,pu}`` gives a unit-magnitude ground coefficient before row
normalization. The corresponding current residual is no longer suppressed by
the original admittance magnitude. Floating-point accuracy and solver acceptance
still depend on the remaining circuit and must be checked in physical units.

Only retained singleton physical voltage coordinates are eligible; prescribed
and ideal-ground voltages are excluded. Scalar shunts select the scale even if
other circuit contributions share the terminal, but no general multi-terminal
shunt, transformer-ground or global equilibration policy is implied.

### Regional admittance units

The original `ground_scaling=:voltage` chooses ``s_g`` from global admittance
units ``|Y|V_b^2/S_b``. The additional `:regional_voltage` policy uses
``|Y|V_r^2/S_b``, where ``V_r`` follows the same nominal-base graph and fallback
rules as transformer scaling. It uses the same eligibility checks and maximum
over separate shunts, with a lower multiplier of one. This base selection also
operates when transformer coordinate scaling is off.

When nominal coordinates are enabled, let ``d_v=V_b/V_r``. The final ground
coordinate is ``w=s_g d_v V_{pu}=s_g V/V_r``. If a single shunt supplies the
regional multiplier and it exceeds one, then

```math
w=\frac{|Y|V_r^2}{S_b}\frac{V}{V_r}
 =\frac{|Y|V}{S_b/V_r}.
```

Thus its magnitude is the ground-current magnitude in local current units.
The complex admittance phase remains in the physical ground law. In contrast,
the old global multiplier followed by nominal voltage scaling differs by
``(V_b/V_r)^2`` when both multipliers exceed one. Both mappings are invertible;
this ratio describes coordinates, not a physical circuit error. For 0.5 S at
230 V behind an 11 kV source with ``S_b=10`` kVA, the multipliers are 2.645 and
6050. Fixed-source values, bounds, outputs and model updates continue through
the complete inverse map. No solver improvement follows from this identity
alone; retain matched numerical controls and independent SI checks.

## 6. Exact lifted definitions and local block substitutions

For a physical complex power ``s(y)=u(y)\overline{j(y)}``, introduce real
auxiliaries ``p,q`` and impose

```math
p=\Re s(y),\qquad q=\Im s(y),\qquad p^2+q^2\leq\bar s^2.
```

Projection onto ``y`` and the unique extension
``y\mapsto(y,\Re s(y),\Im s(y))`` give inverse maps between feasible sets.
The objective and original physical observations retain their original meaning.
Where ``u,j`` are affine, the defining equations are quadratic and the lifted
limit is quadratic; direct substitution produces a fourth-degree inequality.
A further affine definition ``w=ay`` can localize a repeatedly bounded
observation. This is an exact extended formulation, not a convex relaxation.
It can increase linear-system size despite simplifying nonlinear expressions.

For an affine observation ``u(y)=c+Ay``, the support policy counts the union of
nonzero real-variable coefficients in its real and imaginary parts. Lifting only
when this count exceeds a chosen threshold changes the representation of bounds,
not the feasible set. If two observations have exactly equal ``c`` and ``A``,
one auxiliary definition serves both. Each original constraint remains attached
to that expression, including distinct lower/upper limits. This quotient of
identical definitions retains the unique extension of physical points. Merely
similar coefficients, opposite signs, equality only on circuit solutions or a
similar sparsity pattern do not satisfy the `:exact` identity test.
The policy uses exact floating-point coefficient equality and can miss
mathematically equivalent rows with different rounding histories. Such misses
retain additional exact definitions; they do not justify approximate merging.
Neither support nor derivative-entry counts measure numerical KKT factor fill.

For example, an unloaded, unshunted degree-two junction can have oriented line
currents ``j_1=j_2`` after KCL substitution. If their composed affine rows match
exactly and exceed the lifting threshold, one definition ``w=j_1=j_2`` can serve
both original ratings ``|w|\leq\bar i_1`` and ``|w|\leq\bar i_2``. Both
inequalities remain, even when their limits differ. A shunt changes the identity
to ``j_1-j_2=j_{\mathrm{sh}}`` and generally prevents this reuse. Orientation
may instead give ``j_1=-j_2``; `:exact` retains separate definitions, whereas
`:signed` can reconstruct the second observation as the negative of the first. These examples explain why network topology
alone is insufficient to predict the number of reusable observations.

### Certified real proportional observation sharing

Let ``u_j(y)=c_j+A_jy`` be complex affine observations of the same real solver
coordinates. If a finite nonzero real scalar ``\alpha_j`` satisfies
``c_j=\alpha_j c_r`` and ``A_j=\alpha_j A_r`` coefficient by coefficient, define
only ``w=c_r+A_ry`` and replace every use of ``u_j`` by ``\alpha_j w``.
For each original feasible ``y`` there is exactly one ``w``; conversely the
representative defining equality reconstructs every original observation.
This is a unique graph extension, with no added physical freedom.

Each original bound remains on its reconstructed expression. For example,
``|u_j|^2\leq L_j^2`` becomes ``\alpha_j^2|w|^2\leq L_j^2`` without deleting
other ratings. A native complex power ``v\overline{u_j}`` becomes
``\alpha_j v\overline{w}``; its sign must not be discarded merely because a
current-magnitude bound is sign invariant. The point encoder assigns the
representative before any dependent power auxiliary, preserving starts and
physical SI outputs. CP/dispatch updates do not alter the certified affine rows.

The implementation normalizes the complete ordered real coefficient tuple,
including both constants, using exact `Rational{BigInt}` values of the stored
floating coefficients. Equal normalized tuples identify a real proportional
class. A second exact check requires that the reconstruction ratio be represented
without rounding by a finite nonzero `Float64`. For example, a row ``u`` does
not reuse the first representative ``3u`` through a rounded factor ``1/3``;
it keeps a new definition. A later ``2u`` can reuse that new representative.
The `:signed` subcase restricts multipliers to ``\pm1``. First-representative
selection can affect auxiliary counts and conditioning; no optimal grouping
or speed improvement is guaranteed. Constants are not freely translated,
and complex rotations/conjugation are not included. See [methods and tests](ivr_affine_sharing.md).

For charged-section elimination, partition a selected set of surviving linear
equations into targeted coordinates ``x`` and retained coordinates ``y``:

```math
A x+B y=0,\qquad x=-A^{-1}B y.
```

If ``A`` is nonsingular, dropping ``x`` and reconstructing it by this formula
are inverse maps on the selected equations' feasible set. Substitution into
**every** retained equation, objective, observation and operating limit proves
conditional OPF equivalence. Sequential blocks preserve this property by
induction: each block targets only currently retained coordinates. The formula
is implemented by factorization/solve, not by forming an inverse. It uses
current-voltage KCL/KVL rows, so it does not require invertible line impedance.

The implementation equilibrates each target row by its largest absolute target
coefficient. It rejects incomplete target sets, zero target rows, nonfinite
coefficients, condition estimates above ``10^8`` and relative solve residuals
above ``10^{-12}``. These conservative gates decline uncertain substitutions;
they do not replace independent SI residual checks. No free mode is assigned a
minimum-norm value, and no small coefficient is discarded. Rejected attempts
retain the original circuit. Accepted blocks report their numerical evidence.

Charged sections generally cannot represent a flat, zero-current start: shunt
currents enter KCL. Matched timing experiments therefore encode one shared
unloaded linear-circuit point in all models, including every lifted definition.
This point is used only for initialization, not as an additional operating law.

### A bounded component selection policy

Let ``E`` be the set of original buses accepted for series elimination and let
``G[E]`` be the induced subgraph of original line connections. Before accepting a
new bus ``b``, form the union of ``\{b\}`` and the already accepted components
containing its neighbours. Accept only if this union has at most ``K`` members
and the preceding block certificate and bound-support checks accept. Commit the
component union after the substitution succeeds. All other components remain
unchanged, so induction proves that every component of ``G[E]`` has at most
``K`` vertices. Set union counts a component touched by both neighbours once.
A declined step changes neither ``E`` nor its coordinate map.

At each step the cap can decline a candidate, but every accepted step must still
pass the block certificate in the current coordinates. Different decisions can
alter later pivot choices, so accepted bus sets need not be nested as the cap
changes. The same nonsingularity and complete-composition argument establishes
conditional OPF equivalence; graph cardinality is not the algebraic certificate.
No interior voltage, endpoint current/apparent-power limit, objective or physical
output is dropped. Conductor-region maps and subsequent device substitutions can
couple more distant coordinates, so the graph cap does not prove a corresponding
support-width or factorization-fill bound. See [bounded hybrid condensation](ivr_hybrid.md).

## 7. Transformer coil-current graph substitution

For the implemented fixed two-sided winding stamps, let ``j_f`` and ``j_t``
denote currents into the from/to coils. Current balance is

```math
j_f+R^Hj_t=0.
```

The coefficient of ``j_f`` is the identity. Thus ``j_f=-R^Hj_t`` defines a
unique extension of every retained ``j_t``, even when ``R`` is rectangular or
leakage is zero. Substitute this expression into the retained voltage equations,
bus KCL, terminal and coil observations, operating bounds and objective. Every
original feasible point projects to a reduced feasible point; conversely, each
reduced feasible point extends uniquely in the eliminated currents and satisfies
the removed current-balance equations. These maps preserve feasible objective
values. This is a graph substitution, not an assertion that an OPF solution is
unique or globally optimal.

The implementation composes with earlier coordinate maps and accepts only
surviving unit pivots on recorded from-side current coordinates, without dividing
by leakage or a singular incidence matrix. A failed device substitution rolls
back all its tentative changes. Remaining to-side currents retain any delta
circulation; regulator bond and ground currents are separate states/observations.
In particular, equal delta-coil current increments can leave terminal currents
unchanged while changing individual coil limits. Those limits must still be
evaluated. The independent circulation test exercises exactly this distinction.

`device_elimination=:transformer_currents` currently covers the ordinary fixed
transformer/regulator stamp, not the separate multiwinding stamp. Reconstruction
and supplied-point checks audit removed equations and original channels. Exact
algebra does not guarantee smaller expression support, better conditioning or
faster Ipopt solves; the [performance guide](ivr_performance.md) separates these
questions from equivalence.

## 8. Local voltage/current coordinates and row normalization

Let the retained global per-unit state be ``x`` and choose a finite positive
factor ``d_j`` for every complex coordinate. With ``y_j=d_jx_j``, compose the
existing projection ``P`` and reconstruction ``R`` as

```math
P_{\mathrm{new}}=DP,\qquad R_{\mathrm{new}}=RD^{-1}.
```

Thus ``P_{\mathrm{new}}R_{\mathrm{new}}=I`` whenever ``PR=I``. Every retained
physical constraint and observation is evaluated through the same reconstruction,
so feasible physical points and objective values are preserved. A prescribed
source coordinate ``x_k=a y_j=v_k`` fixes ``y_j=v_k/a``; fixing it to ``v_k``
would be incorrect when ``a\ne1``.

For a local voltage base ``V_r`` and common power base ``S_b``, choose
``d_V=V_b/V_r`` and ``d_I=V_r/V_b``. Their product is one. The product of a
local voltage and current therefore retains the original power base. For the
scalar ideal relation ``u_t=r u_f``, the solver relation is
``\hat u_t=r(V_f/V_t)\hat u_f``. Choosing compatible nominal bases makes the
nominal gain order one without deleting tap deviations or connection matrices.
An 11 kV/415 V interface can then have phase voltages near one on both sides,
while reconstructed quantities remain SI. This is a coordinate change, not a
voltage constraint or network reduction.

For an equality ``a^T R_{\mathrm{new}}y=0``, division by its finite positive
coefficient norm is another exact transformation. An identically cancelled row
uses divisor one. The independent row policy does not rescale nonlinear rows by
near-zero gradients of inactive limits. Positive variable scales preserve
feasibility but do not guarantee improved condition numbers, reduced factor fill
or lower Ipopt time. Different regional power bases would require additional
current-balance and objective/dual scaling contracts and are outside this policy.

### Explicit regional current bases and independent objective scaling

Let ``S_b,V_b`` denote assembly bases and let ``S_r,V_r`` denote the declared
regional current-unit power base and nominal voltage base. For physical voltage
``V`` and current ``I``, define

```math
y_V=V/V_r=(V_b/V_r)V_{pu},\qquad
y_I=I/(S_r/V_r)=(V_r/V_b)(S_b/S_r)I_{pu}.
```

With finite positive factors, this is an invertible diagonal transformation.
Current factors are classified from device observation rows; coordinates with
mixed or unclassified factors retain their earlier units with a reason. No
transformer current equation is rewritten by assuming a new turns ratio. The
existing physical stamp is composed with the full inverse map, automatically
retaining every needed power-base ratio.

For a voltage/current pair sharing those local bases,

```math
V_{pu}\overline{I_{pu}}=(S_r/S_b)y_V\overline{y_I}.
```

The existing reconstruction implements this identity. Regional current seeds
do not change generator P/Q or lifted-power units; their definitions are not
replaced by an unweighted local product. The separate `generator_power_bases`
option uses dispatch coordinates ``P_g/S_g,Q_g/S_g`` with exact defining
equalities ``\operatorname{Re}(V_{pu}\overline{I_{pu}})=(S_g/S_b)\widehat P_g``
and the corresponding reactive equality. It changes dispatch columns while
retaining assembly-unit rows; physical boxes divide by ``S_g``. Lifted powers
use ``S_b`` by default, or the separately declared ``S_l`` under
`lifted_power_base`. The lift satisfies
``(S_l/S_b)(\widehat P+\mathrm{i}\widehat Q)=V_{pu}\overline{I_{pu}}``;
bounds and objective observations compose this inverse factor. Exact generator
power sharing may replace this extra pair with existing dispatch variables
when both original voltage and current rows match. The generator defining
equalities then supply the same identity; its original capability limit remains. Ground multipliers also retain their separately
declared policy and common ``S_b``. Thus `current_power_bases` isolates one
coordinate intervention instead of claiming that every NLP variable is in a
regional power unit. Explicit seeds propagate only over lines and closed
switches; transformers separate these current-base regions.

For a physical objective ``f``, the solver receives ``f/\sigma``, with
``\sigma=S_b`` under the legacy default. An explicit `objective_scale` sets
``\sigma`` independently. Supplied-point reports and solve results recover
``f=\sigma f_{solver}``; generator price updates multiply their coefficients by
``S_g/\sigma`` (where ``S_g=S_b`` by default), in addition to the W-to-kW
conversion. Explicit power objectives likewise recover SI before evaluating terms. A positive divisor preserves
mathematical minimizers, but changes numerical stopping behavior. A common-power
base experiment should therefore hold ``\sigma`` fixed or explicitly report its
change. Neither a voltage level nor this algebra establishes an optimal power
base; physical loading/rating differences motivate candidates that still require
controlled timing and original-unit feasibility checks.

## 9. Implementation and evidence map

| Responsibility | Implementation | Validation |
|:--|:--|:--|
| Exact circuit, maps and endpoint quantities | `src/formulations/ivr_electrical.jl` | manufactured SI states; component/OpenDSS tests |
| Power products, operating bounds, objectives and updates | `src/formulations/ivr_nlp.jl`, `src/formulations/ivr_loads.jl` | fixed-state negative-bound tests; fresh/reused comparisons |
| Local impedance/series elimination | `src/compilation/ivr_elimination.jl` | `test/ivr_elimination_tests.jl`: bidirectional physical points, retained bounds, modes, meshes, zero impedance and boundary refusals |
| Charged blocks and exact lifting | `src/compilation/ivr_elimination.jl`, `src/formulations/ivr_nlp.jl` | `test/ivr_lifting_blocks_tests.jl`: inverse maps, omitted equations, lifted definitions, bound witnesses, refusal/rollback and reuse |
| Composed affine sharing and support thresholds | `src/formulations/ivr_nlp.jl` | `test/ivr_observation_policy_tests.jl`: offsets, exact coefficient identity, signs, sequential starts, physical equivalence and updates; extended negative-bound tests |
| Certified signed/proportional sharing | `src/formulations/ivr_nlp.jl` | `test/ivr_affine_sharing_tests.jl`: exact rational certificates, arbitrary-coordinate graphs, real-factor refusals, native powers, transformer and interior-bound witnesses, updates and SI exports |
| Matched structural experiments | `examples/benchmark_ivr_lifting_blocks.jl` | `test/ivr_lifting_study_tests.jl`: complete shared starts, analytical 920 W midpoint case, active limits and transformer fixtures |
| Optional series selection | `src/compilation/ivr_elimination.jl`, shared `_ivrn_each_bus_limit` visitor | `test/ivr_series_selection_tests.jl`: all voltage-bound families, apparent-power rows, rollback, reconstruction, ground scaling and updates |
| Transformer-local coordinate/row scaling | `src/compilation/ivr_scaling.jl` | `test/ivr_transformer_scaling_tests.jl`: independent SI states, large ratios, fixed sources, original bounds, map composition and fallback |
| Finite-ground coordinate/row scaling | `src/compilation/ivr_scaling.jl` | `test/ivr_ground_scaling_tests.jl`: analytical finite-ground states, current-error witnesses, retained bounds, scope and reuse |
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
