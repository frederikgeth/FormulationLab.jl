# Residual certificates for implied electrical equations

## Question and scope

Removing an equation does not give it an independent solver tolerance. Its
residual follows from reconstruction, from retained equations, or from both.
The [physical circuit-row trace](ivr_circuit_residuals.md) measures these residuals;
`examples/ivr_implied_residual_certificate.jl` additionally constructs explicit
identities and componentwise bounds. It never solves, repairs or changes a model.

The certificate is exact **for the stored coefficients**: each finite coefficient
in the original electrical rows, reconstruction and SI multiplier is converted
to a rational number without approximation. Matrix products, cancellations and
bound sums then use rational arithmetic. This includes defects hidden by a
Float64 product that rounds to zero. It does not recover coefficients before
assembly rounding or prove equivalence to an exact physical network description.
Independent original-SI audits remain necessary.

This diagnostic covers omitted linear electrical equations and KCL. It requires
a complete physical-row catalogue. It does not certify nonlinear load laws,
power definitions, operating bounds or fixed-source constraints. Certificates
must be evaluated using native coordinates from their corresponding build.

## An explicit dependence identity

Let ``a`` be an omitted original row, ``R`` its stored reconstruction, ``y`` a
native complex state and ``s>0`` the row's stored SI multiplier. For selected
retained rows ``a_j`` with their actual stored normalization divisors ``d_j``,
define

```math
b=aR,\quad b_j=a_jR,\quad \eta_j=b_jy/d_j,
\qquad \delta=b-\sum_j c_j b_j/d_j.
```

The identity

```math
r_{\mathrm{SI}}=s\,aRy
 =s\left(\sum_j c_j\eta_j+\delta y\right)
```

holds exactly for the stored numbers. Dependencies are chosen from the recorded
removal reason, without a rank threshold, least-squares fit or pseudoinverse:

| Removal reason | Retained dependencies | Coefficients |
|:--|:--|:--|
| Conductor-specialization KCL | Other retained terminal KCL rows at the same bus | ``c_j=-d_j`` |
| Passive, impedance-current or transformer-current substitution | None | Empty sum |
| Empty original row | None | Empty sum |

The first choice expresses the certified zero-sum conductor connection. If
another same-bus row was also removed, it is **not** used as a retained constraint:
its contribution remains in ``\delta``. Substitution rows should have zero
composed coefficients in ideal arithmetic, but rounded reconstruction can leave
a defect. The implementation retains every nonzero rational coefficient of
``\delta``. A large defect produces a large bound; it is never silently discarded.
No source constraint is needed or inferred by these particular identities.

## Componentwise SI bounds

Write ``\delta_k=\alpha_k+\mathrm{i}\beta_k`` and
``y_k=u_k+\mathrm{i}v_k``. At the supplied state, define

```math
E_r=s\sum_k(|\alpha_k||u_k|+|\beta_k||v_k|),\qquad
E_i=s\sum_k(|\beta_k||u_k|+|\alpha_k||v_k|).
```

The dependency coefficients above are real. The observed bounds are therefore

```math
|\Re r_{\mathrm{SI}}|\le s\sum_j|c_j||\Re\eta_j|+E_r=B_r,
\qquad
|\Im r_{\mathrm{SI}}|\le s\sum_j|c_j||\Im\eta_j|+E_i=B_i.
```

If both components of every retained residual satisfy a supplied target
``\tau_j``, a separate conditional bound follows by replacing their magnitudes
with ``\tau_j``. Targets can be common or row-specific. They are never read from
Ipopt settings or assigned to omitted rows. `retained_targets_satisfied` reports
whether the exact stored-row residuals at this state actually meet those targets.

Each component bound is converted to Float64 **upward**, including positive
underflow. The reported modulus bound is ``B_r+B_i``, a conservative bound on
the Euclidean modulus that avoids a rounded square root. Exact zero defects are
distinguished from nonzero defects. These are bounds at the supplied state,
not uniform bounds over the feasible region: the defect term uses ``|u_k|`` and
``|v_k|`` from that state.

The normalized residuals in this identity are exact evaluations of the stored
mathematical expression ``a_jRy/d_j``. Rounded JuMP coefficient assembly and
solver evaluation can differ. Consequently an Ipopt termination message alone
does not establish the conditional premise. The existing floating/high-precision
trace quantifies some of these arithmetic differences separately.

## Tutorial: certify an already solved state

After solving a native `IVRNLPBuild` called `build`:

