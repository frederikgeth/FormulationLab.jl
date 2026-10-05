# Objectives expressed in physical power

## Existing evidence and the expanded contract

Earlier transformer, grounding and power-base timing studies used
`objective=:source_import`: minimize the **signed** sum of voltage-source active
powers. Export has negative cost in that objective; it is not a positive-part
import tariff or loss minimization when generation can change. Earlier external
feeder studies often used `:feasibility`. The regression suite also exercised
linear `:cost`, price updates, negative generation prices and IBR availability.
Those studies do not establish performance under quadratic dispatch costs or
reactive-power tracking.

`objective=:power` adds explicit affine/quadratic objectives in physical power
channels. The existing three modes remain unchanged:

| Mode | Physical expression | Reported objective units |
|---|---|---|
| `:feasibility` | Zero | Dimensionless |
| `:source_import` | Sum of source active powers | W |
| `:cost` | Sum of source, generator and IBR active powers times linear energy prices, divided by 1000 | Currency/h |
| `:power` | Sum of explicitly supplied `IVRPowerTerm` expressions | User-defined by coefficients |

Legacy cost includes each device's native connection channels, with the existing
`cost` / `energy_cost_rate` alias rules. A snapshot cost has no time integration.
`:power` replaces that objective; it does **not** silently add legacy prices.

## Definition and units

For a term \(t\), choose active power \(P\) or reactive power \(Q\), a channel
list \(C_t\), weights \(w_{tk}\), target \(r_t\), and coefficients \(a_t,b_t\):

```math
x_t=\sum_{k\in C_t}w_{tk}X_k-r_t,\qquad
F=\sum_t(a_tx_t+b_tx_t^2),\qquad b_t\ge0.
```

Here \(X_k\) is in W for `quantity=:p` or var for `quantity=:q`. Targets have
the same units as their weighted sums. The coefficients must make the terms
dimensionally compatible. A quadratic price stated per kW squared therefore
needs a factor of \(10^{-6}\) when supplied as a coefficient on W squared.
The target offset remains part of the reported objective, including in affine
terms. Squaring an aggregate is different from summing individual squares; the
API preserves the distinction. P and Q are selected separately per term.

Each channel is `(family, id, index)`, with a **one-based native power-channel
index**, as in `result.powers[(family,id)][index]`. Generator delta indices are
coils. THREE_LEG IBR terminal powers use their existing conductor convention;
`:ibr_internal` uses the modeled internal winding/filter channels. Source and
line indices follow their declared terminal maps. Transformer IDs include their
kind, for example `"delta_wye/downstream1"`. Inspect `build.powers` for available
families and channel counts; a finite-ground shunt stamped directly in KCL need
not have a separate entry there. Unknown families, IDs, out-of-range indices,
empty/mismatched channel lists, nonfinite data and negative quadratic
coefficients are refused. Duplicate channels are summed with their supplied
weights. Supplying `power_terms` in another objective mode is refused.

```julia
terms = [
    # Generation cost: 0.10 currency/kWh plus 0.02 currency/(kW² h).
    IVRPowerTerm(channels=[(:generator,"g",1)],
        linear=0.10/1000, quadratic=0.02/1e6),
    # Total source reactive exchange tracking; weight chosen by the user.
    IVRPowerTerm(channels=[(:voltage_source,"grid",k) for k in 1:3],
        quantity=:q, target=0., quadratic=1e-6),
]
formulation = IVRNLP(objective=:power, power_terms=terms, objective_scale=1.)
```

The example's two terms are an explicit weighted trade-off; its reactive penalty
is not an energy price inferred by the package. Nonnegative quadratic coefficients
do not make the AC OPF convex. No global certificate follows from local Ipopt
acceptance.

## Scaling, exact reformulations and reuse

The solver minimizes \(F/d\), where `d=objective_scale` or, if omitted,
`d=s_base`. The same positive scalar is reversed during solve extraction and
supplied-point evaluation. Changing \(d\) preserves mathematical minimizers,
but may change numerical stopping behavior. Fix it when comparing electrical
power bases for a given objective; do not equate different objectives' values
or choose a normalization by comparing their timings directly.

