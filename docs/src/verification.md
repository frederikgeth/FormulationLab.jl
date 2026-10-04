# Verification

## Exact IVR fixed regulators — 5 October 2026

The default Julia 1.12.6 suite passes **23,074/23,074** assertions (test summary
2m36.9s). The regulator package adds 3,471 analytical, perturbation, bound,
refusal and solve checks, plus 60 assertions against eight OpenDSS fixed
circuits; two former unsupported-family checks are retired. The OpenDSSDirect
precompilation warning described below persists, with successful fallback
loading and reference-test completion.

Both type-A/type-B fixed gains, all three open-delta connections, optional
neutral, single-phase implicit earth and nonneutral common conductors are
covered. Tests vary leakage, excitation location, power base and power-flow
direction. Grounding cases distinguish unique voltages from possibly nonunique
bond/earth current allocations. Explicit bond-current observations bind the
supplied exact-IVR point; older formulation observations retain only physically
identifiable audit relations. Side-current negative tests tighten individual
entries while holding the physical state fixed.

The OpenDSS comparison uses explicit shared nodes and a documented conversion
from native leakage ohms to fixed two-winding parameters. It compares output
phasors and source complex power, not regulator-controller behavior or a
universal interpretation of connection labels. A read-only scan of transformer
entries in the earlier 2,815-network local dataset inventory found only
single-phase and delta–wye types, so it supplies no regulator feeder evidence.
The executable tutorial now includes an analytical fixed-gain example and an
output-current bound violation. No regulator performance claim is made.

All seven fixed transformer families are now accepted by exact IVR. The
remaining static load-law package is constant-current/ZIP/exponential demand;
controls, optimized taps, external DC and time-series semantics remain outside
scope. Every transformer still causes conductor-specialization fallback. This
checkpoint supersedes the earlier scope statements below; their dated results
remain historical evidence.

## Exact IVR static components and reusable models — 4 October 2026

At implementation commit `ac89168`, the default Julia 1.12.6 suite passes
**19,545/19,545** assertions (test summary 2m26.6s). This includes 1,657 new static
IBR checks. Documentation builds pass. OpenDSSDirect still reports its existing
method-overwrite precompilation error, falls back to loading without the cache,
and its oracle tests pass. The dated counts below describe earlier milestones.

The exact-IVR validation separates four kinds of evidence:

| Claim assessed | Reproducible evidence | Limit of inference |
|:--|:--|:--|
| Local coordinate identities and conditional network equivalence | `test/compiler_algebra_tests.jl`, `test/compiler_network_tests.jl` | Narrow declared certificate, not mixed-section/transformer composition |
| Physical equations and port conventions | independently manufactured SI states; fixed-transformer and capacitor OpenDSS tests | Stated native circuits, not universal schema or hardware equivalence |
| Operating bounds retained | `test/ivr_bound_coverage_tests.jl`, switch/capacitor/IBR suites hold states fixed and violate one limit | Implemented inventory; future fields require new tests |
| Reusable updates preserve the problem | fresh/reused solves, objectives, variable identity and bidirectional supplied-point checks | No implicit warm-start/factorization claim or universal speedup |

The [equation chapter](ivr_theory.md) states the equivalence assumptions and
source map. The [tutorial](tutorial_exact_ivr.md) runs its analytical, full/reduced,
fresh/reused, generator-price, inverter-loss and refusal checks during every
Documenter build, using `examples/tutorial_exact_ivr.jl`. Tutorial assertions
are a documentation gate, separate from the dated default-suite count above.

An exploratory local panel used 18 ENWL inverter snapshots (30–538 buses,
28–302 single-phase inverters). Explicitly removing their unsupported control
records on owned copies produced changed static-capability scenarios. Of 36
initial full/reduced solves, 32 passed strict acceptance; four full 538-bus runs
returned ALMOST_LOCALLY_SOLVED and remained rejected. Disabling acceptable
termination and raising the iteration limit from 300 to 600, with the same
1e-10 tolerances, produced four strictly accepted retries. Physical/model checks
passed and retry objectives agreed with the reduced counterparts. These results
are local experimental evidence, not a repository CI gate, raw controlled-input
support, a global certificate or a performance conclusion. The user's planning
documents and raw panel evidence remain outside Git; the portable synthetic
tutorial supplies the repository's reproducible demonstration.

No omitted operating bound was found in the implemented native inventory;
negative tests and independent decoding provide evidence rather than a proof
of completeness for all possible schema fields. Fixed regulators/autotransformers,
constant-current/ZIP/exponential loads, control profiles, optimized taps, external
DC and time-series semantics remain outside exact-IVR scope.

