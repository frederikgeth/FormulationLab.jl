# Formulation decisions and experimental lessons

Decision record, 11 September 2026. Evidence and implementation baseline:
`176dba9`. This page records what to retain from the experiments, not a claim
that the current implementation is universally fastest or AC exact. The target
is a fixed, portable relaxation for Clarabel, using SOC and load power cones,
with explicit approximation diagnostics. There is no iterative outer approximation.

## The formulations to retain

| Family or configuration | Decision | Reason and limitation |
|:--|:--|:--|
| `LinDist3Flow` | Retain the fixed-reference approximation baseline. | Useful when its lossless, radial assumptions are acceptable. It is not an AC lower bound; the latest studies do not establish its speed or accuracy on the entire panel. |
| `IVRSDP` | Retain dense reference and chordal representations. | Provides a stronger moment relaxation and a correctness comparator, with optional Mosek testing. It is outside the SOC-only deployment target. |
| `BranchFlowSDP` | Experimental branch-flow formulation added after this decision baseline. | Exposes classic line moments plus matrix KCL and connection-local device moments; a conditional voltage Gram supports meshes and multiple sources. Static IBRs remain outside its scope. |
| `IVRSOC`, physical projections plus `strengthening=:linear`, `clique_size=32` | Retain as the general Clarabel starting point. | Best-supported balance of objective agreement and accepted solver outcomes so far; still has substantial failures and slow cases. |
| `IVRSOC`, `strengthening=:kim`, eight triplets | Retain as an opt-in strengthening of the same family. | Twelve-coordinate setting is useful on ENWL 96; 32 is a useful LV comparator. Neither warrants replacing the general default. |
| Automatic voltage LNCs | Keep opt-in, default `lnc=:off`. | Valid with suitable domains, but negligible benefit or worse numerical behavior in the small historical panel. |
| Physical projections without linear strengthening | Keep as an ablation. | Removing the secants did not give a compelling advantage. |

The retained baseline contained three mathematical families. `BranchFlowSDP`
is now a fourth, experimental family because its variables and electrical
decomposition differ materially; it is not a numerical profile. Strengthening
and numerical options within a family do not create new formulations. In
particular, “linear32” is a study label for an SOC relaxation with linear cuts;
it does **not** mean a linear programming formulation.

Keep six decisions separate: input semantics, network reduction, electrical
formulation, moment coordinates/cuts, solver settings, and state recovery.
Reduction and reconstruction are shared services for all formulations, not
SOC-specific mathematics. JuMP remains the modeling backend; PowerIO remains the
only power-system runtime dependency. BMOPFTools/Ipopt and Mosek are optional
reference/testing tools. An ExaModels backend remains deferred until an exact
nonconvex formulation is implemented here.

## Mathematical identity and scientific lineage

The electrical core uses a homogeneous complex state of voltages and component
currents, linear laws ``Az=0``, and an elimination ``z=Ny``. It replaces
``H=yy^H`` by a Hermitian positive semidefinite moment matrix. Physical products
are ``(aN)H(bN)^H``. Thus `IVRSDP` is a current–voltage moment relaxation; it is
not simply the textbook bus-injection or S–W branch-flow SDP under a new name.
Nonquadratic load laws require additional envelopes.

`IVRSOC` keeps those electrical maps and replaces PSD conditions with pairwise
complex SOC minors and selected physical projections. Optional three-map
projections strengthen the outer relaxation. With matching coordinates, bounds,
and cuts, these conditions are necessary for PSD, not sufficient for it.
A full PSD cone is invariant under nonsingular congruence; a finite collection
of pairwise SOC constraints generally is not. Coordinate and decomposition
choices can therefore change SOC strength, not just solver performance.

The sources below identify the scientific ideas used. Software adaptation and
empirical profile selection are our engineering work, not claims of invention
or of inheriting a paper's exactness theorem.

