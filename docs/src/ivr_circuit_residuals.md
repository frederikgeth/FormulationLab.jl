# Physical units of retained and implied circuit residuals

## Why extend the KCL trace?

A small normalized equality residual need not be small in physical units. The
[KCL study](ivr_kcl_residuals.md) demonstrated this for current elimination.
The same question applies to voltage drops and transformer leakage equations,
including equations removed by exact substitutions. Two distinctions matter:
not every non-KCL circuit equation has voltage units, and an implied equation
has no independently enforced solver tolerance.

`examples/ivr_circuit_residual_trace.jl` provides a read-only diagnostic for
these distinctions. It does not change the model, repair a solution, introduce
a row cap or invoke the optimizer. Existing KCL diagnostics remain available.

## Provenance before conversion

The diagnostic assigns units from recorded physical stamps:

| Recorded row family | Physical unit | Assembly-to-SI multiplier |
|:--|:--|:--|
| Line series voltage drop | V | ``V_b`` |
| Ordinary transformer ampere balance | A | ``I_b`` |
| Multiwinding ampere-turn balance | A | ``I_b`` |
| Multiwinding leakage equation, referred through its declared turns | V | ``V_b`` |
| Constant-impedance load current law | A | ``I_b`` |
| Bus-terminal KCL | A | ``I_b`` |

Multiwinding block records contain, for each coil, one ampere-turn balance
followed by the leakage equations. The diagnostic checks the recorded block
size and uses this stamp contract; it does not infer units from coefficient
magnitudes or from whether a row contains voltage coordinates. Other circuit
equation indices are returned as `unclassified_equations`. In particular,
ordinary transformer voltage equations are currently outside this catalogue.
Nonlinear load/power/operating-bound rows and fixed-variable constraints are
also outside this diagnostic's scope. An unclassified row is not an omitted
constraint or a failed equation.

Removal status follows the recorded specialization, passive-line,
impedance-load and device-elimination reports. The diagnostic distinguishes
retained, empty and omitted rows. It does not infer elimination merely because
a composed row is small or cancels numerically.

## Retained-row conversion and implied-row residuals

For original row ``a``, stored reconstruction ``R``, fixed native state ``y``,
physical multiplier ``s`` and the actual positive retained-row divisor ``d``,

```math
r_{\mathrm{SI}}=s\,aRy,\qquad
\eta=aRy/d,\qquad G=s d.
```

The multiplier ``s`` is ``V_b`` or ``I_b`` according to the row's provenance.
The cap, if present, changes ``d`` for retained KCL only. For a reporting target
``\epsilon`` in the row's SI unit, a sufficient componentwise normalized target
is ``\epsilon/(\sqrt{2}G)``. This is an exact-arithmetic implication conditional
on both scalar residuals meeting the target, not an assertion about Ipopt's
termination criterion.

An omitted row has **no independent normalized constraint**. Its `divisor`,
`gain_SI`, normalized residual fields and `sufficient_scalar_target` are therefore
`nothing`. The physical residual ``s aRy`` is still evaluated. A small residual
may follow from algebraic substitution, while approximate stored reconstruction
coefficients can leave a nonzero remainder. A residual bound inherited from
other rows would require an explicit dependence certificate; this diagnostic
does not supply one or borrow the largest retained-row tolerance.

For every classified row, the trace compares Float64 nested reconstruction,
Float64 composed evaluation, the JuMP expression, and high-precision nested
and composed evaluation of the **stored Float64 coefficients**. These comparisons
separate arithmetic effects at the returned native state. They do not recover
exact pre-rounding circuit coefficients or establish a conditioning bound.
Independent original-SI physical audits remain the acceptance authority.

## Usage and interpretation

After solving an `IVRNLPBuild` named `build`:

```julia
include("examples/ivr_circuit_residual_trace.jl")
report = IVRCircuitResidualTrace.trace(build;
    bits=256, atol_A=1e-6, atol_V=1e-6)
unknown = report.unclassified_equations
voltage_rows = filter(q -> q.unit == :V, report.rows)
implied_rows = filter(q -> !q.retained_constraint, report.rows)
```

