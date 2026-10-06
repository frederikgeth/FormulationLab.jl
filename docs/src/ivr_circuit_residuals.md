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

Native IVRNLP builds now record provenance when each linear electrical row is
assembled. `build.electrical.equation_metadata` contains its original index,
physical label, unit (`:V` or `:A`) and positive `assembly_multiplier`. Recording
appends metadata only; it does not modify the row or its insertion order.

| Recorded row family | Physical unit | Assembly-to-SI multiplier |
|:--|:--|:--|
| Line series voltage drop | V | ``V_b`` |
| Ordinary transformer leakage/voltage relation | V | ``V_b`` |
| Ordinary transformer ampere balance | A | ``I_b`` |
| Transformer ideal bond or ideal neutral ground | V | ``V_b`` |
| Multiwinding ampere-turn balance | A | ``I_b`` |
| Multiwinding leakage equation, referred through its declared turns | V | ``V_b`` |
| Constant-impedance load current law | A | ``I_b`` |
| Closed-switch voltage continuity | V | ``V_b`` |
| Homogeneous source phasor relation | V | ``V_b`` |
| Internally normalized current-form shunt law | A | ``m I_b`` |
| Bus-terminal KCL | A | ``I_b`` |

All current native linear electrical rows have explicit records. KCL has its
separate known ampere provenance. The diagnostic rejects incomplete, duplicated
or invalid metadata instead of guessing units. Its earlier partial catalogue
remains available for older builds or external toy data without metadata;
those can still return `unclassified_equations`. In that fallback, multiwinding
block ordering supplies the distinction between ampere and leakage rows.

The shared assembly's current-form shunt row is divided by a row admittance
magnitude ``m`` before it reaches the formulation. Its physical current residual
therefore requires ``m I_b``, not just ``I_b``. This multiplier is one for the
other recorded families. Native IVRNLP uses substituted admittance shunts;
the current-form test is a shared-assembly control, not a new solver option.
Similarly, native IVRNLP fixes source variables directly; source phasor rows
occur only in the shared assembly's homogeneous source mode.

Completeness here means `electrical.equations` plus KCL. Nonlinear power/load-law
rows, operating bounds and fixed-variable constraints are outside this catalogue.
This is not a new certificate of bound-expression coverage. Finite grounding
admittances substituted into currents do not create a separate equality; ideal
grounding can create a voltage row, including an empty row if already fixed.

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

The multiplier ``s`` is the recorded `assembly_multiplier` times ``V_b`` or
``I_b`` according to the row's provenance.
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
other rows requires an explicit dependence certificate. The separate
[exact stored-coefficient diagnostic](ivr_implied_residuals.md) now provides
these identities and state-dependent bounds; the trace itself does not borrow
the largest retained-row tolerance.

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
The 6 October catalogue left three ordinary-transformer voltage equations per
endpoint explicitly unclassified; the independent whole-network audit still
checked their original physics. The 7 October extension below classifies them.

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
The subsequent extension below supplies explicit linear-row provenance.
Dependence certificates remain necessary where an inherited residual bound is needed.

The new diagnostic regression passes **12,193 assertions**. Raw traces include
native real/imaginary coordinates and every row result; input/source snapshots,
failed controls and validation scripts are retained outside Git in
`CIRCUIT_ROW_RESIDUALS_20261006`. Complete regression and documentation logs are
archived with them. Diagnostic timings are excluded from speed evidence.

## Complete linear-row provenance, 7 October 2026

The repeated 32-endpoint panel adds the 96 formerly unclassified ordinary
transformer-voltage rows: **38,240 classified evaluations, zero unclassified**.
All native coordinate values, iteration counts and previously recorded row
results agree exactly with the preceding stored panel. The same 30 endpoints
pass and the same two uncapped ordinary-only KCL controls fail. No physical
input, objective, bound, normalization policy or option default changes.

The added voltage rows have maximum Float64 nested residual below
``2.192\times10^{-12}`` V and high-precision nested residual below
``2.185\times10^{-12}`` V. Their largest compared arithmetic effect is below
``4.887\times10^{-14}`` V, with maximum retained voltage conversion factor
325.269120 V (rounded upward). These observations still do not motivate a
voltage-row cap or certify an inherited tolerance for implied equations.

Regression tests compare recorded/unrecorded assemblies exactly, including
coordinate numbering, rows, KCL, device observations, limits and source values.
Independent SI oracles cover all six ordinary transformer/regulator types,
both flow directions and deliberately perturbed secondary voltages. Additional
cases cover ordinary/multiwinding grounding, closed/open switches, source modes,
constant-impedance loads, normalized shunt currents, legacy fallback and corrupt
metadata refusal. Full regression logs and raw comparison records are archived
outside Git in `EQUATION_PROVENANCE_20261007`.

An isolated timing retry was refused before launch because a competing Julia
process appeared at the initial guard. It produced zero warmups and zero
measured solves; the record is retained in `NWINDING_COORDINATE_TIMING_20261007`.
The diagnostic comparisons above are not speed evidence.

The complementary [load-law and voltage-bound trace](ivr_nonlinear_residuals.md)
records original nonlinear load laws and bus-voltage declarations, including
shared equalities and tautologies. Its catalogue is explicitly partial and
does not extend the linear residual certificates to nonlinear laws.