## ENWL generation-cost comparison — 30 September 2026

The complete 128-file ENWL reduced-topology panel (5–538 buses) compares
generation-cost-minimising LinIVR, Kron-reduced LinDist3Flow and BMOPFTools'
four-wire nonlinear IVR. All three solve 127 cases. The main panel explicitly
consolidates each priced `grid` generator with its otherwise unpriced source;
five as-supplied audits retain the original artificial export-credit behavior.
Original DER prices and bounds are preserved. Prices receive a common positive
numerical scaling, and costs are independently reconstructed in original units.

On 118 paired converged four-wire replays, median feeder-maximum magnitude
errors are 0.0615 V versus 0.8658 V for phase-to-neutral voltage and 0.0237 V
versus 2.002 V for neutral-to-ground voltage (LinIVR versus LinDist3Flow).
The latter has no neutral state and is assessed using its imposed zero-neutral
assumption. Its Kron projection also discards neutral current ratings; both
model changes remain explicit findings.

Both approximations understate the nonlinear reference cost by a median 4.20%.
Among 115 paired replays passing the assessed operational checks, the median
replayed cost excess is 0.195% for LinIVR versus 0.845% for LinDist3Flow.
Three converged LinDist3Flow replays fail assessed limits; no converged LinIVR
replay does. Solver failures and near-convergence statuses are retained and
excluded from paired accuracy statistics. Nonlinear optimality remains local,
and the solution checker retains its unassessed dimensions.

The panel required LinDist3Flow to accept omitted/one-sided reactive generator
bounds, without adding artificial Q limits. Eleven new regressions and the full
**6,842/6,842** suite pass. The reproducible runners are
`examples/benchmark_enwl_cost.jl` and `examples/report_enwl_cost.py`.
The report, figures, aggregate JSON and compressed complete observations are
under `examples/results/enwl_cost_comparison_2026-09-30.*`.

## Explicit-neutral LinIVR experiment — 30 September 2026

After the coverage expansion, the Julia 1.12.6 default suite passes
**6,831/6,831** checks, including 439 dedicated LinIVR checks. The documentation
site builds successfully. OpenDSSDirect emits its existing precompilation
warnings and runs its tests without the cache.

The initial Julia 1.12.6 default suite passed **6,518/6,518** checks after extracting
the shared solver-independent IVR circuit assembler. The first 126 LinIVR checks
cover analytical neutral displacement and finite grounding, per-unit and
rotation invariance, dispatch/loss objectives, zero-reference neutral limits,
constant-impedance references, singular/unsupported inputs, coupled four-wire
lines, delta loads, endpoint shunts, a parallel circuit and a fixed transformer.

The coverage expansion adds 313 checks for all seven fixed transformer families,
tap changes and reversed flow, exact impedance aliases, delta coil dispatch,
current-only reference freedom, transformer loss identities and all three static
inverter topologies. It tests an affine internal-power budget that is exceeded
by the actual filter power, so that limitation remains visible. The independent
checker accepts `physical_residuals(input, result::LinIVRResult)` and selects the
appropriate delta coil convention automatically.

The optional BMOPFTools comparison covers 18 synthetic scenarios and three
existing ENWL cases without applying neutral Kron reduction. Nonlinear replay
exposes a voltage-limit violation in a stressed case accepted by LinIVR. See
[the formulation and experiment](linivr.md); these checks establish neither
universal approximation accuracy nor AC-feasible dispatch guarantees.

The expanded panel contains 73 transformer cases with independently constructed
and physically validated AC references, plus seven BMOPFTools PCC comparisons:
three inverter topologies at a fixed source and on an unbalanced feeder, and an
unbalanced delta generator. The loaded references are validation data only.
Delta P/Q and current ratings follow BMOPFTools' coil convention; existing SDP
conductor semantics are unchanged. The inspected nonlinear comparator does not
stamp the inverter filter/internal-power extensions, which are tested separately.
Raw observations and limitations are retained in
`examples/results/linivr_coverage_2026-09-30.json` and its Markdown companion.
All 73 transformer approximations solve, with maximum conductor phasor error
0.359 V on this panel. All seven device replays report `LOCALLY_SOLVED` and pass
the comparator's assessed solution checks; replayed device dispatch differs from
the requested dispatch by less than ``2\times10^{-8}`` VA. These results do not
extend to untested limits or certify AC feasibility of the approximate states.

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
