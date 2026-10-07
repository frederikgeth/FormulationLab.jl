# Native augmented systems and bound curvature

The [callback capture](ivr_iterate_diagnostics.md) supplies model derivatives
and original TNLP primal/dual states. It does not expose Ipopt's independent
inequality slacks. Native diagnostic output supplies the missing states and an
independent matrix against which to check a reconstruction. This study uses
Ipopt 3.14.19 with MUMPS; all instrumented runs are excluded from timing.

## The matrix being checked

With internal variables ordered as ``(x,s,y_c,y_d)``, the standard augmented
system printed by Ipopt is

```math
K = \begin{bmatrix}
W+\Sigma_x+\delta_x I & 0 & J_c^\mathsf{T} & J_d^\mathsf{T} \\
0 & \Sigma_s+\delta_s I & 0 & -I \\
J_c & 0 & -\delta_c I & 0 \\
J_d & -I & 0 & -\delta_d I
\end{bmatrix}.
```

Here ``c(x)=0`` are equalities and ``d(x)-s=0`` couples the inequality functions
to independent slack variables. ``W`` is the internally scaled Lagrangian
Hessian. For lower/upper bound-selection matrices ``P_L,P_U``, positive distances
to bounds ``t_L,t_U`` and their current multipliers ``z_L,z_U``,

```math
\Sigma_x = \operatorname{diag}\!\left(
P_L(z_L\oslash t_L)+P_U(z_U\oslash t_U)\right).
```

The corresponding ``\Sigma_s`` uses the internal slack-bound distances and
multipliers ``v_L,v_U``. These definitions and block signs follow the matching
[calculated-quantities source](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpIpoptCalculatedQuantities.cpp)
and [standard augmented-system implementation](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpStdAugSystemSolver.cpp).

Two substitutions are generally invalid at intermediate states:

* ``d(x)`` cannot replace ``s`` unless their equality residual has been checked.
* ``\mu/t^2`` cannot replace ``z/t`` unless the relevant complementarity product
  satisfies ``zt=\mu``. Current multiplier values are required away from that
  centrality condition.

The public constraint-complementarity query does not solve this problem: the
[TNLP interface](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Interfaces/IpTNLP.cpp)
uses original constraint values and constraint multipliers for that report,
rather than exposing all independent internal slack states and bound multipliers.

## Native reader and verification

`examples/ivr_native_kkt.py` reads the restricted four-block layout printed at
level 10. It supports dense and homogeneous vectors, triplet matrices, explicit
positive row scaling, and the diagonal/identity blocks above. Repeated triplet
positions are summed. Unsupported column scaling, missing entries, ambiguous
bound maps and other matrix layouts are refused. Failed factorizations retain
their matrix and RHS without inventing a solution.

The checks combine separate information:

1. Model declarations identify fixed variables, free columns, equality and
   inequality rows, and bound positions. Native dimensions and callback arrays
   check the resulting maps.
2. Native Jacobian wrappers expose NLP row scales. Scaled/unscaled callback
   multipliers independently check their conversion and the objective scale.
3. Post-solve model Jacobians and Hessians supply the derivative blocks. Native
   bound distances and bound multipliers supply ``\Sigma_x`` and ``\Sigma_s``.
4. Direction-specific regularization supplies the remaining diagonals. The
   reconstructed blocks are compared with each printed native augmented matrix.
5. Native RHS/solution pairs are multiplied independently by the parsed matrix
   to record ``\lVert Kq-b\rVert_\infty``.

Entrywise discrepancies are normalized by ``\max(1,|a|,|b|)``. Each selected
matrix's row scales also match the separately printed initialization vectors.

The current scope has no additional NLP column scaling. If ``R`` is the NLP row
scaling and ``a>0`` is the objective scale, the multiplier conversion is
``\lambda_{\mathrm{unscaled}}=R\lambda_{\mathrm{scaled}}/a``. Thus, after removing
fixed columns, ``W=aH_{\mathrm{model}}`` and ``J_{\mathrm{internal}}=RJ_{\mathrm{model}}``.
The model already contains the declared physical per-unit and composed-row
conventions; this additional scaling is performed by Ipopt.

Direction regularization values are printed with seven significant digits,
whereas matrix entries have higher precision. The audit retains raw discrepancies
and a separately reported conservative allowance of ``5.1\times10^{-7}|\delta|``
on each affected diagonal entry. Derivative-block comparisons receive no such
allowance. This avoids interpreting log rounding as a reconstruction failure.

## Calibration and declared workload

