# Hard-limit OPF and fixed-dispatch power flow

LinDist3Flow has two explicit operating modes. The default is unchanged.

| Contract | `operating_mode=:opf` | `operating_mode=:power_flow` |
|:--|:--|:--|
| Generator/DER P/Q | Optimized within existing constraints | Fixed to an explicit operating point |
| Voltage sources | Balance the network within their remaining constraints | Same |
| Line/transformer/source current and apparent-power limits | Enforced | Monitored, with overload reporting |
| Generator/IBR capability and P/Q bounds | Enforced | Enforced |
| Voltage bounds, nonnegative squared voltages, physics and connectivity | Enforced | Enforced |
| Objective | Selected cost, feasibility or source-import objective | Zero feasibility objective |

This is still the L3F approximation, including its loss and voltage-angle
assumptions. Power-flow mode is not an exact nonlinear AC calculation and does
not guarantee feasibility if a voltage bound, DER capability or electrical
constraint conflicts with the operating point. It changes only the treatment of
supported branch/source thermal limits. The separate `unsupported` policy still
controls preprocessing; `:permissive` projections are not undone by either mode.
These modes currently apply to LinDist3Flow, not the SOC/SDP formulations.

## Usage

```julia
using FormulationLab, Clarabel

# Existing behavior: optimize DER dispatch and enforce thermal limits.
opf = solve_l3f_opf(network, Clarabel.Optimizer;
    options=L3FOptions(operating_mode=:opf, unsupported=:lower))

# Explicit P/Q per generator channel, in watts and vars.
dispatch = Dict("pv1" => Dict("pg" => [3000.0], "qg" => [0.0]))
pf = solve_l3f_opf(network, Clarabel.Optimizer;
    options=L3FOptions(operating_mode=:power_flow, unsupported=:lower),
    dispatch=dispatch)

report = l3f_limit_report(pf)
overloads = filter(row -> row["overloaded"], report["entries"])
```

`dispatch` uses generator IDs **after** the documented IBR lowering. Values must
be finite vectors with one entry per generator power channel, in retained-model
channel order. An optional `terminal_map` is checked against the retained model.
Unknown IDs and malformed vectors are errors. Every omitted generator must
already have equal finite lower/upper P and Q bounds; otherwise the build fails
and names the generator needing a setpoint. No midpoint, zero or nominal dispatch
is guessed by the power-flow API. A network without generators needs no map.

To inspect the required IDs before choosing setpoints, build the default OPF
without solving and inspect `build.network["generator"]`; this includes the
retained channel maps and lowered IBR IDs even if the rated OPF is infeasible.

For a solved operating point, `dispatch=previous_result.generators` is convenient
when the retained IDs and channel maps match. Passing a dispatch in OPF mode is
an error, to avoid silently changing the optimization problem. A P/Q point that
violates retained capability limits remains infeasible: fixing dispatch does not
remove those bounds. Fixed dispatch is recorded as input metadata in
`pf.formulation["fixed_dispatch"]`; `pf.generators` contains the solved outputs
under the usual successful-solve contract.

The generic API also forwards dispatch:

```julia
pf = solve_opf(network,
    LinDist3Flow(operating_mode=:power_flow, unsupported=:lower);
    optimizer=Clarabel.Optimizer, dispatch=dispatch)
```

## Report contract

[`l3f_limit_report`](@ref) works on a solved `L3FBuild` or `L3FResult`. Results also
carry the report at `result.formulation["operating_limits"]`, alongside the mode,
dispatch policy and `branch_limits_enforced` flag. The report contains:

- `status`: `within_monitored_limits`, `overloaded`, or `unavailable`.
- `monitored_count`, `overload_count`, `enforced`, and the explicitly stated scope.
- One entry per supported thermal cone with semantic `family`/`key`, `quantity`,
  SI `unit`, `limit`, evaluated `value`, `loading_ratio` and `overloaded` flag.
- Evaluated power and allowed power in VA for each check. Current uses the live
  L3F voltage and power closure, not the reference voltage alone.

Nameplate reports are per modeled coil where that is the formulation's contract;
open-delta winding powers are converted back from their terminal-power proxy.
Keys preserve physical endpoint/channel identity and lowered branch IDs; switch
lowering findings map derived line IDs back to input switch IDs. Reported limit
counts are **checks**, not counts of overloaded assets: two ends or multiple
phases can report the same line.

For `p²+q² ≤ w Imax²`, the loading ratio is
`hypot(p,q) / (sqrt(w) Imax)` in consistent coordinates. The stored model cone
also supplies the appropriate winding-voltage closure. Apparent-power loading is
`hypot(p,q)/Smax`. The default relative tolerance is `1e-6`, plus a `1e-6 VA`
absolute floor on power-transfer comparison. Zero capacity can make ratios or
current estimates undefined (`nothing`), while a positive transfer still reports
an overload. No infinity is required in those report fields.

Before an optimal feasible solve, or for an infeasibility certificate, the report
is `unavailable` with no evaluated entries. A converged overloaded power flow
can therefore be solver-feasible while `branch_limits_enforced=false` and
`status="overloaded"`. Neither `within_monitored_limits` nor successful solver
termination is an AC-feasibility certificate.

## IEEE 9500 check

The committed example `examples/run_ieee9500_operating_modes.jl` uses a clearly
named dispatch scenario: preserve fixed P/Q bounds; for adjustable DER choose
upper active bounds and reactive power closest to zero within bounds. It writes
all 190 generator/DER setpoints to a separate dispatch JSON. That selection is
specific to the experiment and is not an API default or a claim about the source
deck's controllers.

At that identical fixed point, hard-limit OPF is infeasible. Power-flow mode is
optimal and reports 49 overload checks: 43 line-current and six center-tap
nameplate checks, out of 15,246 monitored checks. The worst receiving-line check
is about 291.70 A against 195 A (1.496 times the limit). Native Clarabel times
were 0.647 s and 0.133 s respectively in single runs; this is not a timing
benchmark or a relaxation-gap comparison. DER capability limits remain SOCPs,
so power-flow mode need not be an LP.

Results and explicit dispatch are in
`examples/results/ieee9500_operating_modes_2026-09-12.json` and its
`.dispatch.json` companion. The earlier 57-check unrated diagnosis used adjustable
DER and a different point; the 49-check count is not a correction to that record.

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test examples/run_ieee9500_operating_modes.jl /tmp/ieee9500_final.json /tmp/9500-modes.json
```

## API

```@docs
l3f_limit_report
```
