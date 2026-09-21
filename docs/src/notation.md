# Notation and conventions

This page defines the notation shared by the formulation documentation. It is
close to the matrix notation of Geth and Ergun's
[*Real-Value Power-Voltage Formulations of, and Bounds for, Three-Wire
Unbalanced Optimal Power Flow*](https://arxiv.org/abs/2106.06186), extended here
to arbitrary ordered terminal sets, explicit neutrals, parallel branches and
connection-aware devices.

The notation describes mathematics, not Julia storage. Code identifiers are
shown only where they prevent ambiguity.

## Typography and operators

| Symbol | Meaning |
|:--|:--|
| ``x`` | scalar; its domain is stated where needed |
| ``X`` | vector or matrix |
| ``\mathcal X`` | set |
| ``X^T``, ``X^*``, ``X^H`` | transpose, elementwise conjugate, and conjugate transpose |
| ``\operatorname{diag}(X)`` | vector containing the diagonal of ``X`` |
| ``\operatorname{Diag}(x)`` | diagonal matrix formed from vector ``x`` |
| ``X\circ Y`` | elementwise (Hadamard) product |
| ``X\succeq0`` | Hermitian positive semidefinite matrix |
| ``\operatorname{Re}(X)``, ``\operatorname{Im}(X)`` | real and imaginary parts |
| ``\mathrm j`` | imaginary unit, ``\mathrm j^2=-1`` |

The symbol ``i`` is reserved for a bus index; the imaginary unit is always
``\mathrm j``. Superscript ``H`` never means a plain transpose. Inequalities
between real vectors are elementwise. Matrix semidefiniteness is written only
with ``\succeq``.

## Sets and indices

| Symbol | Meaning |
|:--|:--|
| ``i,j\in\mathcal N`` | buses |
| ``\ell\in\mathcal E`` | physical branches; retaining ``\ell`` distinguishes parallel lines |
| ``\ell:i\to j`` | chosen orientation of branch ``\ell`` from bus ``i`` to bus ``j`` |
| ``t\in\mathcal T_i`` | ordered terminals of bus ``i`` |
| ``c\in\mathcal C_d`` | ordered coils/channels of device ``d`` |
| ``d\in\mathcal D`` | connected devices such as loads, generators, capacitors or transformers |

An orientation is a bookkeeping choice. It does not change the declared
`bus_from` ordering of ratings or the physical sign of a public endpoint
quantity. A tree used for recovery may orient a line differently from the input;
the implementation carries the necessary maps explicitly.

## Physical phasors and branch parameters

For each bus and oriented branch,

```math
U_i\in\mathbb C^{|\mathcal T_i|},\qquad
I_{\ell ij}^s\in\mathbb C^{|\mathcal T_\ell|},\qquad
I_{\ell ij}\in\mathbb C^{|\mathcal T_\ell|}.
```

``U_i`` is the ordered terminal-to-ground voltage vector.
``I_{\ell ij}^s`` is the series current oriented from ``i`` to ``j``;
``I_{\ell ij}`` is the total current entering the complete pi section at its
``i`` endpoint. The branch data are

```math
Z_\ell^s\in\mathbb C^{m\times m},\qquad
Y_{\ell ij}^{sh},Y_{\ell ji}^{sh}\in\mathbb C^{m\times m}.
```

No diagonal or symmetry approximation is implied. The physical equations are

```math
U_j=U_i-Z_\ell^s I_{\ell ij}^s,
```

```math
I_{\ell ij}=I_{\ell ij}^s+Y_{\ell ij}^{sh}U_i,
\qquad
I_{\ell ji}=-I_{\ell ij}^s+Y_{\ell ji}^{sh}U_j.
```

The endpoint complex-power matrices are

```math
S_{\ell ij}=U_i I_{\ell ij}^H,
\qquad
S_{\ell ji}=U_j I_{\ell ji}^H.
```

Their diagonals are conductor powers. The off-diagonal entries are not extra
physical power meters; they are cross-terminal products required by coupled
multiconductor equations.

## Lifted variables

The shared lifted symbols are

| Symbol | Exact rank-one definition | Interpretation |
|:--|:--|:--|
| ``W_i`` | ``U_iU_i^H`` | bus voltage Gram, in V² before scaling |
| ``W_{ij}`` | ``U_iU_j^H`` | cross-bus voltage product |
| ``S_{\ell ij}^s`` | ``U_i(I_{\ell ij}^s)^H`` | series sending voltage-current product |
| ``L_\ell^s`` | ``I_{\ell ij}^s(I_{\ell ij}^s)^H`` | series-current Gram, in A² before scaling |
| ``L_{\ell ij}`` | ``I_{\ell ij}I_{\ell ij}^H`` | total endpoint-current Gram |
| ``M`` | ``xx^H`` for a stated local or global phasor vector ``x`` | generic moment block |

When a formulation omits the superscript ``s`` in code or a result field, its
page states whether the stored line quantity is series or total endpoint
current. The mathematical documentation retains the superscript whenever that
distinction matters.

An exact lifted state has rank one. The SDP models keep the affine identities
among these products and drop selected rank constraints. Consequently a matrix
called a “moment” is a relaxation variable, not necessarily the outer product
of the returned phasor candidate.

## Device connection maps

A device ``d`` connected at bus ``i`` has a real incidence matrix

```math
D_d\in\mathbb R^{|\mathcal C_d|\times|\mathcal T_i|}.
```

Rows follow device coil order; columns are embedded in bus-terminal order. If
``J_d`` is the vector of coil currents directed from the bus into a passive
device, then

```math
U_d=D_dU_i,\qquad I_d^{term}=D_d^T J_d.
```

For a three-terminal delta in order ``(a,b,c)``, one convention is

```math
D_\Delta=
\begin{bmatrix}
1&-1&0\\
0&1&-1\\
-1&0&1
\end{bmatrix}.
```

Thus ``U_d=(U_a-U_b,U_b-U_c,U_c-U_a)`` and the bus sees ``D_\Delta^TJ_d``.
The matrix is never inverted. This preserves the physical circulating-current
degree of freedom and avoids inventing a neutral or phase-to-ground allocation.

In a local lifted block define

```math
C_d=U_iJ_d^H,\qquad K_d=J_dJ_d^H.
```

Then

```math
s_d^{coil}=\operatorname{diag}(D_dC_d),
\qquad
M_i^d=C_dD_d,
```

where ``M_i^d=U_i(I_d^{term})^H`` is the full contribution to lifted KCL.
This one identity is used for wye, delta and terminal-pair loads, generators,
capacitors and transformer winding ports.

## Sign conventions

Currents into passive components are positive. Therefore:

- load, shunt and capacitor consumption enters KCL with a positive sign;
- generator and ideal-source delivery enters with a negative sign; and
- a branch endpoint current is positive from its bus into the branch.

Complex power follows the same convention. A consuming load normally has
positive active power. An energized capacitor has negative reactive
consumption. Transformer winding currents are directed into the transformer on
every winding.

These conventions apply to model equations and relaxed powers. Public result
keys additionally document whether they report coil, terminal, series or
endpoint quantities.

## Terminal order is part of the data

Three orders must remain distinct:

1. bus moment matrices use `bus.terminal_names`;
2. component limits, costs, public currents and public powers use that
   component's `terminal_map`; and
3. coil quantities use the row order of the connection incidence matrix.

A partial or permuted `terminal_map` is therefore not normalized into bus order.
Selection matrices move between these spaces. This is essential for asymmetric
limits and costs, and for buses that contain a neutral or an unused conductor.

## Units and per-unit coordinates

BMOPF inputs and public results use SI units: volts, amperes, ohms, siemens,
watts, vars and volt-amperes. The conic formulations solve internally in
per-unit coordinates. With voltage and power bases ``V_b`` and ``S_b``,

```math
I_b=\frac{S_b}{V_b},\qquad Z_b=\frac{V_b^2}{S_b},
\qquad Y_b=\frac1{Z_b}.
```

A hat denotes a per-unit quantity only when a derivation must show the scaling,
for example ``\widehat U=U/V_b`` and ``\widehat Z=Z/Z_b``. Most formulation
pages suppress hats after stating that their equations are evaluated in the
internal coordinate system. Changing `s_base` changes conditioning, not the
physical problem. Results are converted back to SI.

## Complex and real PSD representations

For a Hermitian matrix ``M=M^{re}+\mathrm jM^{im}``,

```math
M\succeq0
\quad\Longleftrightarrow\quad
\begin{bmatrix}
M^{re}&-M^{im}\\
M^{im}&M^{re}
\end{bmatrix}\succeq0.
```

FormulationLab may submit a Hermitian cone or this real embedding depending on
the selected cone representation and solver. This is a representation choice,
not a different electrical formulation. Chordal decomposition is likewise a
PSD representation choice when the required overlaps are preserved.

## Code correspondence

| Mathematical object | Common implementation/result spelling |
|:--|:--|
| ``U_i`` | `voltage_candidate`, bus voltage coordinates |
| ``W_i`` | `voltage_moments` |
| ``S_{\ell ij}^s`` or endpoint ``S_{\ell ij}`` | `branch_power_moments`, with the page-specific convention |
| ``L_\ell^s`` | `branch_current_moments` in `BranchFlowSDP` |
| ``D_d`` | component connection/incidence map |
| ``C_d,K_d`` | local terminal/current moments |
| ``M`` | reduced, local, edge or voltage-closure moment matrix |

Always use the formulation page and result contract to disambiguate a field.
The shared letters make relationships visible; they do not imply that every
formulation stores identical matrices.
