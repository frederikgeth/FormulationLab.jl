# Why use exact IVR and reusable models?

These examples motivate different research questions. Each separates a physical
hypothesis from an implementation benefit and a measurable acceptance criterion.
All cases are synthetic, require no external dataset and run in
`examples/tutorial_exact_ivr.jl`. The [tutorial](tutorial_exact_ivr.md) executes
them during documentation builds; the [theory chapter](ivr_theory.md) gives the
underlying equations and equivalence assumptions.

![Two-wire service with a grounded source neutral and floating load neutral.](assets/ivr_two_wire.svg)

*Figure 1. Analytical operating point of the tutorial service. Values are rounded;
all equation checks use unrounded phasors.*

## A. Neutral displacement in a single-phase service

A 230 V source supplies a 2 kW, unity-power-factor load through a 0.2 Ω phase
conductor and a 0.3 Ω neutral conductor. The source neutral is grounded; the
load neutral is not. With zero mutual impedance and zero line shunts, the loop
resistance is ``R=0.5\ \Omega``. The higher-voltage solution is

```math
u=\frac{230+\sqrt{230^2-4(0.5)(2000)}}{2},\qquad
I=\frac{2000}{u},\qquad U_n=0.3I.
```

This gives about 225.567 V phase-neutral, 2.660 V neutral-ground, 8.867 A and
39.308 W of conductor loss. The second quadratic root is excluded by the
180 V phase-neutral lower bound. A 1 V neutral-ground limit rejects this
operating point although the phase-neutral voltage is within its bounds.

**Question.** Can a reduced representation retain neutral displacement and
its constraint? The two-wire specialization keeps the neutral voltage, removes
one redundant current coordinate and reproduces the analytical state. The
negative example tightens only `vn_max` and evaluates the **unchanged** state
in both independent physics and compiled-model checks. No optimizer can hide
a missing bound by returning a different point.

## B. One algebra for two, three and four wires

Two-wire phase-neutral, three-wire delta and four-wire unbalanced wye sections
can all have zero-sum conductor current. Their difference bases have respectively
one, two and three rows. A delta winding connection and a network coordinate
change serve different purposes: the latter does not replace a delta device
with a wye device or remove its internal circulation.

**Question.** Does the representation preserve the feasible set and objective
in each connection family? The tutorial solves full and reduced forms, checks
each resulting physical point in the opposite model, and records variable
counts. For its one-line two-wire example, real JuMP variables fall from 14 to
12. Its three-line three-wire and four-wire examples fall from 66 to 60 and
78 to 72 respectively. These are model counts before solver presolve, including
fixed variables; they are not runtime measurements.

A downstream 1 mS phase-earth shunt provides a counterexample to the current
identity. Requested specialization falls back to the full formulation with
`:bus_shunt`, retaining the admittance and its physical currents. This is a
successful scope check, not a failed network solve.

## C. Repeated demand and local generation studies

A sensitivity study often changes demands while preserving topology, equipment,
source phasors and limits. Rebuilding the electrical model for every point is
avoidable. In the tutorial, demand increases from 1 to 2 to 3 kW. Reusing the
model changes constant-power right-hand sides; fresh builds of independently
edited input copies provide a comparison. Source imports are approximately
1009.635, 2039.308 and 3090.262 W, reflecting increasing line losses.

**Question.** Is avoiding construction useful without changing the OPF?
The example checks identical JuMP variable identities, one assembly, three
updates, matching objectives and feasible supplied states in both directions.
It does not claim warm starts, factorization reuse or speedup from three tiny
solves. Use the matched [benchmark runners](ivr_nlp.md) to measure those study
costs on a chosen network and scenario count.

A separate price experiment adds a bounded generator and prices **both** the
source and generator. A local price of 0.1 currency/kWh against a source price
of 0.2 makes the 600 W generator cap active; changing the generator price to
0.5 moves dispatch to approximately zero. The tutorial independently rebuilds
the cost from physical powers. A source colocated with a priced generator is
not automatically consolidated; omitted source pricing can change the intended
optimization problem.

## D. An inverter's internal budget is not its PCC output

Add a single-phase static converter to the same service. Give it a 600 W PCC
availability limit, a 500 W internal active-power limit, 0.2 Ω filter resistance
and zero filter shunt susceptance. Reactive PCC power is fixed at zero.
Minimizing source import produces approximately 499.031 W at the PCC and
500 W internally; about 0.969 W is dissipated in the filter.

**Question.** Are equipment constraints applied at the intended physical port?
The example independently checks
``P_{\mathrm{int}}-P_{\mathrm{PCC}}=r_f|J_f|^2``. Applying the 500 W cap only
to PCC output would admit a different operating domain. This example establishes
the native static contract; it contains no controller, external DC network,
storage energy balance or temporal coupling. Repeated snapshots alone do not
supply those missing equations.

## E. Fixed voltage regulation and the output-current limit

Replace the tutorial service line with an ideal single-phase type-B
regulator at fixed tap 1.04. Its common conductor is bonded and its source
neutral is grounded. With no leakage or excitation, the 2 kW load sees
239.2 V and draws approximately 8.361 A. Source import is still 2000 W;
voltage regulation has changed current, not created energy.

**Question.** Does the model retain the correct physical port when voltage and
current scale in opposite directions? The example verifies the analytical
voltage, output current and lossless power balance. Tightening only the output
phase rating to 8 A rejects the unchanged state in both checks. Requested
conductor specialization falls back with `:transformer_boundary`. This is a
fixed circuit demonstration; it neither chooses a tap nor simulates a regulator
controller. The reference regression suite separately tests leakage, excitation,
open-delta coupling and nonunique bond/earth current allocations.

