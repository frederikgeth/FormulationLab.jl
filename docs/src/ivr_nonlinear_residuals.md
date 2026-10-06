# Original nonlinear laws and operating-limit residuals

## Purpose and scope

A small residual in one normalized nonlinear row does not, by itself, establish
that the original physical law is satisfied. Exact auxiliary definitions must
also hold. This matters when power columns, load-law rows and voltage observations
use different units. The read-only helper
`examples/ivr_nonlinear_residual_trace.jl` reports the native residual, the
original SI residual and the auxiliary discrepancies that connect them.

This is a **partial provenance catalogue**. It covers constant-power,
constant-current, ZIP and exponential load power laws, plus every original bus
voltage-bound declaration, and equipment current/apparent-power limits. Constant-impedance loads are identified separately;
their equations belong to the [linear circuit catalogue](ivr_circuit_residuals.md).
Other constraints are enumerated as outside this catalogue. These include
KCL, other circuit rows, generator dispatch definitions and boxes,
IBR availability/DC/internal-voltage limits and generic lifting definitions.
“Outside scope” does not mean that a constraint is absent from the model.
`complete_model_coverage` is deliberately `false`.

Recording provenance introduces no variables, constraints, coefficients,
objectives or starts. It changes neither feasibility nor the physical result
export schema. Every transformation option remains available. This work is
about residual interpretation and coverage, not a performance ranking.

## Load-law correspondence

For original coil voltage and current rows ``a_v,a_i`` and reconstructed native
state ``z=Ry``, the physical quantities are

```math
U=V_b a_vz,\qquad I=I_b a_iz,\qquad S=U\overline I.
```

Let ``P`` denote either ``\Re S`` or ``\Im S``, with units W or var, respectively.
The declared demand is ``P_0 f(x)`` where ``x=|U/V_0|^2``. The functions are

| Law | ``f(x)`` |
|:--|:--|
| Constant power | ``1`` |
| Constant current | ``\sqrt{x}`` |
| ZIP | ``a_zx+a_i\sqrt{x}+a_p`` |
| Exponential | ``x^{\gamma/2}`` |

P and Q use their own declared coefficients. No nominal-voltage floor, epsilon
or clipped observation is introduced. Nonlinear evaluations outside their
finite nonnegative voltage-square domain are refused. The compiler's existing
positive engineering voltage-domain requirement remains unchanged.

For row multiplier ``\lambda>0``, a native load-law equality has the form

```math
r_n=\lambda\left(\widetilde P/S_b-P_0f(\widetilde x)/S_b\right).
```

Here ``\widetilde P`` may be a power auxiliary and ``\widetilde x`` a voltage-square
auxiliary. The stored row has the exact declared SI conversion ``S_b/\lambda``.
This is a row conversion, not a bound on the entire reconstructed physical law.
Define the discrepancies

```math
\Delta_P=\widetilde P-P,\qquad
\Delta_D=P_0\left[f(\widetilde x)-f(x)\right].
```

Then, in exact arithmetic,

```math
r_{\mathrm{physical}}
=P-P_0f(x)
=(S_b/\lambda)r_n-\Delta_P+\Delta_D.
```

The trace evaluates all four terms and reports their numerical reconciliation
error. It computes physical power from the original voltage/current rows,
bypassing observation and power auxiliaries. At an assignment violating an
auxiliary definition, the physical and native residuals can therefore differ.
For example, an auxiliary of 1,000 W can satisfy a 1,000 W native load law while
the reconstructed electrical power is 1,150 W. The missing 150 W appears in the
power-definition discrepancy. Such an assignment violates the complete model;
checking the native law alone would overlook it.

These are Float64 diagnostics of the stored model. They are not interval
certificates, bounds over a coordinate domain, proofs of global optimality or
bounds on pre-rounding physical data. In particular, a nonlinear demand error
cannot be replaced by a universal voltage-to-power multiplier without a justified
domain and derivative bound. The separate
[implied-row certificates](ivr_implied_residuals.md) have a narrower linear scope.

## Original voltage declarations and emitted constraints

