# Exact row-unit controls for retained KKT systems

The [native KKT study](ivr_native_kkt.md) identified additional automatic NLP
scaling on 897 phase-to-neutral lower-voltage bounds in broad lifting. An exact
change of coordinates lets us remove that scaling from a retained linear system
while holding the objective scale, physical state and Newton direction fixed.
This is a control for subsequent numerical experiments, not a new optimization
run or evidence that either set of units is faster.

## Coordinate transformation

Let ``R_c,R_d`` be the current positive diagonal NLP row scales and
``\widehat R_c,\widehat R_d`` the desired scales. Define
``A_c=\widehat R_cR_c^{-1}`` and ``A_d=\widehat R_dR_d^{-1}``.
Primal variables ``x`` and the objective scale remain unchanged. The slack and
dual coordinates change as

```math
\widehat s=A_ds,\qquad
\widehat y_c=A_c^{-1}y_c,\qquad
\widehat y_d=A_d^{-1}y_d.
```

For a direction ordered as ``q=(\Delta x,\Delta s,\Delta y_c,\Delta y_d)``,
let ``T=\operatorname{diag}(I,A_d^{-1},A_c,A_d)``. Then

```math
q=T\widehat q,\qquad
\widehat K=TKT,\qquad
\widehat b=Tb.
```

Consequently, ``Kq=b`` if and only if ``\widehat K\widehat q=\widehat b``.
This positive diagonal congruence preserves symmetry, rank and inertia in exact
arithmetic. It does not generally preserve eigenvalues or a normwise condition
number. It leaves the slack/inequality coupling equal to ``-I``.

The derivative blocks become ``\widehat J_c=A_cJ_c`` and
``\widehat J_d=A_dJ_d``. The Hessian stays unchanged: each rescaled row's
curvature is multiplied by its inversely rescaled multiplier. The complete
slack and dual diagonal blocks transform as

```math
\begin{aligned}
\widehat D_s &= A_d^{-2}(\Sigma_s+\delta_sI),\\
\widehat D_c &= -\delta_c A_c^2,\\
\widehat D_d &= -\delta_d A_d^2.
\end{aligned}
```

Keeping the old scalar regularization in these blocks would generally define a
different linear system. The ``x`` diagonal and its regularization remain fixed.
For an internal slack-bound distance ``t`` and multiplier ``v``, the corresponding
row ratio ``a>0`` gives ``\widehat t=at``, ``\widehat v=v/a`` and therefore

```math
\widehat t\widehat v=tv,\qquad
\frac{\widehat v}{\widehat t}=\frac{1}{a^2}\frac{v}{t}.
```

For example, replacing an old row scale of 0.8 by 1 gives ``a=1.25``.
The slack distance increases by 25%, its multiplier becomes 80% of its old
value, and its barrier curvature becomes 64% of its old value. The physical
bound and complementarity product are unchanged. Scaling only the Jacobian
would miss that curvature change.

Both the complementarity product and the transformed barrier curvature can thus
be checked using native states, including states away from centrality.

## Residuals and backward error

With ``r=Kq-b``, the transformed residual is ``\widehat r=Tr``.
Its unweighted maximum norm may change solely because its units changed.
A componentwise backward error provides a useful invariant control:

```math
\eta_i=\frac{|r_i|}{(|K||q|+|b|)_i}.
```

Use zero for a zero numerator and denominator. Because ``T`` is positive,
``|\widehat K||\widehat q|+|\widehat b|=T(|K||q|+|b|)`` and hence
``\widehat\eta_i=\eta_i`` in exact arithmetic. The implementation accumulates
repeated sparse entries and combines the Hessian and primal diagonal before
taking absolute values. Otherwise cancellations could give a different metric.
This is neither Ipopt's complete primal-dual refinement ratio nor a condition
estimate.

## Calibration and frozen replay