The small calibration includes a removed fixed variable, asymmetric variable
bounds, both inequality directions, mixed quadratic/nonlinear curvature and an
initially violated constraint. Its independently computed analytic derivatives
and native systems check the conventions before the large-case interpretation.
In its first three states, normalized differences between ``d(x)`` and ``s``
reach 1.0; substituting one for the other would be incorrect.

The large experiment retains the four zero-reduced 333-bus exchange-tracking
profiles. Inputs, starts, objectives, bases and numerical tolerances match the
previous capture. Native verbosity changes from 7 to 10; the diagnostic CPU
ceiling increases from 30 to 300 seconds to permit verbose output. Neither is a
timing comparison. All four final endpoints pass the physical/model/objective
gates, and all 142 callback states match the earlier captures exactly.

Selected directions are iteration 0, powers-only iterations 20/22, broad
iterations 22/24, and eliminated-current powers-only iteration 15 for its recovery
episode. These are comparable declared barrier phases, **not matched physical
states**. The selection precedes the new native runs.

| Ordinary currents | Lifting | Selected states | Native augmented systems | System dimension | Maximum normalized block discrepancy |
|:---|:---|---:|---:|---:|---:|
| Explicit | Powers | 3 | 18 | 31,712 | ``2.08\times10^{-17}`` |
| Explicit | Broad | 3 | 6 | 45,492 | ``1.44\times10^{-15}`` |
| Eliminated | Powers | 4 | 27 | 31,520 | ``5.55\times10^{-17}`` |
| Eliminated | Broad | 3 | 7 | 45,300 | ``1.55\times10^{-15}`` |

All **58 native systems at 13 selected states** pass reconstruction. Reported
discrepancies include the explicit regularization-print allowance described
above. All selected large-case systems have returned solutions; the small
calibration additionally exercises failed factorization attempts. Native
refinement classifications and printed residual sequences match the previous
controls. Equality/inequality and fixed-variable maps account for every native
matrix dimension.

## What this changes about the next experiment

Broad lifting causes Ipopt's gradient-based scaling to rescale **897 of 6,055
inequality rows** on this workload. Powers-only uses no additional NLP
constraint-row scaling. The broad factors are approximately 0.779–0.899 on the
affected rows. Therefore the admitted lifting comparisons include both a
structural change and a change in automatic row scaling. This does not invalidate
the measured formulation recommendations, but it prevents attributing their
benefit solely to curvature placement or solely to matrix size.

Rebuilding the models without optimization and reconciling every solver row with
the declaration inventory identifies all 897 affected rows as phase-to-neutral
lower-voltage bounds (`vpn_min`) on 299 LV buses. No affected row belongs to a
transformer equation. This narrows the scaling intervention to a particular
physical bound family; the provenance check does not establish its causal effect.

The next controlled diagnostic should hold objective scaling fixed while
separately enabling/disabling the extra NLP row scaling. Native matrix/RHS exports
allow the linear-system effect to be examined before repeating nonlinear solves.
The size of a row-scale change alone does not establish its performance impact.

## Reproduce and interpret carefully

After retaining a native level-10 log, stream selected direction blocks:

```python
import sys
sys.path.insert(0, "examples")
from ivr_native_kkt import iteration_blocks, calls
with open("solve.log") as log:
    for iteration, text in iteration_blocks(log, {0}):
        systems = calls(text)
        assert systems
        # Each successful call has a matrix, RHS, solution and residual_max.
```

Run the reader regressions with:

```sh
python3 -m unittest discover -s test -p 'test_ivr_native_kkt.py'
```

The augmented matrix is printed before subsequent linear-solver scaling and
pivoting. It is not the MUMPS factorization, and its direct matrix residual is
not Ipopt's full primal-dual refinement ratio. Roundoff in printed values and in
the independent multiplication limits residual interpretation. No condition
number, causal timing explanation or universal scaling recommendation follows.
All transformation options and defaults remain unchanged; timing stays deferred.

The source files used to establish conventions, complete native logs, selected
blocks, callback states, derivatives, analytic calibration and audits are retained
outside Git in `NATIVE_KKT_20261007`. The initial reader refused the scaled
Jacobian wrapper in broad lifting; that failed audit is preserved. The final
reader handles the explicit scale vector and checks its dual conversion. No
solver or package source was modified.

The [retained-system row-unit control](ivr_kkt_row_units.md) now verifies the
complete coordinate congruence on all 58 selected systems, including slack-bound
curvature and RHS/direction transformations. This supplies an algebraic control
for later factorization and nonlinear experiments; it is not a timing result.