The compiler records one entry for each declared channel of `v_min`, `v_max`,
`vpn_min`, `vpn_max`, `vpp_min`, `vpp_max`, `vn_max`, `vpos_min`, `vpos_max`,
`vneg_max` and `vzero_max`. Each entry retains the original row, limit in volts,
lower/upper sense and references to the actual emitted constraints.

| Recorded form | Constraint correspondence |
|:--|:--|
| `magnitude_lower`, `magnitude_upper` | One normalized squared-magnitude inequality |
| `zero_upper` | Real and imaginary zero equalities |
| `identically_zero_upper` | No row is needed for an identically zero observation |
| `nonnegative_magnitude` | A zero lower bound is a tautology |
| `coincident_equality` | Both original bounds reference the same exact equality |
| `shared_equality` | A further coincident pair references an existing guarded equality |

Source-fixed or circuit-fixed pairs retained as inequalities still have separate
original records. Counting declarations and counting emitted constraints are
therefore different operations. Shared rows do not erase the declarations they
represent. The catalogue includes the voltage-square load definitions and their
derived variable bounds when counting covered constraints, and deduplicates
shared references.

For an original observation, the report gives its magnitude, limit, slack and
violation in volts. Positive slack denotes satisfaction. The native constraint
residuals remain separate: squared-magnitude constraints have no constant
conversion to a magnitude error in volts. A positive native violation at a
perturbed observation auxiliary can coexist with zero original voltage
violation. Conversely, inspecting an auxiliary without its defining equation
can miss a physical violation.

## Equipment declarations and rating conventions

Equipment entries are recorded when the original network is assembled, before
coordinate reduction. Each retains a `source_path` into the input network,
`source_channel` (or `nothing` for a scalar), `declared_value`, applied divisor,
physical channel, voltage/current basis, and actual emitted constraint
references. Inheritance is recorded per field: a line's explicit `i_max` can
override its linecode while its `s_max` still comes from that linecode.
Equivalent or zero rows cannot identify this provenance reliably by themselves.

| Equipment | Current limit | Apparent-power limit |
|:--|:--|:--|
| Line, both ends | Terminal current, including end shunts | Phase terminal-to-ground voltage times conjugate terminal current |
| Fixed switch, both ends | Terminal current | Terminal-to-ground voltage times conjugate terminal current |
| Generator | Declared coil or terminal arity; delta coil convention takes precedence | Connection-coil power |
| IBR | Declared coil or terminal arity | Connection-coil power for WYE/single-phase; conductor PCC power for three-leg delta |
| Voltage source | Supported terminal currents | Non-neutral terminal powers |
| Ordinary transformer | Delta series-coil current; otherwise terminal current | Existing opt-in `s_rating` convention |
| N-winding transformer | Series-coil current | Coil voltage times conjugate series-coil current |

An ordinary transformer's terminal current may include excitation, grounding
and bond contributions. It must not be substituted for a delta series-coil
current. Under the BMOPFTools nameplate policy, mixed delta–WYE nameplates use
three equal shares on the WYE side with phase terminal currents; the other
supported ordinary transformer types use the existing per-coil nameplate
interpretation. For n-winding transformers, a scalar `s_max` means equal shares
of the winding total under `:bmopftools`, and a per-coil cap under `:ignore`.
A vector is per-coil under both policies. Scalar current caps remain per-coil.
These are the compiler's existing conventions; provenance does not redefine them.

Under `transformer_nameplate=:ignore`, ordinary transformer nameplates remain
visible in `inactive_nameplates`. They are not enforced operating limits under
that policy. This differs from an enforced but identically satisfied limit.
Open-switch zero-current bounds, for example, retain equipment declarations
with `form=:identically_zero_upper` and no emitted row. A zero upper limit on
a nonzero observation references its two real/imaginary equality constraints.

For a current bound, let ``w=I_b a_i z``; for a power bound, let
``w=(V_b a_v z)\overline{(I_b a_i z)}``. The trace evaluates

