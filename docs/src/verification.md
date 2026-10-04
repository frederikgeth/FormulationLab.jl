# Verification

## Sparse affine expression preparation — 5 October 2026

The default Julia 1.12.6 suite passes **28,065/28,065** assertions (2m03.6s),
including **132 new expression checks**. Exact IVR and LinIVR now accumulate
sparse linear rows directly into a fresh complex JuMP affine expression. They
previously allocated a scaled expression for each row term before summation.
The numerical reference/reconstruction evaluator is unchanged. This modifies
preparation, not the circuit equations, conductor coordinates, objective,
operating bounds, input domain or update API.

For affine coordinates ``z_k(x)=a_k^T x+b_k`` and a circuit row ``c``, the emitted
polynomial remains

```math
\sum_k c_k z_k(x)
=\left(\sum_k c_k a_k\right)^T x+\sum_k c_k b_k.
```

This is an unconjugated linear combination. Tests compare its coefficients,
constant and numerical values against independently assembled dense coefficients.
They cover complex coefficients, cancellation, constant/empty rows, vector views,
repeated coordinate objects and mutations of the returned expression. Each
result is owned independently; neither input rows nor shared coordinate
expressions can be mutated by accumulation. The complete suite exercises this
helper through LinIVR, full and specialized exact IVR, device laws, operating
bounds, supplied-point reconstruction and update paths.

A controlled same-process ablation compares the old and new emitters on three
external feeders in full and regional modes. Each case/mode excludes one
warm-up per variant and measures six pairs in balanced alternating order with
single-thread BLAS. All inputs retain their electrical data; the explicitly
chosen objective is feasibility. Independent physical and both cross-model
checks pass for **72 measured solves**. All variable, constraint and backend
Jacobian/Hessian counts match. A further **12 production-method confirmation
solves** pass physical/model checks and retain those counts without the
experimental switch. No timings run concurrently with tests or documentation.

| Input / mode | Build allocation MB: old / new | Median paired build-time ratio | Observed build-ratio range |
|:--|--:|--:|:--|
| DSuite 265 buses, full | 65.60 / 57.53 | 0.912 | 0.129–2.624 |
| DSuite 265 buses, regional | 68.46 / 60.02 | 0.947 | 0.927–1.981 |
| DSuite 2,854 buses, full | 743.32 / 655.74 | 0.826 | 0.584–1.588 |
| DSuite 2,854 buses, regional | 768.67 / 678.48 | 0.808 | 0.626–1.381 |
| Reduced ENWL 538 buses, full | 224.61 / 184.17 | 0.679 | 0.393–2.135 |
| Reduced ENWL 538 buses, regional | 239.33 / 193.17 | 0.394 | 0.279–1.672 |

Allocation values are separate medians in decimal MB; ratios are new/old within
pairs. Build allocation falls approximately **12–19%** in the controlled
ablation; the production-method checks confirm the saving. Julia allocated
bytes exclude native solver memory and peak resident memory. GC is included in
timings and contributes to their broad ranges. Solve-time ratios are near one;
the full 538-bus case's median paired total time increases about 5% despite the
lower median build-time ratio. Consequently these observations support an
allocation improvement, not a general runtime or solver-speed guarantee.
Six pairs and three selected inputs do not provide a statistical significance
or population claim. This repeats the preparation workload under a separate
feasibility objective, not the earlier source-import optimization study.

Raw scripts, hashes, versions, warm-ups, trials and confirmation results remain
in the local evidence directory outside Git. An earlier exploratory run partly
overlapped focused-test compilation and is retained separately; its timings
are not used above. The known OpenDSSDirect method-overwrite precompilation
error still falls back to successful loading and passing reference comparisons.
It is not changed by this optimization. Earlier regional timing results below
describe the older emitter.

## Regional performance and coordinate ablation — 5 October 2026

The expanded experiment uses `examples/benchmark_ivr_regions.jl`: one excluded
warm-up pair per case, then six balanced alternating-order pairs with strict
Ipopt tolerances, single-thread BLAS, fresh builds and unloaded starts. Physical,
own-model, cross-model and objective checks lie outside the timers. The runner
retains failures, raw timing/allocation observations and within-pair ratios.
Inputs and evidence remain outside Git; production equations and coordinates
are unchanged by this experiment.

Of eight source-import cases, four pass the warm-up and all six measured pairs.
The other four are retained as rejected warm-ups. A separately labelled
feasibility experiment passes three of those four cases. Thus **84 measured
solves** pass all gates across seven case/objective combinations. These include
related/reduced variants and are not seven independent feeder designs.

