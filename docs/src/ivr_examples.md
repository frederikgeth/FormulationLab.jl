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

## Interpreting benefit and evidence

There are three distinct potential benefits: a native exact reference for
approximation studies, less repeated construction work, and fewer coordinates
under a proved specialization. Feasibility tests address correctness; matched
fresh/reused timing experiments address construction savings; matched full/reduced
experiments address numerical effects. Smaller models need not solve faster,
and local solvers need not find the same stationary point on every network.
Compare objectives only after assessing the same physical problem and accepting
both states. Preserve failures and changed-input provenance in any benchmark.