```math
m=|w|,\qquad \sigma=L-m,\qquad \nu=\max(-\sigma,0).
```

Here ``L`` is the applied SI limit; ``\sigma`` and ``\nu`` are slack and
violation in A or VA. The separately reported `observation_gap_SI` is
``|\widetilde w-w|`` and includes both real and imaginary discrepancies, even
when two observations have equal magnitudes. Native normalized squared rows
remain separate: there is no constant multiplier converting their residual to
an SI magnitude violation. The original rows bypass all observation auxiliaries.
This separation helps diagnose a misleadingly small native bound residual.

## Tutorial

The following single-phase example solves a ZIP load, then inspects an
auxiliary-only perturbation without changing the physical state or re-solving.

```@example nonlinear_trace
using FormulationLab, JuMP, Ipopt
include(joinpath(pkgdir(FormulationLab), "examples", "ivr_compiler_cases.jl"))
include(joinpath(pkgdir(FormulationLab), "examples", "ivr_nonlinear_residual_trace.jl"))
T = IVRNonlinearResidualTrace
net = ivr_compiler_case(conductors=2, segments=1)
d = net["load"]["d1"]
d["model"] = "zip"
d["v_nom"] = [230.0]
for prefix in ("alpha", "beta"), (suffix, coefficient) in zip(("z", "i", "p"), (0.2, 0.3, 0.5))
    d[prefix * "_" * suffix] = [coefficient]
end
options = IVRNLPOptions(s_base=1e5, load_power_lifting=true,
    load_power_base=500.0, load_power_row_scaling=:both, load_power_row_base=100.0)
build = build_opf(net, IVRNLP(options); optimizer=Ipopt.Optimizer)
result = solve_ivr_nlp_opf(build; solver_options=(print_level=0, tol=1e-10,
    constr_viol_tol=1e-10, acceptable_iter=0, bound_relax_factor=0.0))
@assert result.solve.optimal && physical_residuals(net, result).passed
original = T.trace(build)
@assert !original.complete_model_coverage
assignment = Dict(v => value(v) for v in all_variables(build.model))
coordinate = first(values(build.model.ext[:ivr_load_law_rows])).voltage_coordinate
assignment[coordinate] *= 1.01
perturbed = T.trace(build; variable_values=assignment)
@assert [q.physical_residual_SI for q in original.loads] ==
        [q.physical_residual_SI for q in perturbed.loads]
@assert maximum(abs(q.native_residual_SI) for q in perturbed.loads) > 1.0
@assert maximum(abs(q.reconciliation_error_SI) for q in perturbed.loads) < 1e-7
(length(original.loads), length(original.bounds), original.complete_model_coverage)
```

`T.catalog(build)` provides original row and constraint references for inspection.
`T.trace(build, point)` instead encodes a supplied `ACPoint`; missing channels
are refused. A complete assignment can be infeasible, which is useful when
investigating auxiliary discrepancies. Constant-power load updates read current
network targets and current constraint right-hand sides, so the trace does not
retain stale demand values. An absent upper engineering voltage bound is
reported as `nothing`, allowing strict JSON serialization of the diagnostic
report. These reports are separate from BMOPFTools-compatible physical results.


The same catalogue explains an inherited line-current rating in this solved
single-phase model. This diagnostic is separate from the canonical result JSON.

```@example nonlinear_trace
using JSON3
line_limits = filter(q -> q.family == :line && q.field == "i_max", original.equipment)
@assert length(line_limits) == 4 # two conductors at both ends
@assert all(q -> q.source_path == ("linecode", "wire", "i_max"), line_limits)
@assert all(q -> q.violation_SI < 1e-8, line_limits)
@assert all(q -> q.observation_gap_SI < 1e-8, line_limits)
encoded = JSON3.write(original)
@assert length(JSON3.read(encoded).equipment) == length(original.equipment)
[(label=q.label, origin=q.source_path, limit_A=q.limit_SI,
  current_A=q.magnitude_SI, slack_A=q.slack_SI) for q in line_limits]
```

## Verification and remaining coverage