| Input and explicit objective | Buses | Median solve ratio | Median total ratio | Observed total-ratio range |
|:--|--:|--:|--:|:--|
| DSuite SPD Suburban, import | 265 | 1.078 | 0.944 | 0.336–1.624 |
| DSuite SPM Suburban, import | 2,854 | 1.007 | 1.054 | 0.956–1.137 |
| ENWL network 23 feeder 3, import | 59 | 0.920 | 0.972 | 0.166–0.990 |
| Reduced DSuite SPD Suburban, import; no selected region | 178 | 1.001 | 1.025 | 0.231–1.540 |
| Reduced ENWL network 8 feeder 2, feasibility | 538 | 0.377 | 0.497 | 0.403–0.610 |
| ENWL three-wire Kron variant, feasibility | 844 | 0.955 | 1.356 | 0.793–1.506 |
| ENWL three-wire phase-neutral variant, feasibility | 844 | 0.954 | 1.025 | 0.823–1.285 |

Ratios are regional/full, calculated per pair before taking the median. Total
includes build and solve/extraction; it excludes validation. GC remains enabled
and contributes to the wide observed ranges. Six pairs are descriptive evidence,
not a significance test. In particular, the 2,854-bus result reverses the earlier
small total-time improvement. No general speed benefit is established. The
538-bus feasibility result is promising for that workload but is not an accepted
source-import optimization result. Regional build allocation increases by about
2–9% across these cases, including detector overhead in the fallback control.

**Fewer variables can produce more derivative entries.** On 265 buses, variables
fall from 3,430 to 3,346 while unique backend Jacobian entries rise from 14,528
to 15,168. On 2,854 buses the corresponding counts are 36,716 to 36,242 and
159,826 to 163,070. On the 59-bus uniform feeder both variables and Jacobian
entries fall. These are structures before solver preprocessing, not factorization
fill or memory. The separate large-feeder stage pass takes approximately 17 ms
for certification and 3 ms for maps; assembly and GC are more prominent in the
sampling profile. These separate measurements are diagnostic, not additive
components of the timed public build.

A process-local prototype retained physical voltages while reducing only line
currents. It passes 24 measured solves on the two DSuite cases, reduces Jacobian
entries relative to differential voltages, but leaves them above full-IVR counts.
It does not recover the two rejected cases included in that ablation. Timing
variation and inconsistent gains do not justify changing production coordinates;
the prototype remains only in local experimental evidence.

**Failure interpretation.** The two mixed three-wire inputs have unrestricted
colocated generators and sources. Separate feasibility witnesses allow increasing
each generator phase by ``t`` W and decreasing source injection by the same
amount. Phase injections cancel; the existing unbounded ideal-ground return
can absorb any neutral imbalance. All downstream states remain unchanged and the import objective falls
by ``3t`` W. Eight fixed-state witnesses (four per input, up to ``t=10^7`` W)
pass independent physics and both full/regional models. The absence of limiting
source/generator bounds establishes an unrestricted decreasing direction; Ipopt's
`NORM_LIMIT` status alone would not establish this. Source files are unchanged.

The original 844-bus bounded-generator input returns `ALMOST_LOCALLY_SOLVED`
in both modes even under the separate feasibility objective. Diagnostic raw
iterates pass the ordinary physical/model audit tolerances, but residuals around
``3.2\times10^{-9}``–``3.8\times10^{-9}`` exceed the requested ``10^{-10}``
solver threshold. The largest physical residuals are source-bus KCL. These
iterates remain rejected; audit tolerances and strict acceptance are not
interchangeable. The reduced 538-bus source-import comparison similarly lacks
strict regional acceptance, despite its successful separate feasibility study.

The runner's **17 smoke assertions** cover accepted-only arithmetic, retained
failures, invalid arguments, balanced order, profiles and JSON output. All
**14 executable tutorial blocks** and documentation checks pass. The existing
**27,933-assertion** production gate belongs to the preceding implementation
checkpoint; it is not a new test count for this benchmark-only change.

## Exact IVR pendant-region specialization — 5 October 2026

