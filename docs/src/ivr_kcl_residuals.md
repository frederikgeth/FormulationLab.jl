# KCL residual amplification after current elimination

The [regional-current experiment](ivr_nwinding_network.md#Regional-preflight-results-—-6-October-2026)
rejected three endpoints despite `LOCALLY_SOLVED` and native constraint errors
below ``5\times10^{-13}``. Their original SI KCL residuals exceeded the unchanged
``10^{-6}`` A gate. This study traces that discrepancy and introduces an optional
row-normalization cap. Existing formulations, uncapped controls and all rejected
results remain available. No optimizer wall-time conclusion is drawn from these
concurrent diagnostic runs.

## Residuals in three coordinate systems

Let ``y`` be the native complex solver state, ``z=Ry`` the reconstructed
assembly-unit state, ``a`` an original KCL row and ``I_b`` the global current
base in amperes. If the row is divided by the positive scalar ``d``,

```math
\eta=\frac{aRy}{d},\qquad
r_{\mathrm{SI}}=I_b aRy=G\eta,\qquad G=I_b d.
```

``G`` has units of amperes per unit normalized residual. It is not an operating
current or a matrix condition number. When the real and imaginary scalar
constraints each have residual at most ``\tau``, exact arithmetic gives

```math
|r_{\mathrm{SI}}|\leq\sqrt{2}\,G\tau.
```

Thus a complex SI target ``\epsilon_A`` corresponds to complex normalized
residual ``\epsilon_A/G``; the sufficient target for **each scalar component**
is ``\epsilon_A/(\sqrt{2}G)``. Mixing complex magnitudes with componentwise
solver tolerances would omit the ``\sqrt{2}`` factor.

`examples/ivr_kcl_residual_trace.jl` evaluates the same native state through:

1. the original row applied to Float64 reconstructed coordinates;
2. the Float64 composed row applied directly to solver coordinates;
3. the normalized JuMP expression used to construct retained circuit rows;
4. 256-bit nested and composed evaluations of the **stored Float64 coefficients**.

The higher precision evaluation does not re-solve the NLP, repair the point,
or recover exact coefficients preceding floating-point stamping and elimination.
It separates evaluation and composition arithmetic from the residual already
present at the returned solver state. Omitted KCL rows are flagged from the
specialization and passive-elimination reports. They must not be interpreted
as independently enforced constraints. This compiler-based diagnostic complements
the independent SI audit; it does not replace it.

## Matched control experiment

The three rejected physical/current-unit cases are each solved under all four
current/lifting representations, giving twelve native solves and 96 row traces
at the 24 originally violated bus/terminal locations. All inputs, starts,
objective definitions, units and strict solver settings match the preceding
regional panel. The selected rows are independently retained in all controls.
The original three failures reproduce; the other nine controls pass.

For these rows:

| Current representation | Conversion factor G (A) |
|:--|--:|
| Explicit multiwinding currents | 10.0516623911 |
| Eliminated multiwinding currents | 3866168.80512 |

The conversion factor is about 384,630 times larger after elimination. Power
and bounded-observation lifting have the same factor within a current
representation; their numerical endpoints need not have the same residual.
Elimination introduces voltage-dependent current expressions with large
coefficients. Normalizing their composed KCL rows makes a small native residual
compatible with a larger ampere residual.

For example, one rejected row has normalized complex residual approximately
``3.6363\times10^{-13}`` and SI residual ``1.4058\times10^{-6}`` A. Its sufficient
scalar-component target for the 1 µA audit is approximately
``1.8290\times10^{-13}``. Across all twelve solves, differences attributable
to the compared composition/evaluation arithmetic stay below
``1.8\times10^{-11}`` A, far below the rejected residuals. Higher precision
preserves those residuals. The evidence identifies normalization amplification
as the dominant explanation for these endpoints, rather than last-step
reconstruction roundoff. It does not certify every other transformation or case.

The analytical regression also includes deliberately catastrophic cancellation:
``10^{16}+1-10^{16}`` loses the unit contribution in the ordered Float64
composition, while the high-precision nested evaluation retains it. This checks
that the diagnostic can detect arithmetic loss when it actually occurs.

## Optional cap on retained KCL row units

`IVRNLPOptions(kcl_row_max_base=1000.0)` caps the **numerical ampere unit** of
each retained KCL equality. It is not an engineering current limit. The divisor
becomes

```math
d_{\mathrm{new}}=\min(d_{\mathrm{existing}}, C_A/I_b),
\qquad G_{\mathrm{new}}\leq C_A.
```

The default `nothing` retains the preceding normalization exactly. The cap
applies after either `row_scaling=:legacy` or `:composed`; rows already below
it stay unchanged. It does not change coordinate maps, non-KCL device equations,
physical bounds, objectives, generator/auxiliary units or result variables.
Nonpositive/nonfinite caps and unrepresentable ampere-to-assembly ratios are
refused. Omitted KCL rows receive no independent cap and still require SI audits.

At ``C_A=1000`` A and a hypothetical component residual bound
``\tau=10^{-10}``, the above arithmetic bound is
``1.415\times10^{-7}`` A (rounded upward). This provides margin relative to the
1 µA SI gate and motivates the tested cap. It is not a solver guarantee: finite
arithmetic, internally scaled convergence tests and implied rows still require
original-network validation. Ipopt settings and physical tolerances are unchanged.

The first intervention solves the three rejected cases with exactly this new
option. All three pass original SI physics and full-model membership with
matching objectives. Their largest KCL residuals are respectively
``1.4571\times10^{-11}``, ``5.2466\times10^{-11}`` and
``1.1213\times10^{-11}`` A (rounded upward); iterations change 26→25, 30→25
and 32→30. The subsequent complete-panel comparison retains all 96 regional
cases rather than selecting only those three failures.

The complete comparison admits **96/96** capped endpoints, versus the preserved
**93/96** uncapped baseline. Independent SI audits also admit all 96, with maximum
KCL residual ``5.2466\times10^{-11}`` A (rounded upward), and both result readers
agree on all exports. Every case matches the original objective and variable
count; the only option difference is `kcl_row_max_base=1000.0`. SI audit coverage
includes 38,400 KCL balances, 13,056 coil powers, 6,528 winding caps and 2,176
IBR internal-power channels. Exports retain the same physical variable structure.

Iterations are unchanged in 59 cases, lower in 20 and higher in 17. Those counts
include the three rejected baseline endpoints for diagnostic completeness;
failed endpoints cannot enter a speed comparison. The cap therefore has
mixed convergence effects even though it resolves the tested SI failures.
The diagnostic's 328 targeted assertions and the cap's 457 targeted assertions
pass, including unchanged coordinate maps/equations, objective correspondence,
engineering-bound rejection witnesses and both legacy/composed row policies.
The complete suite is also checked for this production option; its log is
retained with the checkpoint evidence.

## Reproduction and scope

```julia
include("examples/ivr_kcl_residual_trace.jl")

# `build` is an IVRNLP model already solved with native primal values.
rows = IVRKCLResidualTrace.trace(build;
    keys=[("u8_b4", "a")], bits=256, atol_A=1e-6)
```

The reporting target does not modify solver settings. The optional cap is set
when building a model, for example:

```julia
build = build_opf(net,
    IVRNLP(transformer_scaling=:nominal, row_scaling=:composed,
           kcl_row_max_base=1000.0);
    optimizer=Ipopt.Optimizer)
```

Other options should be carried over from the profile being compared. The raw
`NWINDING_KCL_RESIDUAL_TRACE_20261006` archive records the twelve traces, original
and capped sources, fixed settings, exports, comparison scripts and all initial
failures. Handover, roadmap and raw evidence remain outside Git. Isolated
optimizer-call wall timing, with compilation excluded, remains necessary before
promoting this robustness intervention as a speed improvement. Nominal-voltage
propagation through general multiwinding devices remains a separate opt-in
research priority; this intervention preserves the existing fallback.

## Voltage equations and implied rows

The [circuit-row diagnostic](ivr_circuit_residuals.md) extends physical-unit
tracing to recorded line drops, winding leakage and ampere balances. It reports
unclassified equations explicitly and leaves normalized fields undefined for
rows that are not independently enforced. This complements the original KCL
trace without changing its API or the formulation.