```julia
using JuMP
include("examples/ivr_implied_residual_certificate.jl")
I = IVRImpliedResidualCertificate
certificates = I.certificates(build) # Also available before optimization.
y = value.(build.coordinates.real_variables) +
    im * value.(build.coordinates.imaginary_variables)
observed = [I.evaluate(c, y) for c in certificates]
conditional = [I.evaluate(c, y; retained_scalar_target=1e-10)
               for c in certificates]
@assert all(r.exact_identity_verified && r.exact_enclosure_verified
            for r in observed)
```

Inspect `dependencies` to see which retained rows contribute, and compare
`inherited_components_SI` with `defect_components_bound_SI`. The returned reports
are JSON-compatible; exact normalized coefficients are strings. Internal
certificate rows retain exact rationals for further inspection. SI units remain
`:A` or `:V`, as recorded by the physical catalogue. This diagnostic export is
separate from, and does not change, the BMOPFTools-compatible solution export.

For a simple three-conductor example, suppose an omitted terminal KCL is minus
two retained KCL rows, each with ``d_j=0.2``, with ``s=10`` A and zero defect.
Targets ``\tau_1=\tau_2=10^{-10}`` imply at most ``4\times10^{-10}`` A per
component; the reported modulus bound is ``8\times10^{-10}`` A. A deliberately
infeasible native state can violate those targets. Its observed bound remains
valid, while `retained_targets_satisfied` is false.

A second regression sets a reconstructed coordinate to `Float64(1/3)` times
another coordinate. For the original row ``3z_3-z_1``, Float64 evaluation of
`3 * (1/3) - 1` is zero. Exact evaluation of those stored coefficients gives
``-2^{-54}``. The certificate retains that defect and its state-dependent SI
contribution.


## Fixed-state evidence, 7 October 2026

The study replays the native coordinates from the preceding 32-endpoint
[provenance panel](ivr_circuit_residuals.md#Complete-linear-row-provenance,-7-October-2026).
It verifies matching input networks and serialized options before rebuilding
the coordinate maps. It performs **zero new optimizer calls**. The panel crosses
8/24 four-winding units, four current/lifting representations, two nominal-unit
policies and two KCL-cap choices, with a power-tracking objective.

All **15,968 omitted-row identities and observed enclosures** pass. A separate
Python `Fraction` calculation reproduces every exported coefficient-defect bound
and conditional bound from rational coefficient strings and native states.
Every previous high-precision nested residual lies inside the new modulus bound.

| Omitted row family | Evaluations | Exactly zero coefficient defects | Largest observed modulus bound | Largest conditional modulus bound |
|:--|--:|--:|--:|--:|
| Voltage, substitution | 8192 | 0 | ``4.432\times10^{-13}`` V | ``4.432\times10^{-13}`` V |
| Current, substitution | 5728 | 2816 | ``3.199\times10^{-12}`` A | ``3.199\times10^{-12}`` A |
| Current, conductor KCL | 2048 | 2048 | ``2.540\times10^{-15}`` A | ``3.615\times10^{-8}`` A |

Maxima are rounded upward and can occur on different rows. The conditional
column uses ``\tau_j=10^{-10}`` for each retained scalar component. Exactly 1024
conductor-KCL certificates have nonempty retained dependencies, and all of these
dependencies meet that target at the archived states. The remaining 1024
conductor-KCL rows become identities after passive substitution. Their
coefficient defects and dependency sets are both empty. Target satisfaction
for dependency-free rows is vacuous; it does not certify other retained rows.

There are 4864 exactly zero coefficient defects overall. The remaining 11,104
are explicitly retained. In this panel their bounds are small enough that they
do not explain the known microampere failures. The original 30 accepted endpoints
and two rejected retained-KCL controls retain their classifications. These
results support the distinction between reconstruction defects and retained-row
normalization; they do not prove a universal conditioning guarantee or promote
a faster formulation.

The new regression checks analytical dependencies, complex defects, upward
conversion at underflow/overflow, missing or invalid targets, deliberately
infeasible states, independent high-precision nested evaluation, and 16 live
network builds spanning both nominal policies, both cap choices and all four
representations. Raw JSON reports, original-state references, source snapshots,
initial script/test errors and validation logs are retained outside Git in
`IMPLIED_RESIDUAL_CERTIFICATES_20261007`. Diagnostic costs do not enter optimizer
wall-time rankings. All existing transformations and defaults remain available.