Independent manufactured states span single-phase, three-wire delta and
four-wire WYE loads; three voltage-dependent laws; direct and lifted powers;
independent row units; and full/reduced coordinates. Auxiliary perturbations
leave original physical residuals unchanged and satisfy the reconciliation
identity within the tested floating-point tolerance. Every bus voltage-bound
family is tightened and compared with the independently evaluated original
network. Further tests cover zero limits, fixed magnitude domains, shared
coincident rows, constant-power updates and strict JSON without infinite values.

The next coverage extension is generator/source/IBR dispatch boxes and IBR
availability/DC/internal-voltage constraints. Those families remain enforced
and independently audited today, but this constraint-reference catalogue does
not yet describe them. A
complete emitted-row inventory must also distinguish original physical laws
from auxiliary definitions and fixed native coordinates.

### Controlled evidence, 7 October 2026

Canonical solver-model fingerprints match the preceding commit in all **108**
cases crossing conductor count, load law, lifting/row units and interval,
coincident or duplicate voltage declarations. The fingerprints include every
scalar constraint function and set, variable identity/name/start, objective and
sense; stored numeric coefficients are compared by bit pattern. This supports
the intended metadata-only change on that panel, not a proof for all inputs.

A separate **24-case** live panel crosses two/eight non-star multiwinding units,
cost/tracking power objectives, explicit/eliminated multiwinding currents and
powers/coils/all observation lifting. All original physical, own/full-model,
reverse-anchor and independent winding-equation gates pass. It reports 2,160
load P/Q rows and 6,480 original voltage declarations. Independent checks compare
1,080 complex load residual aggregates and 2,160 voltage-bound field aggregates.
The largest load discrepancy is below ``5.6\times10^{-14}`` VA; voltage-limit
violation differences are zero. Maximum load-law reconciliation error is below
``4.8\times10^{-14}`` VA. These are observed discrepancies, not guaranteed error
bounds.

All 24 canonical SI exports pass both FormulationLab and BMOPFTools readers.
Every physical leaf path agrees across tested formulations at each network
size. The 2,160 exported load P/Q values agree with the independently reconstructed
trace powers to below ``5.7\times10^{-14}`` VA. No schema field was added to the
physical result contract by this provenance catalogue. The initial experiment
script incorrectly used a generic JSON writer on a canonical result containing
a legacy NaN; switching to `write_result` preserved the existing result contract.
That failed attempt and its partial file are retained.

All data, model fingerprints, development failures and validation logs are
outside Git in `NONLINEAR_PROVENANCE_20261007`. The live panel is deliberately
correctness evidence; it supplies no wall-time ranking and changes no numerical
recommendation.

### Equipment extension evidence, 7 October 2026

The equipment extension passes **4,420 targeted assertions**. Manufactured
states compare tightened limits against the independent original-network
auditor across two-, three- and four-conductor circuits, line shunts,
forward/reverse switch and IBR flows, all six ordinary transformer types,
scalar/vector winding ratings and both nameplate policies. Full/reduced
coordinates, two assembly power bases and direct/lifted observations are
included. Zero limits, open-switch tautologies, strict diagnostic JSON and an
auxiliary-only perturbation have separate checks.

All **222** solver-model fingerprints match commit `2924367`, including 114
additional equipment cases. The 24-case live panel retains the preceding
physical and export gates and traces **13,296 equipment declarations**.
All **4,416** aggregate equipment-violation comparisons agree with the independent
SI auditor, with zero observed discrepancy. The live solutions are feasible;
the manufactured tightened-limit tests provide the complementary nonzero
violation evidence. Every canonical export passes both readers, and physical
leaf paths remain invariant across formulations at each network size.

The initial development checks exposed a switch audit-label mismatch, an
islanded open-switch test fixture and standalone-driver errors. These were
corrected without changing the electrical equations. The failures, revised
scripts, fingerprints, full test logs and raw records are retained outside Git
in `EQUIPMENT_LIMIT_PROVENANCE_20261007`. This extension supplies no performance
ranking and leaves `complete_model_coverage=false`.