| Idea | Origin and relationship to this implementation |
|:--|:--|
| Fixed voltage-ratio multiphase linearization | Michael D. Sankur, Roel Dobbe, Emma Stewart, Duncan S. Callaway and Daniel B. Arnold, [*A Linearized Power Flow Model for Optimization in Unbalanced Distribution Systems* (2016)](https://arxiv.org/abs/1606.04492). This is the LinDist3Flow lineage; the code and regression fixtures were migrated from PowerOptLab. |
| OPF semidefinite lifting | Javad Lavaei and Steven H. Low, [*Zero Duality Gap in Optimal Power Flow Problem* (2012)](https://smart.caltech.edu/papers/zeroduality.pdf), is a foundational OPF SDP reference. Lingwen Gan and Steven H. Low, [*Convex Relaxations and Linear Approximation for Optimal Power Flow in Multiphase Radial Networks* (2014)](https://arxiv.org/abs/1406.3054), develops multiphase SDP formulations. Our explicit-current construction differs; their exactness results are not a blanket guarantee here. |
| Explicit-neutral current–voltage modeling | Sander Claeys, Frederik Geth and Geert Deconinck, [*Optimal Power Flow in Four-Wire Distribution Networks: Formulation and Benchmarking* (2022)](https://arxiv.org/abs/2204.08126). This provides the relevant four-wire IVR modeling background. |
| Wye/delta voltage-dependent load power cones | Sander Claeys, Geert Deconinck and Frederik Geth, [*Voltage-Dependent Load Models in Unbalanced Optimal Power Flow Using Power Cones* (2021)](https://doi.org/10.1109/TSG.2021.3052576). We retain connection-specific physical voltage maps and convex envelopes, rather than silently replacing these loads by constant power. Constant-power secants also use the elementary secant upper bound of a convex function on a finite interval. |
| Fixed regulator connection matrices | Mohammadhafez Bazrafshan, Nikolaos Gatsis and Hao Zhu, [*Optimal Power Flow with Step-Voltage Regulators in Multi-Phase Distribution Networks* (2019)](https://arxiv.org/abs/1901.04566), supplies the regulator-bank matrix lineage documented in LinDist3Flow. We fix taps and do not implement that paper's tap-selection optimization. |
| Sparse PSD completion | Robert Grone, Charles R. Johnson, Eduardo Marques de Sá and Henry Wolkowicz, [*Positive Definite Completions of Partial Hermitian Matrices* (1984)](https://doi.org/10.1016/0024-3795(84)90207-6), supplies the chordal completion foundation. Required overlaps must be consistent; merely splitting arbitrary blocks is not an equivalence theorem. |
| Finite SOC relaxations of PSD | Sunyoung Kim, Masakazu Kojima and Makoto Yamashita, [*Second Order Cone Programming Relaxation of a Positive Semidefinite Constraint* (2003)](https://doi.org/10.1080/1055678031000148696). Frederik Geth and James Foster, [*Improving Optimal Power Flow Relaxations Using 3-Cycle Second-Order Cone Constraints* (2021)](https://arxiv.org/abs/2104.06695), extends this strategy to complex three-map constraints. Our fixed data-selected triplets and direction budgets adapt this idea to unbalanced physical maps. |
| Lifted nonlinear cuts | Carleton Coffrin, Hassan Hijazi and Pascal Van Hentenryck, [*Strengthening the SDP Relaxation of AC Power Flows with Convex Envelopes, Bound Tightening, and Lifted Nonlinear Cuts* (2015 preprint)](https://arxiv.org/abs/1512.04644). PowerModels supplied a software reference. Here the scalar product cuts apply to general physical voltage maps with justified magnitude and angle domains. |
| Limits of finite SOC replacement | Hamza Fawzi, [*On Representing the Positive Semidefinite Cone Using the Second-Order Cone* (2016 preprint)](https://arxiv.org/abs/1610.04901), rules out a finite SOC lift of the general real 3×3 PSD cone. Finite directional strengthening should not be advertised as full SDP equivalence. This is not a theorem about every possible exotic-cone representation. |
| Conic solver | Paul J. Goulart and Yuwen Chen, [*Clarabel: An Interior-Point Solver for Conic Programs with Quadratic Objectives* (2024)](https://arxiv.org/abs/2405.12762). Formulation-specific scaling, regularization and tolerances are separate empirical choices. |

Frederik Geth's local **DeltaLoadsSDP** experiments and working manuscript,
*Matrix Current-Balance Constraints for Multiconductor Optimal Power Flow*,
informed the winding-current and lift-before-eliminate treatment. This is
working-repository provenance, not an additional published exactness result.
Retaining delta coil currents avoids inventing a voltage gauge or deleting a
physical current degree of freedom. Our transformer implementation uses winding
incidence and current–voltage equations before forming moments; see
[the detailed transformer derivation](sdp_transformers.md).

The reducer was independently vendored from BMOPFTools revision
`ddd588f7143ae218142e4176e8086199179722c3`, with BSD attribution retained in
`THIRD_PARTY_BMOPFTOOLS_LICENSE.md`. Adding lengths of compatible π sections is
a compatibility approximation, not exact Kron elimination. The correlation-tree
voltage recovery is a local engineering heuristic using a maximum spanning
forest; it carries no published AC-feasibility guarantee. See
[migration provenance](migration.md) and [reduction details](reduction.md).

## What the numerical studies actually establish

The [reduction study and raw-data links](https://github.com/frederikgeth/FormulationLab.jl/blob/176dba9/examples/results/reduction_study_2026-09-11.md)
are the latest evidence. They use Julia 1.12.6, Clarabel 0.11.1, Ipopt 1.16.0,
one BLAS thread, fixed taps, source-bus generators removed, other generators
retained, and net source active-power import as objective. The per-phase power
base is `max(total apparent nominal load, installed active generation, 3000 VA)/3`.
The reference is BMOPFTools with Ipopt on both original and reduced networks.

Reported “solve” times are wall times around solving **and result extraction**,
not isolated Clarabel native solve times. Build time is separate. Measurements
are single warmed runs, with possible component compilation and concurrent
verification work. Subsecond differences are not evidence of a reliable speedup.
The objective difference is NLP minus SOC in watts; it is not a certified gap.
Ipopt gives a local candidate, and approximate reduction can change the problem.
`ALMOST_OPTIMAL` and failed runs are excluded from accepted objective comparisons.

Selected fixed-profile results (initial sweep unless noted):

| Case | Profile | Solve stage s | NLP − SOC W | Difference / absolute NLP import |
|:--|:--|--:|--:|--:|
| ENWL 9_Feeder_4, 24 buses | linear32 | 16.125 | 0.104 | 0.00258% |
| Same | kim12_8 | 24.031 | 0.066 | 0.00165% |
| ENWL 18_Feeder_6, 45 buses | linear32 | 44.455 | 20.697 | 0.70348% |
| Same | kim12_8 | 59.117 | 10.188 | 0.34630% |
| ENWL 18_Feeder_9, 96 buses | linear32 | 1.780 | 33.607 | 2.56632% |
| Same | kim12_8 | 3.221 | 14.642 | 1.11813% |
| LV t500, reduced 907 → 118 buses | linear32 | 0.876 | 86.219 | 0.38459% |
| Same, strengthening sweep | kim32_8 | 0.715 | 85.832 | 0.38286% |
| LV t1000, strengthening sweep | physical32 | 0.670 | 355.879 | 0.72822% |
| Same | kim32_8 | 0.647 | 353.690 | 0.72374% |

The t1000 voltage-tree run of linear32 gave the same 355.879 W difference,
with approximately 0.68 s in the solve stage. The 96-bus percentage is amplified
by near-cancellation of demand and generation: its NLP net import is about
−1309.54 W. Preserve absolute watt differences alongside percentages.

The strongest practical improvement was reduction on the two LV snapshots:
907 buses became 118, and default SOC build plus solve completed in about
14–15 seconds, whereas earlier unreduced runs exhausted a 240-second process
budget. This is a budget comparison, not a measured speedup factor. Original
and reduced NLP objectives agreed to reported precision, and no approximate
reduction events were applied to those LV inputs. They do not measure the error
of π aggregation. All twelve sampled ENWL networks were already irreducible.

Do not generalize the early four-feeder success panel. The
[broader comparison](https://github.com/frederikgeth/FormulationLab.jl/blob/176dba9/examples/results/nlp_soc_combined_2026-09-11.md)
had four accepted default SOC results, five `ALMOST_OPTIMAL` outcomes and three
budget failures across twelve ENWL cases, while NLP solved all twelve. Relaxed
study tolerances subsequently rescued some cases. Derived IEEE34 still returned
`NUMERICAL_ERROR` after reduction; derived CIGRE solved. Their transformer
`s_rating` fields were deliberately removed to align differing engine semantics;
these are not successful solves of the untouched inputs. IEEE13/123 were topology
scans only in the latest study. The reduced LV NLP solve was about 0.01 seconds:
SOC has not established a local speed advantage over Ipopt.

Smaller requested cliques were less reliable on the larger cases. Some requests
produce the same dense layout, and the current compiler can fall back to dense
when a selected block spans the entire independent state. Bus count and a
`clique_size` keyword are insufficient descriptions of solver workload. The
24/45-bus solve stages are much slower than the reduced LV solve stages.

Kim strengthening approximately halves the 45/96-bus objective difference, with
more solve time. Its LV objective improvement is small; the apparent subsecond
timing benefit is unproven. Automatic LNCs gave little benefit and sometimes
worse termination in the earlier panel. Keep these options, without enabling
all cuts indiscriminately. SDP also beat SOC on some small historical cases;
retain it as a reference rather than assuming SOC always dominates it.

## Bounds, transformers, and trust

Bound corrections and propagation are shared by SOC and SDP. They distinguish
phase-to-neutral from phase-to-phase domains, respect inherited component data,
and derive current caps only from an actual power capability and a positive
lower bound on the **same physical voltage**. Transformer `s_rating` is a schema
base quantity, not an invented operating cap. Missing DER capabilities remain
visible. Eight bounded propagation sweeps use electrical identities without an
optimization or incumbent solution. No nominal phase-angle sector is assumed.
See [schema semantics](schema_fields.md) and [bound details](soc.md).

The static AC electrical model includes explicit grounding, switches, shunts,
static inverter capabilities, and winding-level fixed transformers, including
single-phase, center-tapped, Dy/Yd, autotransformer, open-delta regulator and
multiwinding cases. This is implemented scope, not proof that every parser path,
parameter combination, or benchmark solves correctly. Taps remain fixed and
control laws are excluded. LinDist3Flow has its own applicability rules.

The baseline passed 4,707 tests and 13 optional BMOPFTools reducer-parity checks.
Analytical fixtures, migrated OpenDSS regressions, and AC containment checks give
complementary evidence. They do not constitute an exhaustive relaxation proof.
BMOPFTools is a useful independent NLP comparator, with documented transformer
and PowerIO interpretation inconsistencies; see [the containment audit](ac_validation.md)
and [BMOPFTools issue #393](https://github.com/frederikgeth/BMOPFTools.jl/issues/393).
Compare identical physical contracts before interpreting an objective difference.

Recovery is the clearest remaining limitation. Conditional moment recovery once
produced a 357.53 V magnitude error and approximately 29,433 A KCL residual on
LV t500 despite an `OPTIMAL` solve. The new default voltage tree reduced maximum
magnitude differences to about 0.70 V and 1.17 V on the LV snapshots, but maximum
KCL residuals remained about 49 A and 45 A. Kim32 reduced those residuals to about
18 A and 31 A, still material. These are useful voltage estimates, not verified
AC-feasible dispatches or trustworthy line-loading certificates.

Retain the voltage-tree default, original-network reconstruction, raw moments,
and full residual/unassessed diagnostics. Retain all reduction warnings. A reduced
model with approximate events cannot automatically furnish an original-network
lower bound. `series_merge_policy=:exact` restricts series merging, not every
other reduction operation. Dropping intermediate bus constraints remains opt-in.

## Reproducible starting configurations

These are existing options, not new named API profiles:

```julia
using FormulationLab, Clarabel

base = IVRSOC(physical_projections=true, strengthening=:linear,
              clique_size=32, lnc=:off, voltage_recovery=:voltage_tree)
kim32 = IVRSOC(physical_projections=true, strengthening=:kim,
               max_triplets=8, clique_size=32, lnc=:off,
               voltage_recovery=:voltage_tree)
kim12 = IVRSOC(physical_projections=true, strengthening=:kim,
               max_triplets=8, clique_size=12, lnc=:off,
               voltage_recovery=:voltage_tree)
reference = IVRSDP(profile=:reference)

prepared = prepare_network(input; reduction=:bmopf) # inspect reduction_report
result = solve_opf(prepared, base; solver_options=(
    verbose=false, tol_feas=1e-7, tol_gap_abs=1e-6, tol_gap_rel=1e-7))
full = reconstruct_solution(prepared, result)       # inspect physical diagnostics
```

The tolerances above are the latest study settings, **not** all package defaults.
The implicit Clarabel SOC optimizer sets static regularization to `1e-7`,
iterative refinement limit to 30, and absolute gap tolerance to `1e-7`; feasibility
and relative gap use Clarabel's defaults unless overridden. An explicit optimizer
factory keeps its own defaults. Kim's constructor triplet budget is 16, so the
experiment's eight-triplet setting must be specified. Reproduction also requires
the matching input preparation, scaling and time limit in the study manifests.

## Next experiments, not locked-in claims

The subsequent [controlled comparison and implementation plan](soc_performance_plan.md)
measures native solver time and identifies the small-state physical-basis path
as the main performance problem. The historical decisions above remain the
baseline; that study adds an explicit sparse-coordinate speed–strength option.

The next target is **Clarabel solve time**, superseding the earlier report's
emphasis on construction caching. First record native solver time, iterations,
KKT factorization/refinement work, cone counts and sizes, and repeated timings at
matched accuracy. Keep build, extraction and original-state reconstruction separate.

Then test genuinely local sparse coordinates against dense fallback, and tune
regularization/refinement and tolerances against an explicit watt-error budget.
Explore fixed structural pruning of redundant projections and bounded LP/SOC
hybrids; a smaller system may be faster even with a weaker objective bound.
A native branch-current SOC formulation is another candidate, provided exotic
winding and neutral equations retain their physical meaning. These are experiments,
not established improvements or changes made by this decision record.

Do not silently regularize the objective and continue reporting its value as the
original source-import bound. Do not select cuts from an incumbent solution.
Any cheap structural policy must be fixed before solving and logged. A bounded
AC correction can be investigated separately for state quality; it is not part
of the fixed conic formulation, and its runtime and failures must remain visible.
