# Nonlinear row scaling with a fixed objective scale

## Question and controls

The [fresh-factorization study](ivr_kkt_factorization.md) found no consistent
accuracy benefit from removing the extra NLP scales on 897 LV lower-voltage
rows. This experiment asks whether that intervention changes the complete
nonlinear trajectory. It retains the same four zero-load-reduced, 333-bus
exchange-tracking profiles, physical input, per-unit bases, objective, primal
starts, MUMPS settings and convergence tolerances as the
[native KKT study](ivr_native_kkt.md). It supplies no timing evidence.

Let ``\gamma>0`` be the objective scale and ``R`` the positive diagonal NLP
constraint scale. Ipopt solves with ``\widetilde f=\gamma f`` and
``\widetilde g=Rg``. Changing `nlp_scaling_max_gradient` alone can change both
``\gamma`` and ``R``. The following three arms separate that ambiguity:

| Arm | Objective-gradient target | Constraint-gradient cutoff | Required control |
|:---|---:|---:|:---|
| Baseline | Default (0) | 100 | Reproduce earlier native callback records |
| Held | 100 | 100 | Reproduce baseline records exactly |
| Unit | 100 | ``10^{300}`` | Reproduce baseline for powers-only profiles |

The explicit objective target gives ``\gamma=100/\lVert\nabla f(x_0)\rVert_\infty``.
For this panel, the initial gradient exceeds 100 and the result equals the
baseline factor, **0.09977750221131347**. This recipe is not a universal identity:
if the initial gradient were below 100, the explicit target could scale the
objective upward, unlike the default rule. The scaling floor can also matter.
The large cutoff is a diagnostic way to suppress row scaling; the actual native
vectors must establish unit scales, rather than assuming the cutoff suffices.
These behaviors follow the
[Ipopt 3.14.19 gradient-scaling implementation](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpGradientScaling.cpp).

All twelve arms use verbosity 8 to retain internal vectors, a diagnostic CPU
ceiling of 300 seconds and one BLAS thread. Compilation and instrumented solver
time are excluded from performance assessment. No production default changes.

## Physical coordinates and internal initialization

Each callback is checked against the declared scales:

```math
\widetilde x=x,\qquad
\widetilde z=\gamma z,\qquad
\widetilde\lambda=\gamma R^{-1}\lambda,\qquad
\widetilde g=Rg.
```

Here “unscaled” means original TNLP model units, which may already be per unit;
it does not mean SI. Canonical physical exports remain in SI.

Matching these relations does not imply that two runs start from the same
internal primal-dual state. To remove row scales while preserving that state,
the inequality slacks and multipliers must satisfy

```math
s_{\mathrm{unit}}=R_d^{-1}s_{\mathrm{base}},\qquad
 y_{d,\mathrm{unit}}=R_d y_{d,\mathrm{base}},\qquad
 t_{\mathrm{unit}}=R_d^{-1}t_{\mathrm{base}},\qquad
 v_{\mathrm{unit}}=R_d v_{\mathrm{base}}.
```

The bound vectors use the corresponding entries of ``R_d``. Complementarity
products ``tv`` should then agree and slack-bound curvature transforms as
``(v/t)_{\mathrm{unit}}=R_d^2(v/t)_{\mathrm{base}}``. Initial internal vectors are
read from native logs before the first primal-dual solve and checked separately
from the callback arrays. Differences use
``\max_i|a_i-b_i|/\max(1,|a_i|,|b_i|)``. The previous exact KKT congruence applies
to fully transformed states; a new nonlinear solve uses Ipopt's initializer.

## Results

All twelve OPF arms converge locally and pass the physical residual, own-model,
full-reference-model, reverse-point and emitted-constraint checks. Their
physical objectives agree under the declared ``10^{-6}`` absolute or
``10^{-8}`` relative tolerance. The four baselines reproduce all 142 earlier
callback states exactly. Held-objective controls reproduce those trajectories
and every retained initial internal vector. Powers-only unit-row controls also
reproduce their baselines exactly. Native row vectors and callback arrays verify
the common objective factor and all declared constraint scales.

| Transformer currents | Lifting | Baseline iterations | Held iterations | Unit-row iterations |
|:---|:---|---:|---:|---:|
| Explicit | Powers | 33 | 33 | 33 |
| Explicit | Broad bounded observations | 36 | 36 | 35 |
| Eliminated | Powers | 33 | 33 | 33 |
| Eliminated | Broad bounded observations | 36 | 36 | 35 |

The broad runs remove exactly 897 lower-voltage row scales. After coordinate
mapping, their initial primal variables, slacks, constraint multipliers and
variable-bound multipliers agree to roundoff. However, all initial lower-slack
bound multipliers equal one in both runs. Coordinate equivalence would require
multiplying 897 of them by the original row scales. Their maximum normalized
discrepancy is 0.22145; initial complementarity products differ by up to 0.06299
and mapped slack-bound curvature by up to 0.22145. Thus the complete internal
states are **not coordinate equivalent**.

This distinguishes two findings. The row-unit intervention, with native
initialization and fixed objective scale, reduces iterations by one in both
broad profiles. It does not identify a benefit caused solely by KKT scaling or
factorization. Nor does one fewer iteration establish lower Ipopt wall time.
Automatic MUMPS preprocessing and existing formulation recommendations remain
unchanged. Retain unit-row scaling as an experimental candidate.

All twelve SI exports preserve the same 25,907 physical leaf paths across arms
and formulations, agree with the earlier exports' field paths, and pass both
FormulationLab and BMOPFTools readers. BMOPFTools writing followed by
FormulationLab reading also preserves each export exactly. Equality of field
paths does not claim pointwise equality of every optimizer output; physical
feasibility and objective equivalence are tested separately.

The initial driver mistakenly included `complete_input_coverage` in its
acceptance conjunction. The [inventory](ivr_constraint_inventory.md) explicitly
leaves this flag false because it certifies emitted constraints, not the entire
input schema. All raw `accepted=false` summaries are retained. A separate audit
checks the numerical gates and preserves the input-coverage limitation; no
solver settings, numerical tolerance or result is altered to change acceptance.
Universal input-field completeness remains unclaimed.

The [warm-start follow-up](ivr_warm_start_controls.md) constructs and verifies
coordinate-equivalent complete initial states to roundoff. Both broad profiles
then take 32 iterations in either row convention. This uses new warm states;
it is not a replay of the original cold starts. Timing comparison remains
explicitly deferred until an eligible isolated campaign is authorized.

## Reproduction and limitations

The small calibration includes a fixed variable, both inequality directions,
nonlinear curvature, a violated starting constraint and a nontrivial affine row
scale. It checks the optimum, every callback's scaled/unscaled arrays and exact
baseline/held replay:

```sh
julia --project=docs --startup-file=no test/ivr_row_scaling_control.jl
```

For a prepared diagnostic model:

```julia
include("examples/ivr_row_scaling_control.jl")
options = IVRRowScalingControl.settings(unit_rows=true)
# Merge with the declared solver options; retain and verify native scales.
```

Earlier calibration variants with a heavily scaled nonlinear inequality entered
restoration, which the existing iterate recorder does not support. Their inputs
and logs are retained. The passing interface test uses a scaled affine bound;
it does not demonstrate robustness for every nonlinear row-scaling choice.
No OPF case or solver setting was revised to avoid those calibration outcomes.

The frozen protocol, all twelve solve logs and callback histories, physical
exports, checksums, audit drivers, calibration limitations and planning documents
are retained outside Git in `NONLINEAR_ROW_SCALING_20261007`.