The default Julia 1.12.6 suite passes **27,933/27,933** assertions (test summary
2m35.5s), including 2,398 new regional checks. The old whole-section option
retains its scope and regression behavior. `:conductor_regions` is a separate
opt-in certificate for disjoint pendant interiors behind retained boundary
buses. It does not reduce through transformers, switches, earth paths or mixed
conductor junctions. See the [proof](ivr_theory.md#Pendant-region-certificate)
and [public contract](ivr_nlp.md#Pendant-regions-inside-a-larger-network).

Independent SI witnesses deliberately give the upstream retained line a nonzero
conductor-current sum. Full and regional models accept the same states in both
directions. Tests cover two/three/four-wire regions, mixed boundary subsets,
cycles and parallel edges, multiple sources, every fixed transformer family,
open/closed switches, voltage-dependent demand, capacitors, generators and
static IBRs. Fixed-state probes cover boundary/interior voltage and sequence
limits, neutral magnitudes, both ends of selected and retained line ratings,
and delta-generator limits. Current perturbations cannot be repaired by
projection. Demand reuse retains model variables and the certificate.

This exercise found a shared initialization defect: a finite phase-earth shunt
could seed zero voltage before propagation reached it from a fixed source.
Fixed-source/ideal-ground references now propagate first; finite grounds seed
only conductor components still unreached. The changed starts affect neither
physical admittance nor KCL. Regression cases that failed strict solver
acceptance from the old starts now pass. One ideal winding comparison had a
separate full-model restoration failure; the composition fixture now explicitly
uses finite leakage. Ideal winding behavior remains covered elsewhere, and no
unique bond/ground current allocation is assumed.

A bounded repeat of the earlier 83-entry local panel assessed 41 networks,
refused 31 unsupported/invalid inputs and left 11 above the 3,000-bus cap
unassessed. Regional certificates select lines in 15 entries, including 10
where the whole-section certificate declined. Several entries are related
variants; this is not a count of independent feeder designs.

Three original DSuite inputs also pass strict full/regional solves, independent
physics, model checks, both cross-model directions and objective agreement:

| Buses | Selected lines | Regions | Real JuMP variables: full → regional |
|--:|--:|--:|--:|
| 66 | 4 | 4 | 882 → 874 |
| 265 | 42 | 29 | 3,430 → 3,346 |
| 2,854 | 237 | 152 | 36,716 → 36,242 |

These experiments preserve electrical inputs and explicitly use source-import
minimization. The 66-bus case is effectively unloaded; the two larger cases
have nonzero demand. Already-present input reductions are inherited. The
single-run timings include compilation/order effects and do not establish a
speed benefit.

A separate run excludes one warm-up per mode and feeder, then measures five
alternating-order full/regional pairs. All 20 measured solves pass physical,
model, cross-model and objective-agreement gates. Validation runs outside the
timed intervals. Median times in seconds are:

| Buses | Build: full / regional | Solve: full / regional | Total: full / regional |
|--:|--:|--:|--:|
| 265 | 0.03893 / 0.02507 | 0.03360 / 0.03707 | 0.07253 / 0.06235 |
| 2,854 | 0.40725 / 0.38413 | 0.65755 / 0.68316 | 1.09439 / 1.07209 |

Total medians need not equal sums of component medians. Both solve medians
increase; total medians decrease by approximately 14% and 2%, respectively.
Five pairs on two feeders provide no general speed guarantee or statistical
significance claim. The demonstrated result is broader applicability with
fewer variables and preserved physical states. Raw cases, digests, diagnostics
and timings remain in the user's local evidence directory outside Git. The
known OpenDSSDirect method-overwrite precompilation error still falls back to
successful loading in the complete regression suite.

## Exact IVR voltage-dependent demand — 5 October 2026

The voltage-law extension adds **2,461 assertions**: 2,335 manufactured-state,
solve, bound, domain, input and update checks, and 126 assertions against
18 OpenDSS circuits. The default Julia 1.12.6 suite passes **25,535/25,535**
assertions. The known OpenDSSDirect precompilation issue still falls back to
successful loading; reference comparisons pass. The new executable tutorial
compares all five laws at an identical fixed voltage, separate from the suite
count. Counts here supersede earlier dated milestones below.

Independent SI witnesses cover single-phase, three-wire delta and four-wire
wye loads; unbalanced P/Q; positive, zero and reverse demand; two power bases;
full/reduced representations; fractional, zero and negative exponents; and
terminal reordering. Holding each state fixed, tests violate its load-current
law, matched voltage bound, line current bound or auxiliary squared-voltage
binding. Mixed invalid updates leave valid constant-power entries unchanged.
Pure-Z witnesses check zero current at zero coil voltage while preserving KCL
and power in the deliberately invalid point. This found an independent-auditor
gap: power alone did not identify zero-voltage impedance current. Equal engineering magnitude bounds also have
60 checks that ensure constant power factors add no redundant fixed auxiliary. Scalar ZIP
broadcasting in that auditor was also corrected.

OpenDSS comparisons cover all three connections and laws at 0.85 and 1.08 pu,
with a series line, matching source phasors and coil nominal voltages. They
compare load power, downstream phasors and line input current. DSS ZIP dropout
is disabled and all points stay inside its declared model voltage thresholds;
no claim is made for the different low/high-voltage substitutions documented
in the [OpenDSS load reference](https://dss-extensions.org/dss-format/Load.html).
The local 2,815-network inventory contains 334,486 constant-power load entries
and no explicit current/ZIP/exponential entries. It therefore supplies no
new-law feeder validation or performance conclusion.

All five native static load laws and seven fixed transformer families are now
implemented within documented restrictions. General nonlinear load powers
require a positive bound on the **actual coil voltage** or a fixed nonzero
source coil; nominal voltage supplies no such certificate. Pure impedance laws
retain their linear current equations at zero. This is an explicit applicability
domain, not full deenergized-load behavior or full schema coverage. Controls,
optimized taps, external DC and time-series semantics remain outside scope.
Region-wise conductor specialization and broader reusable parameter APIs also
remain future work.

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