Each row carries its label, original equation index or KCL key, unit, physical
multiplier, omission reason, original/composed support and precision. Interpret
`float_nested_SI` and `big_nested_SI` in `row.unit`; do not compare the numerical
values of ampere and volt residuals as if they shared a tolerance. Reporting
targets never change solver settings. `catalog(build)` can inspect provenance
and omissions before a solve; `trace(build)` requires finite native values.

The regression includes analytical voltage/current conversion, a KCL-only cap,
null normalization fields for omitted rows, precision restoration and explicit
unknown-row reporting. Sixteen live two-unit solves cross both nominal policies,
both cap choices and four current/lifting representations. Original SI line
voltages, charged terminal currents and non-star winding equations provide
independent comparisons. Diagnostic evaluation leaves native variable values
unchanged.

## Matched residual evidence, 6 October 2026

The diagnostic panel crosses 8/24 live four-winding units, the four existing
current/lifting representations and both nominal policies with/without the
1000 A KCL cap. All 32 endpoints are locally solved; 30 pass the unchanged
physical/full-model gates. The two ordinary-only uncapped, eliminated-current,
power-lifted tracking controls reproduce their KCL failures. No bound or
acceptance tolerance changes. The panel traces **38,144 complex rows**:

| Unit and enforcement status | Row evaluations | Largest physical residual | Largest compared arithmetic effect |
|:--|--:|--:|--:|
| V, retained | 10368 | ``2.185\times10^{-12}`` V | ``1.045\times10^{-13}`` V |
| V, implied | 8192 | ``2.231\times10^{-13}`` V | ``1.798\times10^{-13}`` V |
| A, retained | 11808 | ``1.468\times10^{-6}`` A | ``1.569\times10^{-11}`` A |
| A, implied | 7776 | ``3.532\times10^{-12}`` A | ``3.433\times10^{-12}`` A |

Residual and arithmetic columns are separate maxima, rounded upward; they may
occur on different rows. “Arithmetic effect” is the largest of the nested,
composition and composed-evaluation differences. The retained-ampere maximum
includes the rejected controls. These row evaluations are repeated observations
of a manufactured network family, not independent physical-network samples.
Every endpoint has three explicitly unclassified ordinary-transformer voltage
equations; the independent whole-network audit still checks the original physics.

For 24 units, eliminated transformer currents and power lifting:

| Nominal policy | KCL cap | Largest retained A conversion factor | Largest retained V conversion factor |
|:--|:--|--:|--:|
| Ordinary only | None | 3866168.805116 | 4600.000005 |
| Ordinary only | 1000 A | 1000.000000 | 4600.000005 |
| Multiwinding | None | 54791.892433 | 325.269119 |
| Multiwinding | 1000 A | 1000.000000 | 325.269119 |

These are maxima within each physical-unit family, not necessarily the same
row across policies. Nominal units reduce both maxima; the KCL cap leaves the
voltage conversion factors unchanged. The uncapped multiwinding endpoint passes
with largest traced retained ampere residual below ``3.784\times10^{-10}`` A,
while the corresponding ordinary-only endpoint fails at approximately
``1.468\times10^{-6}`` A. The cap remains an independent option.

Small implied-row remainders are comparable to the arithmetic differences on
this panel. This is not a proof of zero residual or a uniform error bound for
other networks. No new voltage normalization cap follows from these results.
The next extension should add explicit provenance for remaining row families
and dependence certificates where an inherited residual bound is needed.

The new diagnostic regression passes **12,193 assertions**. Raw traces include
native real/imaginary coordinates and every row result; input/source snapshots,
failed controls and validation scripts are retained outside Git in
`CIRCUIT_ROW_RESIDUALS_20261006`. Complete regression and documentation logs are
archived with them. Diagnostic timings are excluded from speed evidence.