## F. Voltage reduction changes the load as well as the network

Hold a load coil at 207 V, or 0.9 of its 230 V nominal voltage. A nominal
2 kW load still consumes 2 kW under constant power, 1.8 kW under constant
current and 1.62 kW under constant impedance. With active ZIP fractions
`(0.2, 0.3, 0.5)` it consumes 1.864 kW. Reactive fractions may differ, so the
power factor need not remain constant for ZIP or exponential models.

**Question.** Is an observed import reduction a formulation benefit or a changed
physical demand? The tutorial evaluates all five laws at the same fixed voltage
and independently checks each power function. It isolates the demand effect;
it does not label the lower-demand law a more efficient optimizer. The regression
suite separately uses variable-voltage networks to test load/network coupling,
exact auxiliary magnitude binding and retained limits in full/reduced forms.
Missing positive coil-voltage domains cause a refusal rather than an invented
voltage floor. Deenergized behavior would require another explicit contract.

## G. An earth path need not prevent every local reduction

In a four-wire feeder, place a 2 mS phase-earth shunt at the first downstream
bus. The upstream line now carries current that returns through earth, so its
conductor sum is nonzero. A pendant tree beyond that bus can nevertheless have
only phase-neutral devices and no further earth path. Summed KCL still proves
zero-sum current on its own lines.

**Question.** Can a compiler retain the nonconforming boundary and specialize
only the eligible interior? The tutorial keeps the upstream line, boundary
voltages, shunt and every boundary KCL equation, and reduces only the two
remaining lines. It checks physical states in both model directions and loses
four real current variables. This local proof also applies to eligible trees
attached to retained transformer/switch buses or mesh cores; it does not prove
an identity through those components. Smaller local interiors extend coverage,
but modest variable savings may not improve runtime.

## H. A smaller model can have a denser Jacobian

Consider the 265-bus transformer feeder in the regional comparison. Removing
42 complex line-current coordinates changes 3,430 real variables to 3,346,
but unique backend Jacobian entries increase from 14,528 to 15,168. Expressing
physical voltages and currents in transformed coordinates changes which
variables appear together in constraints. Variable count alone therefore cannot
predict the linear algebra performed by the optimizer.

**Question.** Does the chosen coordinate basis improve the intended workload?
The [regional benchmark](ivr_nlp.md#Matched-regional-experiments) records
allocations, derivative structure, iterations and accepted timing pairs. A
separate physical-voltage prototype decreases some derivative entries but gives
no convincing general runtime advantage. Keep those observations separate from
the algebraic proof: equivalence can hold while numerical performance worsens.
The [verification record](verification.md) retains both results and failures.

## I. Remove an impedance current without losing its observation

For the two-wire service, replace the 2 kW constant-power demand with a
constant-impedance law rated 2 kW at 230 V. Its conductance is
``Y=2000/230^2`` S, so the analytical operating point is

```math
U=\frac{230}{1+0.5Y},\qquad I=YU.
```

`linear_elimination=:impedance_loads` removes the independent coil current and
its defining equality. The reported current, power and all network limits
remain expressions of the retained voltage. The tutorial compares both model
directions and the analytical current. This is a comparison of representations
of the same impedance-load problem, not of impedance and constant-power demand.

## J. Eliminate an intermediate bus but keep its neutral limit

Split the original constant-power service into two equal unshunted segments.
At an unloaded, ungrounded intermediate bus, KCL identifies the through current
and KVL gives the intermediate voltage. With 0.15 ohm of neutral resistance in
the first segment, its neutral displacement is ``0.15I``. A bound on that
displacement remains meaningful even if the bus has no independent solver
voltage variables.

The tutorial combines `linear_elimination=:passive` with conductor specialization,
checks both physical mappings, then tightens the intermediate neutral bound to
half the solved magnitude. Both models' physical checks must reject that state.
This is the central acceptance condition: reconstruction after solving alone
would not retain the original optimization problem. No impedance inversion or
approximate pi-line length aggregation is involved.

## K. Distinguish a small ground voltage from a small current error

In Example I, replace ideal source-neutral grounding with a finite admittance
``Y_g=-\mathrm{j}10^{10}`` S. Its impedance adds ``1/Y_g`` to the loop, so
``I=230/(0.5+230^2/2000+1/Y_g)`` and ``V_n=I/Y_g``. The ground voltage is
about ``8.53\times10^{-10}`` V while the current is about 8.53 A.

A voltage perturbation ``\Delta V_n=10^{-3}/Y_g`` V changes ground current by
1 mA. Dividing KCL by its original large admittance coefficient can conceal this
error from a normalized residual check. With `ground_scaling=:voltage`, the
solver uses ``w=|Y_g|Z_bV_{n,pu}`` and circuit rows are normalized in those
coordinates. The finite law, operating domain and SI observations are preserved.
The [tutorial](tutorial_exact_ivr.md) checks the analytical voltage and demonstrates
rejection of the perturbed physical state. Numerical scaling improves this
example's residual visibility; independent physical validation remains necessary.

## Interpreting benefit and evidence

There are three distinct potential benefits: a native exact reference for
approximation studies, less repeated construction work, and fewer coordinates
under a proved specialization. Feasibility tests address correctness; matched
fresh/reused timing experiments address construction savings; matched full/reduced
experiments address numerical effects. Smaller models need not solve faster,
and local solvers need not find the same stationary point on every network.
Compare objectives only after assessing the same physical problem and accepting
both states. Preserve failures and changed-input provenance in any benchmark.
