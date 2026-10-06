# Guarding voltage equalities under power costs

The [initial voltage-equality experiment](ivr_voltage_equalities.md) removed
opposing inequalities for exactly fixed positive magnitudes. Its local rewrite
can still introduce dependent equality rows. The new opt-in
`coincident_voltage_bounds=:guarded_equality` handles two specific dependencies:
identical affine voltage observations after substitution, and observations whose
coordinates are fixed by existing linear circuit equations. The default
`:separate` and original `:equality` options remain available.

## Two motivating cases

At a perfectly grounded neutral, a phase-ground voltage and the corresponding
phase-neutral voltage are the same observation. Declaring both magnitudes fixed
at 230 V can therefore produce duplicate equalities. Guarded conversion emits
one equality and records the other declaration's representative. Both original
input bounds remain present in the physical network and independent audit.

A closed ideal switch connected to a fixed-voltage source can already determine
the receiving voltage. Adding a magnitude equality contributes no new physical
restriction when the declared value agrees. The guarded option retains the
original inequalities for such certified observations. It does not discard
them: a conflicting declared magnitude must still make the model infeasible.

## Exactness and conservative scope

Let ``F`` contain the coordinates explicitly fixed by voltage sources. For an
existing homogeneous complex circuit equation

```math
\sum_{k\in S_j} a_{jk}z_k=0,\qquad a_{jk}\ne0,
```

if precisely one coordinate ``r\in S_j`` is outside ``F``, then
``z_r=-\sum_{k\ne r}a_{jk}z_k/a_{jr}`` is fixed on every feasible point. Add
``r`` to ``F`` and repeat. Induction proves fixedness relative to the original
equations. The implementation stores coordinate/equation witnesses, uses exact
nonzero support, and does not estimate coordinate values. A coefficient as small
as ``10^{-300}`` is not discarded. Source values, circuit rows and the original
voltage inequalities continue to enforce consistency.

This propagation uses the electrical assembly's linear circuit equations, not
KCL or nonlinear power equations. It can miss fixed coordinates requiring a
multirow elimination. It is not a numerical rank test or a complete independence
certificate. Nominal voltages and starting points supply no fixedness evidence.

For the remaining coincident pairs, let ``u_i(x)=c_i+A_i x`` be the composed
complex affine voltage observation and ``V_i>0`` the physical bound. Two pairs
share an equality only when the real and imaginary coefficient maps of
``u_i/V_i`` are identical. Their common voltage base cancels. The comparison
converts the stored binary coefficients and bounds to `Rational{BigInt}` before
division; rounded floating normalization is insufficient to prove identity.
Equal normalized observations give identical squared-magnitude equations, so
one representative preserves the feasible set. This establishes identity of
the stored affine expressions; it does not reinterpret earlier floating-point
circuit assembly as exact physical arithmetic.

The guard deliberately does not identify sign, complex-phase or conjugate
magnitude aliases. Proper intervals, zero limits, unmatched families and
noncoincident bounds retain their existing behavior. Direct source-fixed pairs
retain the original `fixed_source_pair_retained` action. New actions are
`circuit_fixed_pair_retained` and `shared_equality`; the latter records the
representative bus, lower-bound field and channel. Build diagnostics expose
`voltage_fixed_dependencies`; native JSON exports retain the pair actions and
representative provenance as additive metadata. Physical SI variables are
unchanged.

## External applicability screen

A read-only screen examined 3,136 JSON files in the supplied BMOPFDraftData
`output` and `benchmarks` trees; 3,115 contain top-level bus tables. It found
no positive exactly equal lower/upper declarations in the supported `v`, `vpn`,
`vpp` and `vpos` families. Scalars are broadcast against arrays for this screen;
unequal-length arrays are counted separately rather than assigned an inferred
conductor mapping. Input hashes and screening code are archived.

This is a declaration screen, not compiler/schema admission or a collection of
independent feeders. It gives no basis for claiming widespread external speed
benefits. No external operating limit was changed to activate the option.

## Power-cost experiment

Manufactured two- and four-conductor cases retain constant-power demand and a
coupled series line. The receiving neutral is grounded and phase-neutral
magnitudes are fixed at 230 V. The three treatments are one declaration family,
duplicate phase-ground/phase-neutral families, and a fixed-source connection
through an ideal switch. The switch treatment replaces the line and has no
local generator. Other treatments add a single-phase or wye generator with
per-coil bounds ``0\le P_g\le5000`` W, ``|Q_g|\le2000`` var and
``|S_g|\le6000`` VA.

With powers expressed numerically in kW/kvar, the declared linear objective is

```math
f_{\mathrm{lin}}=0.25\sum P_{\mathrm{source}}+0.10\sum P_g.
```

The quadratic objective adds ``0.02\sum P_g^2+0.002\sum Q_g^2``. Coefficients
define currency/hour costs; signed source exports receive the same marginal
credit as imports cost. The source-connected switch case has no controllable
generation and tests representation consistency at fixed demand.