The compiler reconstructs physical power as \(S_{\mathrm{SI}}=S_bS_{\mathrm{pu}}\)
through the existing inverse coordinate maps. Generator terms use the existing
explicit dispatch P/Q variables. Other selected ports use their exact power
expressions. With lifting off, squared power can be quartic in phasor variables.
With `lifting=:powers` or `:bounded_observations`, selected non-generator powers
use the existing exact P/Q definitions and caches. Objective lifts participate
in start encoding and supplied-point validation. This is an exact graph
extension, not a relaxation, and can increase rather than decrease solver time.

The build owns a deep copy of term lists, channel lists and weights. Supported
load and generator-bound updates preserve the objective definition. A `cost`
update changes only legacy `:cost`; it does not rewrite a custom power term.
Targets, weights and coefficients are fixed for the build: rebuild to change
them through this API. Direct mutation of `build.options` is unsupported.
In particular, an affine curtailment term `available - P` does not automatically
change its declared availability when a dispatch bound changes, and it is not
the nonsmooth expression `max(available-P,0)`.

SI JSON output keeps the same physical variables and recovery rules. Under
`:power`, `_formulationlab.objective_units` is `"user_defined"`, and
`objective_definition` records the physical terms in the solve snapshot. User
coefficients determine whether the result represents currency/h, W, a normalized
tracking penalty, or another compatible measure. The network hash alone cannot
identify a custom objective; retain this definition alongside the input.

## Six motivating workloads

`examples/benchmark_ivr_power_objectives.jl` supplies these cases on the
manufactured unbalanced transformer-leakage network:

| Workload | Objective | Purpose |
|---|---|---|
| `:linear_cost` | Source and generator linear prices | Economic dispatch under the legacy contract |
| `:quadratic_cost` | Source linear price plus generator linear/quadratic prices | Marginal-cost dispatch |
| `:dispatch_tracking` | Individual P/Q target errors | Controllable generator setpoints |
| `:exchange_tracking` | Aggregate source P/Q errors plus weaker individual dispatch penalties | Grid-interface exchange control |
| `:curtailment` | Sum of available-minus-generated active power, plus Q penalties | Generation utilization with reactive effort |
| `:losses` | Source plus generator P minus load P | Total passive-network active losses |

All cases permit bounded generator Q and retain original voltage, current and
capability limits. The loss-only case additionally caps each generator at 70%
of its colocated load so that local supply cannot trivially eliminate every
feeder current. This declared input change is specific to that workload; rankings
are always within one workload. The balance loss expression includes line,
transformer and finite-ground dissipation on this passive circuit. For a circuit
with converters or additional devices, include every relevant port with its
documented sign and distinguish converter losses from network losses. Do not
infer a general loss expression from an incomplete source-minus-load sum.

Six retained candidates combine common 1/10 kVA and regional current bases with
full IVR or conductor/passive-block/transformer-current reductions and optional
power/observation lifting. They are formulation bundles: differences do not
isolate the causal effect of a single option. The runner checks the entire power
objective definition before comparing candidates, not merely the `:power` label.
See the [executable tutorial](tutorial_exact_ivr.md) and
[verification record](verification.md) for analytic and physical checks.

## Confirmed workload comparison — 5 October 2026

The six workloads each receive six excluded warm-ups followed by twelve balanced
rotated/reversed sweeps, with every candidate appearing twice in every position.
A fresh process repeats the complete panel; results are not pooled. All
**864 measured solves and 72 warm-ups** pass original SI feasibility, own/full
model checks, reverse-anchor membership and physical-objective agreement. For
custom objectives, recomputation from recovered SI powers agrees with the
reported objective within 1.7e-9 in the declared objective units. Maximum
within-workload disagreement is below 1.2e-11. These tiny differences are numerical
agreement, not proof of global AC optimality.

Settings are MUMPS AMD, one Julia thread, one BLAS thread, explicitly disabled
Ipopt automatic NLP scaling, strict tolerance 1e-10 and the shared unloaded SI
start. Electrical coordinates are per unit. The objective divisor is 1 for
costs/tracking/curtailment and 10,000 for losses, fixed across formulations within
each workload. Tests, diagnostics and documentation builds never overlap timing.
Only Ipopt wall time ranks candidates; compilation, extraction and audits are
excluded. The raw environment and all solver options are recorded in JSON.