`examples/ivr_kkt_row_units.py` applies the transformation to the restricted
native KKT representation. It copies its inputs and refuses nonpositive,
nonfinite or unrepresentable scales. The small regression model has two primal
variables, two slacks, one equality and two inequality multipliers. Independently
assembled dense matrices and Gaussian elimination verify solutions before and
after nonuniform row changes. Additional checks exercise nonzero regularization,
duplicate entries, diagonal cancellation and deliberately inexact directions.

The retained-system replay uses every native call at the 13 previously selected
states, without additional optimization. Target equality and inequality NLP row
scales are one. Powers-only cases are identity controls; broad cases remove the
897 extra LV bound scales. Each call checks three deterministic dense probe
vectors, reversal, mapped RHSs and native directions, residual covariance and
componentwise backward error. Native bound-distance/multiplier checks additionally
verify complementarity and curvature. The selection and acceptance tolerances
were recorded before replay; the later full backward-error-vector check strengthens
the initial maximum-only check on the same systems.

| Ordinary currents | Lifting | States | Systems | Maximum normalized action discrepancy | Maximum normalized bound discrepancy |
|:---|:---|---:|---:|---:|---:|
| Explicit | Powers | 3 | 18 | 0 | 0 |
| Explicit | Broad | 3 | 6 | ``1.42\times10^{-14}`` | ``4.87\times10^{-16}`` |
| Eliminated | Powers | 4 | 27 | 0 | 0 |
| Eliminated | Broad | 3 | 7 | ``1.42\times10^{-14}`` | ``4.87\times10^{-16}`` |

The action discrepancy divides each entry by ``\max(1,|a|,|b|)``. Residual
covariance uses the corresponding matrix-action/RHS magnitude, with a floor of
one, to avoid normalizing by an almost-zero residual. All 58 systems pass.
The mapped directions on these large cases are **not independently refactorized**.
The maximum absolute difference between corresponding componentwise backward
errors is ``2.46\times10^{-16}`` (rounded upwards). For all 13 broad-lifting
calls, the largest backward-error component belongs to an unchanged row.
That observation does not rule out an influence of scaled rows on a fresh
factorization: pivot choices and propagated roundoff can affect other rows.

The selected broad systems have zero regularization in the blocks affected by
row scaling. Consequently there is no regularization difference in this sample;
the nonzero case is covered by the independent small calibration. This observation
does not establish that regularization is irrelevant at other states.

## Reproduction and next intervention

From a repository-root Python session, after parsing a native call:

```python
import sys
sys.path.insert(0, "examples")
from ivr_kkt_row_units import audit_call, change_units, coordinate_map, map_vector

# call is one entry from ivr_native_kkt.calls(selected_direction_text).
k = call["matrix"]
nx, ns, nc, nd = k["dimensions"]
target_c, target_d = [1.0] * nc, [1.0] * nd
report = audit_call(call, target_c, target_d)
assert report["passed"]
t = coordinate_map(k, target_c, target_d)
new_k = change_units(k, target_c, target_d)
new_rhs = map_vector(call["rhs"], t)
if call["solution"] is not None:
    new_direction = map_vector(call["solution"], t, inverse=True)
```

Run the calibration with
`python3 -m unittest discover -s test -p 'test_ivr_kkt_row_units.py'`.
No additional Python package is required. The experiment driver, JSON audits,
input hashes, handover and roadmap remain outside Git in `KKT_ROW_UNITS_20261007`;
the original native archive is retained unchanged.

This control makes a subsequent matched-state factorization comparison possible.
It does not yet test numerical factorization, pivoting or iterative refinement
under the new units. A nonlinear row-scaling intervention also needs independently
verified objective scaling and internal initial states. Disabling all NLP scaling
alone is not a clean row-only control because it can change the objective scale.
Slack initialization, absolute tolerances, regularization and line-search decisions
can also change the nonlinear path. Preserve those distinctions in reporting.
Timing remains deferred, and no formulation option or recommendation changes.

The [fresh-factorization study](ivr_kkt_factorization.md) independently factors
the paired systems with automatic preprocessing and with a common effective
ordering and solver scaling disabled. It reports accuracy and explicit refinement
separately from optimizer timing.