The full panel crosses two conductor layouts, three treatments, two objectives,
1/100 kVA assembly bases, Ipopt `none`/`gradient-based` scaling, three profiles
and three bound policies: **432 attempts**. Profiles are `full_powers`,
`reduced_powers` and `blocks_signed_reuse`, inherited from the mixed-device study.
All use per-unit coordinates, 10 kVA dispatch units and 1 kVA auxiliary power
units. The latter profile additionally uses bounded-observation lifting and
generator reuse. Strict settings are `tol=constr_viol_tol=1e-10`,
`acceptable_iter=0`, `bound_relax_factor=0`, MUMPS AMD, 500 iterations and a
30-second CPU limit. These are diagnostic runs without timing isolation.

The full guarded solve anchors each physical/base/scaling cell. Admission
requires strict termination, physical residuals, own/full model membership,
reverse membership of the anchor, objective agreement (`atol=1e-7, rtol=1e-6`),
reader round trip and rejection after moving all fixed-voltage declarations
0.1% down and 0.1% up. The test suite additionally checks guarded endpoints
against the plain-equality models, including those with optimizer failures.

| Representation | Strict solves | All admission gates |
|:--|--:|--:|
| Separate inequalities | 144/144 | 144/144 |
| Plain equality | 132/144 | 116/144 |
| Guarded equality | 144/144 | 144/144 |

Every plain-equality exclusion occurs with duplicate declarations: 12
`OTHER_ERROR` terminations and 16 `LOCALLY_SOLVED`, physically feasible endpoints
that miss objective agreement (eight per objective). The largest absolute cost
gap is 0.274079 currency/hour, compared with ``1.044\times10^{-8}`` for separate
inequalities and ``1.083\times10^{-14}`` for guarded equalities. Agreement with
a local anchor is not proof of global optimality. The observed status and
objective failures support avoiding these duplicate equality rows; they do not
establish that equality conversion is generally preferable to inequalities.

An earlier 12-solve **unlifted full-model preflight** had two failures in the
four-conductor duplicate case: `LOCALLY_INFEASIBLE` for separate inequalities
and `OTHER_ERROR` for plain equality. The other ten solves passed. These outcomes
are preserved separately: the final panel uses power lifting, so its successful
separate controls do not contradict the unlifted failures. The study does not
isolate every interaction between lifting, fixed variables and solver behavior.

## Independent verification

The full suite passes **137,485 assertions**, including **1,162 new assertions**
for exact identity, fixedness witnesses and 72 guarded power-cost solves. The
initial test parse error and correction remain archived; no acceptance tolerance
was loosened to obtain the final results.

An independent Python audit reads all 420 strict endpoint exports, including the
16 rejected cost comparisons. All pass: 1,632 current margins, 1,656 ungrounded
KCL balances, 828 fixed-voltage channels, 432 ideal-switch channels and 840
two-sided shifted-bound rejection certificates. Maximum KVL and KCL errors are
``7.985\times10^{-10}`` V and ``4.367\times10^{-10}`` A; maximum fixed-voltage
error is ``8.093\times10^{-9}`` V. Maximum line-loss identity error is
``1.921\times10^{-8}`` VA, and objective reconstruction error is
``3.609\times10^{-10}`` currency/hour. Audit thresholds are ``10^{-6}`` V/A,
``10^{-3}`` VA and ``10^{-8}`` currency/hour, declared for this panel.

Physical export structures agree within each conductor/treatment case across
formulations, bases, objectives and solver scaling. All 420 exports also pass
an independent BMOPFTools reader comparison. The 12 solver-error rows retain
their statuses and null objectives; they have no strict endpoint exports.
All raw evidence resides outside Git in `VOLTAGE_EQUALITY_TRANSFER_20261006`.

## Use and reproduction

```julia
build = build_opf(input, IVRNLP(
    coincident_voltage_bounds=:guarded_equality,
    lifting=:powers);
    optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(
    print_level=0, tol=1e-10, constr_viol_tol=1e-10,
    acceptable_iter=0, bound_relax_factor=0.))
@assert result.solve.optimal && physical_residuals(input, result).passed
build.numerical_diagnostics[:coincident_voltage_bound_report]
build.numerical_diagnostics[:voltage_fixed_dependencies]
```

To inspect the motivating duplicate case, include the runner and call
`IVRVoltageDependencyStudy.scenario(conductors=4, treatment=:duplicate)`.
The scenario is manufactured; preserve real input bounds when applying the
option to external data.

```sh
julia --project=test test/ivr_voltage_dependency_tests.jl
julia --project=test examples/benchmark_ivr_voltage_dependencies.jl /tmp/voltage-dependencies/report.json
```

The runner preserves failures and returns a completed report even when some
comparisons fail. Successful process exit is not universal admission. No speed
ranking follows from this study. The [best-evidence shortlist](ivr_performance.md)
and all alternative transformations remain unchanged. Next numerical work
should prioritize isolated Ipopt wall time on representative power objectives,
with compilation excluded, and broader mixed-winding correspondence.
