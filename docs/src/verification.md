# Verification

## Branch-flow milestone — 21 September 2026

The `BranchFlowSDP` checks cover analytical radial optima, coupled unbalanced
meshes, multiple sources, endpoint line shunts, fixed open/closed switches,
capacitors, wye and delta generators, explicit-neutral matrix KCL, all supported
load laws and advanced voltage maps. Explicit and line-derived LNCs are
exercised. Every fixed transformer connection is covered, including a general
three-winding hyperedge, leakage, excitation, neutral grounding, galvanic bonds,
declared current limits, mixed line/transformer topology and reversed component
declaration. Common cases compare objectives and voltages against `IVRSDP`, and
the independent AC validator checks recovered states where rank permits. The
suite also retains permuted/partial device-map regressions and malformed-input
applicability checks, including permuted delta dispatch, partial/permuted
multiwinding maps, scalar phase-voltage bounds, inert open-switch model size and
declaration-independent line orientation. Paper-derived regressions exercise
parallel-line cross-voltage consistency and the strengthening from
apparent-power/voltage bounds to total endpoint and shunt-corrected
series-current limits. The shared LNC regressions also cover IVR derivation from
`s_max`, while operational P/Q-box tests discriminate applied/skipped
voltage-current RLT domains. Closed-switch and multiwinding-coil regressions
check matching-voltage inferred current limits. Static IBRs remain an
intentional refusal.

The Julia 1.12.6 default suite passes **6,353/6,353** checks. OpenDSSDirect still
emits the precompilation warnings recorded below and then runs its oracle tests
without the cache.

These comparisons establish the implemented static component contracts and
several radial/meshed agreement cases; they do not establish universal
equivalence to `IVRSDP`, scalable performance, or AC feasibility of an arbitrary
recovered moment solution. The branch-flow formulation uses local
current-voltage blocks plus a conditional global voltage Gram, whereas `IVRSDP`
lifts a global eliminated current-voltage system.

## Static AC containment milestone — 11 September 2026

The new [AC containment audit](ac_validation.md) adds 1,102 passing checks to
the default suite (4,634 total on Julia 1.12.6). The first 1,097 of these new
checks also pass on Julia 1.10.11; the five additional passive/missing-observation
checks were run on Julia 1.12.6. The optional BMOPFTools/Ipopt transformer audit
passes 180 assertions on 12 compatible reference cases. Nine incompatible
reference states and four reference initialization failures remain explicit
findings, not passing coverage. The table below records earlier milestones.

| Check | Result |
|---|---|
| Default suite, Julia 1.10.11 | 3,527 passed, no skips |
| Default suite, Julia 1.12.6 | 3,532 passed, no skips |
| Optional MosekTools analytical SDP suite | 1,986 passed |
| New fixed-transformer OpenDSS comparisons (included above) | 42 passed |
| Documenter build and cross-reference checks | Passed |
| Separate BMOPFTools replay integration | 46 passed |
| Historical PowerOptLab adapter check (adapter subsequently removed) | 7 passed |
| Core package loading without a solver | Passed |
| Runtime/default-test dependency audit | No BMOPFTools, PowerOptLab, or Mosek dependency |
| PowerOptLab tracked diff whitespace check | Passed |

The default suite runs the migrated coefficient, component, applicability,
SI/per-unit, IEEE feeder, and OpenDSS oracle checks, plus new PowerIO-boundary,
callback, schema-spelling, independent-island, generic API, and SDP checks. The transformer extension adds 98 analytical and
contract checks plus 42 independent OpenDSS checks at unity and non-unity taps.
Mosek is isolated in `test/optional/Project.toml` and uses the same SDP tests.

The 46 replay checks were executed separately using the sibling PowerOptLab
Julia environment. The entire PowerOptLab test suite was not rerun; its
then-proposed forwarding API and nonlinear replay were checked by seven
integration checks. The adapter was subsequently removed from the PowerOptLab
PR; PowerOptLab has no FormulationLab dependency.

OpenDSSDirect 0.9.9 emits constructor-method/precompilation warnings on Julia
1.12.6 and falls back to loading without its cache. Its oracle tests nevertheless
run and pass. The Julia 1.10.11 suite also passes.

Clarabel 0.11.1 with OrderedCollections 2 reproduced an indexed-OrderedSet failure
in chordal PSD completion. The default optional Clarabel factory disables chordal
decomposition for this dense reference. Explicitly supplied optimizer factories
retain their own settings. No claim about a performance-optimal profile is made.

The static AC extension adds analytical grounding, switch/capacitor, inverter,
voltage-limit and load-envelope checks, plus 36 three-winding OpenDSS comparisons.
A non-star four-winding case checks coupled leakage independently.

