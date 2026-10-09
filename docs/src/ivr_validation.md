# Exact-IVR validation and evidence map

The validation claim concerns the declared static exact-IVR contract. It does
not cover every BMOPF schema field, optimized controls, dynamic operation or
global optimality. The [component inventory](coverage.md),
[scope and operating bounds](ivr_nlp.md), and [equivalence arguments](ivr_theory.md)
define that domain. Use this page to locate executable evidence rather than
infer coverage from the number of successful solves.

## Distinct claims require distinct evidence

An exact transformation requires a map from retained coordinates to physical
voltages and currents, a corresponding encoding of admissible physical points,
and preservation of equations, operating limits and the objective on the stated
domain. The mathematical arguments establish why those maps are valid. Numerical
point tests probe their implementation; agreement of two optimized objectives
alone is insufficient.

For an accepted comparison, check all of the following:

1. The inputs, physical objective, bounds and modelling policies agree. Record
   equipment nameplate policy and distinguish a physical scenario change from
   a coordinate or unit change.
2. Every formulation can encode the common physical start. When interpreting
   native linear algebra, also inspect the actual primal, slack, dual and scaling
   state: the same physical primal point does not imply the same KKT system.
3. Each endpoint satisfies the original SI circuit equations and operating
   limits, with no unassessed required records. An optimal Ipopt status alone
   does not establish this.
4. Each endpoint belongs to its own model and the full reference, and the
   reference endpoint belongs to each candidate. Evaluate the power objective
   independently in physical units.
5. Recovery and JSON serialization preserve the physical result contract and
   channel conventions. Nonunique currents remain explicitly unavailable.
6. Rank performance only after correctness admission, objective comparability
   and the declared experimental controls pass.

The [emitted inventory](ivr_constraint_inventory.md) answers whether every
current solver constraint has provenance. Its `complete_emitted_coverage` flag
does not establish input-schema completeness. `complete_input_coverage=false`
remains explicit. Neither a green test suite nor the matrix below changes that
boundary.

The [supplied-bound inventory](ivr_declared_bounds.md) adds a separate check of
declared scalar channels, inheritance, nameplate policies and fixed-setting
intervals. Use its declaration-coverage flag alongside emitted coverage; neither
flag replaces the independent physical and negative-witness tests.

## Executable evidence by requirement

The [historical admission recheck](ivr_evidence_recheck.md) verifies frozen
source identity and reproduces the principal retained timing and export audits.
It covers 3,168 measured solves and 336 excluded warmups, with no new solve or
timing claim. Current correctness tests and historical timing admission have
different purposes and are not substitutes for each other.

Paths in this table are relative to the repository root. The tests are included
by `test/runtests.jl`; their fixtures are tracked in the repository. The matrix
identifies targeted evidence, not an exhaustive Cartesian product of every
device, bound, topology, objective and numerical option.

| Requirement | Principal executable evidence | What it probes |
|:---|:---|:---|
| Single-phase, three-wire delta and four-wire explicit neutral | `test/ivr_mixed_device_tests.jl`, `test/ivr_elimination_tests.jl` | Full/reduced membership, matched starts, mixed devices, power cost/tracking and physical exports across 2/3/4 conductors. |
| Operating bounds | `test/ivr_bound_coverage_tests.jl`, `test/ivr_equipment_trace_tests.jl` | Individual array entries, signed P/Q boxes, sequence/neutral voltage, inherited and overridden equipment limits, endpoint maps and winding quantities. Tightened limits must reject the same physical witness in both NLP and SI checks. |
| Power objectives | `test/ivr_power_objective_tests.jl`, `test/ivr_mixed_device_tests.jl` | Analytic dispatch, weighted P/Q channels, quadratic cost, exchange tracking, delta coil conventions, internal IBR losses and objective scaling. |
| Voltage-dependent load laws | `test/ivr_load_law_tests.jl`, `test/ivr_load_power_lifting_tests.jl` | Independent states, full/reduced solves, positive-voltage domain, fixed-voltage equalities, power lifting and update refusals. |
| Fixed switches and capacitors | `test/ivr_switch_tests.jl`, `test/ivr_capacitor_tests.jl` | Open/closed states, both-end ratings, terminal maps, scalar/per-coil bank contracts, independent circuit witnesses and specialization fallback. |
| Ordinary transformers and regulators | `test/ivr_transformer_tests.jl`, `test/ivr_regulator_tests.jl`, `test/ivr_device_elimination_tests.jl`, `test/ivr_nameplate_tests.jl` | Fixed connection laws, leakage, excitation, finite grounding, conductive bonds, nameplate policy and retained bounds under current substitution. Delta circulation is retained. |
| General multiwinding transformers | `test/ivr_nwinding_nonstar_tests.jl`, `test/ivr_nwinding_limit_tests.jl`, `test/ivr_nwinding_elimination_tests.jl` | Non-star leakage, mixed connections and delta roll, reverse flow, live winding caps, excitation, independent ampere-turn/leakage/loss identities and recovery. |
| Static IBR capability | `test/ivr_ibr_tests.jl` | PCC/internal conventions, filters, setpoints and budgets; each supported operating bound rejects a fixed witness. |
| Transformer, ground and power units | `test/ivr_transformer_scaling_tests.jl`, `test/ivr_regional_ground_scaling_tests.jl`, `test/ivr_power_base_tests.jl`, `test/ivr_base_formulation_tests.jl` | Positive coordinate changes, physical equivalence, objective normalization and complete start encoding under declared bases. |
| Conditional reductions and updates | `test/ivr_zero_load_tests.jl`, `test/ivr_generator_updates_tests.jl`, `test/ivr_device_elimination_tests.jl` | Certificate validity, zero-voltage counterexamples, atomic update refusal, original bounds and retained observations. |
| Emitted constraints and physical provenance | `test/ivr_constraint_inventory_tests.jl`, `test/ivr_equipment_trace_tests.jl` | Missing/stale/duplicated provenance, added constraints, inheritance, tautologies and shared declarations. |
| Supplied operating-bound declarations | `test/ivr_declared_bound_inventory_tests.jl` | Independent input-channel enumeration; loss of both a row and its provenance; scalar/array contracts, retained tap aliases, inactive declarations and supported generator updates. Declaration and emitted completeness remain separate from full schema coverage. |
| Canonical physical results | `test/result_export_tests.jl`, `test/result_sequence_tests.jl` | Identical physical leaf paths and recovered values across formulations, SI units, transformer/IBR/ground observations, sequence-bound phase order, owned snapshots and JSON round trips. |
| Benchmark admission and metric | `test/ivr_profile_study_tests.jl` | Failed/incomplete trials cannot win, incompatible objectives prevent ranking, and Ipopt wall time is distinct from compilation or extraction. |
| Joint preflight evidence | `test/ivr_joint_preflight_tests.jl` | Complete cost/tracking design, current controls, raw trial/artifact agreement, bound inventories and canonical exports are checked before timing output is created. This read-only gate does not establish isolation. |
| Unknown or unsupported inputs | `test/ivr_input_annotations_tests.jl` and device-specific scope tests | Retained metadata, electrical-field validation, unsupported controls and explicit refusals. |

