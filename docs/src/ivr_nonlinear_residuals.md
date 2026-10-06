# Original load-law and voltage-bound residuals

## Purpose and scope

A small residual in one normalized nonlinear row does not, by itself, establish
that the original physical law is satisfied. Exact auxiliary definitions must
also hold. This matters when power columns, load-law rows and voltage observations
use different units. The read-only helper
`examples/ivr_nonlinear_residual_trace.jl` reports the native residual, the
original SI residual and the auxiliary discrepancies that connect them.

This is a **partial provenance catalogue**. It covers constant-power,
constant-current, ZIP and exponential load power laws, plus every original bus
voltage-bound declaration. Constant-impedance loads are identified separately;
their equations belong to the [linear circuit catalogue](ivr_circuit_residuals.md).
Other constraints are enumerated as outside this catalogue. These include
KCL, other circuit rows, generator dispatch definitions and boxes, equipment
current/apparent-power ratings, IBR capabilities and generic lifting definitions.
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

## Verification and remaining coverage

Independent manufactured states span single-phase, three-wire delta and
four-wire WYE loads; three voltage-dependent laws; direct and lifted powers;
independent row units; and full/reduced coordinates. Auxiliary perturbations
leave original physical residuals unchanged and satisfy the reconciliation
identity within the tested floating-point tolerance. Every bus voltage-bound
family is tightened and compared with the independently evaluated original
network. Further tests cover zero limits, fixed magnitude domains, shared
coincident rows, constant-power updates and strict JSON without infinite values.

The next coverage extension is original equipment current/apparent-power
ratings, generator/source dispatch boxes and IBR capability/DC/internal-voltage
constraints. Those families remain enforced and independently audited today,
but this new constraint-reference catalogue does not yet describe them. A
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