A combined three-phase fixed inverter setpoint and delta-capacitor fixture exposed
Clarabel numerical sensitivity. Fixed P/Q boxes now compile as single equalities,
and source-fixed internal magnitude equations are not duplicated. The combined
regression checks optimal status and its analytical power result at the default
Clarabel settings, as well as with optional Mosek. Near-optimal statuses remain
unpublished as optimal results. These local encoding fixes are not a general
performance or reliability guarantee for the dense representation.

These tests establish the migrated L3F contracts and the declared static AC SDP
models and envelopes. They do not establish complete BMOPF coverage, scalable SDP performance,
rigorous numerical lower-bound certificates, or AC feasibility of a recovered
SDP voltage candidate.

The LNC extension adds 1,766 checks of normalized coefficients, rank-one validity,
fixed SOC projections, explicit interphase/winding domains, diagnostics, automatic
line-angle bounds, shunt correction and neutral/mutual coupling. Automatic cuts
are opt-in and preserve the original problem domain; explicit operating domains
are distinguished in diagnostics. No unbalanced benchmark-wide gap or speedup
claim follows from these unit and analytical checks.

The warmed comparison script on the analytical two-bus case returned approximately
10,429.8183 W with and without automatic LNCs, with maximum scaled constraint
violations below 4e-8. The pair added nine linear constraints (including its
magnitude/sector domain) and no variables: four scalar variables in both models.
This already-exact case demonstrates consistency, not an OPF gap improvement.

The fixed SOC extension removes iterative separation, adds bounded complex
three-map projections and constant-power secants, and audits propagated physical
bounds. Its regressions cover complex projection validity, unchanged model size
across a solve, deterministic triplet budgets, phase-pair ordering, phase-only
source/line limits, and three-wire generator/converter conductor powers. The
five additional budget checks were also run in the focused Julia 1.12 SOC suite.
The Mosek and replay counts above are prior checks, not reruns of this extension.

## Broader NLP / SOC panel — 11 September 2026

A size-stratified sample of 12 of the 128 reduced ENWL feeders (5–538 buses)
was compared with six DistributionTestCases inputs. Both engines received the
same BMOPFTools-normalized input, with source generators removed, taps fixed,
control laws omitted, and a source-import objective. One BLAS thread and small
warm-up cases were used; timings are single observations, not repeated estimates.

| Panel | Ipopt NLP | Default Clarabel SOC |
|---|---|---|
| 12 ENWL feeders | 12 locally solved, no error-level post-solve findings | 4 optimal, 5 almost optimal, 3 construction-budget failures |
| Two 907-bus LV snapshots | Both locally solved, about 0.07 s solve time | Neither completed within its 240 s process budget |
| Modified IEEE 13 / IEEE 123 | Both rejected missing converted line impedances | Same input failures |
| Modified IEEE 34 | Locally infeasible with nameplate caps | Slow progress |
| CIGRE test case | Locally infeasible with nameplate caps | Optimal; no feasible NLP reference for an original-input gap |

The 538-bus ENWL NLP took 0.24 s to build and 0.39 s to solve. SOC construction
already took 54 s at 140 buses. Bounded retries at 178, 241 and 538 buses stopped
in construction; their 240 s process budgets include startup and warm-up.

Fixed Kim strengthening reached optimal status on 3 of the 9 completed ENWL
comparisons. It reduced the 45-bus gap from 20.7 W to 9.0 W but increased total
time from 47 s to 71 s. Modestly relaxed stopping tolerances recovered optimal
status on 3 of 5 almost-optimal default-SOC cases, but did not address build cost.

The transformer `s_rating` interpretation materially affects the imported
comparisons. In **separate derived-input diagnostics**, removing those fields
made both CIGRE and IEEE 34 NLPs locally solved with no error-level findings.
CIGRE then had a numerical NLP-minus-SOC objective gap of 1006.7 W on a 1.837 MW
import (0.055%); IEEE 34 SOC still returned slow progress. Restoring IEEE 13's
explicitly stated missing line impedance allowed model construction but did not
produce a successful solve with its original nameplate caps. The IEEE 123
converter also warned that a delta–delta transformer was dropped: these imported
outcomes cannot establish feasibility of the unchanged DSS circuits.

The full report and numerical evidence are in
`examples/results/nlp_soc_combined_2026-09-11.md` and its JSON companion.
`examples/README_nlp_soc_experiments.md` documents the runners, bounds on execution,
controlled changes and interpretation caveats. These numerical objectives are
not certified global bounds; Ipopt results are local candidates, and solver
status alone does not establish physical equivalence across input conventions.