Confirmation median Ipopt wall time, milliseconds:

| Workload | Full 10 kVA | Full 1 kVA | Full regional | Reduced 10 kVA | Reduced 1 kVA + powers | Reduced regional + observations |
|---|---:|---:|---:|---:|---:|---:|
| `linear_cost` | 11.591 | 11.882 | 11.498 | 10.676 | 10.503 | 9.382 |
| `quadratic_cost` | 10.220 | 10.893 | 10.058 | 9.384 | 9.948 | 8.484 |
| `dispatch_tracking` | 10.772 | 10.862 | 9.428 | 9.933 | 9.912 | 9.615 |
| `exchange_tracking` | 8.922 | 8.394 | 9.098 | 8.388 | 7.706 | 8.391 |
| `curtailment` | 9.200 | 9.270 | 9.085 | 7.181 | 8.206 | 7.496 |
| `losses` | 9.042 | 9.733 | 8.925 | 8.281 | 8.910 | 7.218 |

Relative to full 10 kVA, the fastest bundle improves linear cost by **19.1%**,
quadratic cost by **17.0%**, individual dispatch tracking by **12.5%**, aggregate
exchange tracking by **13.6%**, curtailment by **21.9%**, and losses by **20.2%**.
The winner depends on the workload: reduced regional with observation lifting
for cost and losses; full regional for individual tracking; reduced 1 kVA with
power lifting for exchange tracking; reduced 10 kVA without lifting for
curtailment. In particular, source-import scaling results cannot select the
fastest economic-dispatch formulation automatically.

The three full candidates have 486 real variables and reduced 10 kVA has 116.
Power lifting gives 128–146 variables and observation lifting gives 320–338,
depending on the selected objective ports. More reduction does not always win:
full regional is fastest for individual tracking, while the larger observation
lift beats the 116-variable reduction on cost. Iterations alone also mis-rank
these candidates: the winning linear-cost observation lift takes 18 iterations
versus 16 for full 10 kVA. These are measured bundle effects; no individual
scaling/lifting mechanism or KKT-factorization cause is established.

All tails remain. Exchange-tracking winner/baseline paired timing ratios range
from 0.490 to 1.545 despite unchanged per-profile iteration counts; no cause is
assigned and neither extreme is presented as representative. All twelve paired
ratios for the other workload winners are below 0.923. No default is promoted
from this manufactured single-network panel or single automatic-scaling policy.

Reproduce with `IVRPowerObjectiveStudy.benchmark`. Protocol, frozen code/input,
raw trials, confirmation, objective audits and validation logs are retained
outside Git in `POWER_OBJECTIVES_20261005`. An export-only correction found after
these timings fixes explicit objective normalization for **unaccepted diagnostic
primals**. Every timed solve was accepted, so that branch was never used by the
campaigns. Final regression tests cover both paths.

## Independent economic-dispatch oracle

A fixed-voltage, two-generator circuit supplies 3000 W and 600 var, with source
P/Q fixed to zero. Its objective is

```math
F=0.001P_1+10^{-6}P_1^2+2\,10^{-6}P_2^2
  +10^{-6}Q_1^2+3\,10^{-6}Q_2^2.
```

On the original boxes, eliminating the affine balances gives
\(P_1=(4\,10^{-6}P_D-0.001)/(6\,10^{-6})\), \(P_2=P_D-P_1\),
\(Q_1=3Q_D/4\), \(Q_2=Q_D/4\). Hence the optimum is
\((1833.333\ldots,1166.666\ldots)\) W and \((450,150)\) var.
The reduced Hessian is positive, and the stationary point lies inside the boxes;
this simple oracle has a global certificate independent of Ipopt. A subsequent
1000 W cap on generator 1 binds; a later load update changes both balances.
The tests verify the resulting analytic dispatches and objectives over assembly
bases of 1 and 1000 kVA, two objective divisors and all three lifting modes.
These guarantees apply to this affine fixed-voltage case, not to the coupled
unbalanced AC benchmark.

The present objective contract covers sums of affine terms and nonnegative
squared weighted P sums or Q sums. Piecewise import/export tariffs, P–Q cross
terms in a single square, and intertemporal objectives require further API work.

## API

```@docs
IVRPowerTerm
```