No finite set of numerical tests proves that no bound was forgotten. Confidence
comes from comparing the accepted-field contract with the emission code,
independent physical evaluations, per-bound negative tests and transformation
proofs. A missing row in that comparison is a coverage gap even when all tested
models solve successfully.

## Reproduce correctness before performance

With the documented development environment installed, run from the repository
root:

```sh
julia --project=test --startup-file=no test/runtests.jl
python3 -m unittest discover -s test -p 'test_ivr_*trace.py'
python3 -m unittest discover -s test -p 'test_ivr_native_kkt.py'
python3 -m unittest discover -s test -p 'test_ivr_refinement_policy.py'
julia --project=docs --startup-file=no docs/make.jl
```

The Julia suite includes small benchmark-runner regressions. Their elapsed values
test the recording and admission machinery; they are not controlled performance
evidence and must not be promoted into speed claims. The documentation build
executes the motivating examples and tutorials, including the full/reduced
[selection example](ivr_selection.md).

The optional `test/integration` environment supplies separate BMOPFTools
comparisons; see `test/integration/README.md`. For example,
`ivr_nlp_reference.jl` covers 2/3/4-wire networks and
`ivr_nameplate_reference.jl` tests active/absent nameplate caps and dispatch.
These require the declared reference checkout and are not implied by a passing
core suite. Keep comparator failures and differences visible; independently
reconstructed currents are not independent measurements.

The 9 October 2026 correctness checkpoint reran both optional comparisons against
the clean BMOPFTools revision `a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`.
All four 2/3/4-wire cases pass the reference/native SI checks, physical source
import comparison and bidirectional full/reduced membership checks (36 assertions).
The nameplate comparison passes all 12 native combinations of active/absent cap,
two power bases and three lifting choices, including transformer result fields
and the BMOPFTools JSON reader (108 assertions). These are per-unit correctness
checks, not isolated performance trials or complete transformer-family parity.
The original result-schema reference remains documented in [physical results](results.md).

Manufactured fixtures make the component and mixed-network tests reproducible
without the external feeder collection. Larger empirical conclusions also
depend on their declared input data, transformations and environment. The
[performance guide](ivr_performance.md) links the corresponding studies and
qualifies their populations. `examples/benchmark_ivr_profiles.jl` provides the
generic runner; the tracked `benchmark_ivr_mixed_devices.jl`,
`benchmark_ivr_singlephase_transfer.jl`, `benchmark_ivr_threephase_transfer.jl`
and multiwinding study drivers construct the corresponding declared comparisons.
Running one small fixture does not reproduce an entire historical campaign.

## Performance admission and remaining scope

Retain exact inputs or their reproducible construction, hashes, software and
solver versions, candidate options, objective coefficients, per-unit bases,
physical starts, solver settings, raw acceptance results, warmups, repetitions
and run order. Isolated paired experiments must record competing-process checks
and exclusions. Report Ipopt wall-clock distributions with compilation excluded;
do not replace them with iterations, factor entries or total Julia elapsed time.

Timing campaigns remain deferred until explicitly authorized. Existing admitted
campaigns support only the workload-specific statements in the performance guide.
New diagnostic candidates, including the [initial pivot threshold](ivr_initial_pivot.md),
remain unranked by runtime. Completion of correctness work does not fill missing
timing evidence or broaden the accepted physical scope.
