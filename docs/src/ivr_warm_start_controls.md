# Row scaling from equivalent warm-start states

## Why another initialization control is needed

The [cold-start row-scaling comparison](ivr_nonlinear_row_scaling.md) preserved
objective scaling but changed 897 initial slack-bound multipliers relative to the
coordinate-equivalent state. This follow-up constructs a **new, representable
warm-start pair**. It asks whether a complete initial-state comparison can pass
through the installed Julia/C interface before interpreting nonlinear results.
It does not claim replay of the original cold start or provide timing evidence.

The ordinary Ipopt interface accepts primal variables, constraint multipliers
and variable-bound multipliers. Its warm initializer reconstructs slacks from
constraint values and derives slack-bound multipliers from the constraint duals.
For a one-sided inequality, before subsequent pushes,

```math
s=d(x),\qquad v_L=\max(\epsilon,-y_d),\qquad
v_U=\max(\epsilon,y_d),
```

using only the bound side that exists. Consequently the previous cold state
``y_d=0,\ v=1`` cannot be independently prescribed through these ordinary starts
with a small positive multiplier floor. This restriction follows the
[Ipopt 3.14.19 warm initializer](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Algorithm/IpWarmStartIterateInitializer.cpp)
and the [standard TNLP interface](https://github.com/coin-or/Ipopt/blob/releases/3.14.19/src/Interfaces/IpStdInterfaceTNLP.cpp).
A custom C++ entire-iterate interface could expose additional state; it is not
implemented by this diagnostic helper.

## Constructing the paired states

Let ``\gamma`` be the shared objective scale and ``R_0`` the reference row scale.
The helper sets original-TNLP multipliers to

```math
\lambda_i^0=
\begin{cases}
-(R_0)_{ii}/\gamma,&\text{lower inequality},\\
+(R_0)_{ii}/\gamma,&\text{upper inequality},\\
0,&\text{equality}.
\end{cases}
```

Variable-bound multipliers are ``1/\gamma``. JuMP dual starts use its own sign
convention; `examples/ivr_warm_start_control.jl` performs that conversion.
**Reuse the same reference scales and original-TNLP seeds in both arms.**
Recomputing the seeds from each arm's own row scales would reset the internal
multipliers to one and defeat this control.

The reference arm therefore starts with ``|y_d|=v=1`` to floating-point accuracy.
In the unit-row arm, ``y_d`` and ``v`` are multiplied by the reference row scales.
The coordinate map uses ``A=R_{\mathrm{new}}R_{\mathrm{old}}^{-1}``:

```math
s_{\mathrm{new}}=As_{\mathrm{old}},\qquad
y_{\mathrm{new}}=A^{-1}y_{\mathrm{old}},\qquad
v_{\mathrm{new}}=A^{-1}v_{\mathrm{old}}.
```

Bound distances transform by the corresponding entries of ``A``;
complementarity products are invariant and slack-bound curvature transforms by
``A^{-2}``. Primal variables and variable-bound multipliers remain unchanged.
Objective and column scales are verified separately.

Both arms use `warm_start_init_point="yes"`, bound, slack and multiplier pushes
of ``10^{-8}``, disabled maximum-multiplier clipping, zero target-mu heuristic,
and `warm_start_entire_iterate="no"`. Positive pushes remain, so the algebraic
seed recipe alone does not guarantee matching initialization. Native vectors
before the first primal-dual solve establish the comparison. The normalized
error threshold is ``10^{-10}``, using ``|a-b|/\max(1,|a|,|b|)`` for each component.

The two arms retain objective-gradient target 100, with row-gradient cutoffs
100 and ``10^{300}``. The initial objective scale must remain
0.09977750221131347 for the OPF panel. Actual row vectors and all callback states
are checked; unit row scaling is not inferred solely from an option value.

## OPF results and interpretation

The eight predeclared solves retain all four zero-load-reduced, 333-bus
exchange-tracking profiles. Every solve converges locally and passes physical,
own-model, full-reference-model, reverse-point, objective and emitted-constraint
audits. All 260 callback states pass the declared scale relations. Native logs
verify the same row scales as before and a common initial barrier parameter
``\mu=0.1``.

| Transformer currents | Lifting | Reference rows | Unit rows | Initial-state control |
|:---|:---|---:|---:|:---|
| Explicit | Powers | 31 iterations | 31 iterations | Exact identity |
| Explicit | Broad bounded observations | 32 iterations | 32 iterations | Coordinate equivalent to roundoff |
| Eliminated | Powers | 31 iterations | 31 iterations | Exact identity |
| Eliminated | Broad bounded observations | 32 iterations | 32 iterations | Coordinate equivalent to roundoff |

For both broad pairs, maximum initial vector discrepancy is
``2.22\times10^{-16}``, complementarity discrepancy is
``1.67\times10^{-16}``, and slack-bound curvature discrepancy is
``8.43\times10^{-16}``. Both powers-only pairs reproduce their entire callback
histories exactly. This establishes a much tighter initialization control than
the prior cold-start comparison.

Equal iteration counts do not imply equal trajectories. The broad pairs first
differ in their original-TNLP primal vectors at iteration 1. Their maximum
normalized primal discrepancy over matched iteration indices is
``7.47\times10^{-6}``; the maximum constraint-multiplier discrepancy is
``2.36\times10^{-4}``. These quantities use model coordinates, not SI.
Coordinate-equivalent starting states to roundoff do not make all stopping,
line-search, linear-algebra and finite-precision operations coordinate invariant.
No unique mechanism for the later differences is identified by this experiment.

The previous cold runs used zero initial constraint duals and larger bound
pushes. The warm reference differs from its cold predecessor by up to 0.00999999
in normalized initial primal/slack values and 1 in inequality duals. Therefore
the lower warm iteration counts cannot be attributed solely to dual seeding.
The earlier broad cold comparison's 36-to-35 iteration reduction does not repeat
here, but this is not proof that its entire effect arose from dual initialization:
the common starting state also changed.

All eight SI exports retain the same 25,907 physical leaf paths across arms,
formulations and earlier exports. Both readers and the BMOPFTools-to-FormulationLab
writer/reader roundtrip pass, with 17 integration assertions. Input-schema
completeness remains explicitly unclaimed; the emitted-constraint inventory is
the coverage gate.

No instrumented timing is eligible for ranking. Automatic MUMPS preprocessing,
production defaults and formulation recommendations remain unchanged. Preserve
both cold and warm controls, the row-unit option and every existing formulation.
The next useful diagnostics are a separated study of primal pushes and dual
seeding, and the planned mixed absolute/relative residual analysis with worst-row
provenance. Timing remains deferred.

## Calibration and use

The small nonlinear calibration includes a fixed variable, both bound sides,
nontrivial lower/upper row factors 0.5 and 0.25, and a violated initial constraint.
It verifies the optimum, dual-start signs and scaled/unscaled callback arrays.
All native initial vectors, mapped complementarity and bound curvature agree
exactly for its two arms. The Julia calibration passes 45 assertions. Separate
Python tests verify the coordinate map, its inverse, detection of multiplier
resetting, invalid states and incompatible layouts.

```sh
julia --project=docs --startup-file=no test/ivr_warm_start_control.jl
python3 -m unittest discover -s test -p 'test_ivr_initial_state.py'
```

A diagnostic use with a previously established row layout is:

```julia
include("examples/ivr_iterate_capture.jl")
include("examples/ivr_row_scaling_control.jl")
include("examples/ivr_warm_start_control.jl")
trace = IVRIterateCapture.attach!(model)
IVRWarmStartControl.seed!(model;
    objective_scale=reference_objective_scale,
    row_scales=reference_row_scales)
options = merge(existing_options,
    IVRRowScalingControl.settings(unit_rows=true),
    IVRWarmStartControl.settings())
# Solve with options, capture both TNLP coordinate conventions, and inspect
# native initial vectors using ivr_initial_state.read_initial and compare.
```

The helper rejects unsupported two-sided rows and validates the complete seed
plan before changing any dual starts. This conservative restriction avoids
claiming independent control of both slack-bound multipliers from one dual.
It requires the calibrated Ipopt.jl 1.16.0 row mapping. Production defaults and
all other initialization/formulation options remain available.

The frozen protocol, all eight logs and callback histories, calibration logs,
native-vector and trajectory audits, physical exports, source snapshots and
hashes are retained outside Git in `WARM_ROW_SCALING_20261007`. Revised handover
and roadmap files remain there as well.
