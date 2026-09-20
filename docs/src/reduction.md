# Network reduction and original-network states

Network preparation is independent of the formulation and optimizer. It consumes
an SI BMOPF snapshot through the existing PowerIO boundary; BMOPFTools is **not**
a runtime dependency. The compatibility implementation is adapted from
BMOPFTools revision `ddd588f7143ae218142e4176e8086199179722c3`; its BSD license is
retained in `THIRD_PARTY_BMOPFTOOLS_LICENSE.md`.

```julia
using FormulationLab, Clarabel

prepared = prepare_network("case.json"; reduction=:bmopf)
result = solve_opf(prepared, IVRSOC(objective=:source_import);
    solver_options=(verbose=false,))
full = reconstruct_solution(prepared, result)

full.buses                         # every original bus/terminal: vr, vi, vm, va
full.lines                         # every original line: currents, powers, loss
full.point                         # ACPoint with original IDs, SI volts and amps
full.raw_result                    # unchanged optimization result
full.diagnostics["physical"]       # original-network equations and operating limits
reduction_report(prepared)
```

The same prepared input is accepted by `build_opf`, `solve_opf`, and the direct
LinDist3Flow, SOC, and SDP builders. Reduction does not expand a formulation's
component applicability: for example, a retained π line still has to pass
LinDist3Flow's checks. All topology decisions precede optimization. There is no
iterative outer approximation or solution-dependent rebuilding.

## Compatibility policy

`ReductionOptions()` selects the BMOPFTools pipeline:

1. Collapse eligible fixed closed switches, intersecting bus bounds.
2. Remove fixed open switches.
3. Prune dangling passive lines and leaf buses.
4. Merge eligible series lines.

All four operations can be disabled independently through `closed_switches`,
`open_switches`, `dangling_lines`, and `series_lines`. `profile=:off` keeps an
independent unreduced snapshot.

Same-linecode series merging adds lengths, including for π sections. Series-only
inline absolute impedances are added as matrices. Devices, grounding, mismatched
terminal order, segment apparent-power/angle limits, and unsupported inline
shunt overrides block merging. Intermediate voltage bounds also block merging
unless `allow_drop_bus_constraints=true` is explicitly selected.

```julia
options = ReductionOptions(
    closed_switches=false,
    dangling_lines=false,
    series_merge_policy=:allow_approximate,
    allow_drop_bus_constraints=true,
)
prepared = prepare_network(network; reduction=options)
```

`series_merge_policy=:exact` disables approximate **series merges**. It does not
make the other pipeline operations exact: stub pruning can discard charging and
bounds, and switch collapse can discard switch flow limits. The event log records
these separately. In addition to upstream events, pruned leaf bounds are recorded.

Length aggregation redistributes π shunts and generally changes the terminal
relation. Taking the tightest current limit along a π chain does not enforce
every original segment's current limit. The reconstructed state is checked against
original limits, including at removed buses. Approximate reduction means a solver
objective/bound applies to the reduced model; its difference from an unreduced
NLP objective is a **numerical objective comparison**, not a certified OPF gap.

A concise warning is emitted for applied approximations. `warn=false` suppresses
printing for batch studies; structured diagnostics are always retained.

## Reconstruction equations

Let each original line have series current ``j``, series impedance ``Z``, and
endpoint shunt admittances ``Y_f,Y_t``. Reconstruction solves

```math
v_f-v_t=Zj,\qquad i_f=j+Y_fv_f,\qquad i_t=-j+Y_tv_t.
```

Retained endpoint phasors are prescribed. At eliminated passive terminals,
Kirchhoff's current law determines interior voltages. Pruned branches are included
with their original shunts and zero external injection at their removed leaves.
Closed-switch bus identities are restored. Sparse current–voltage equations avoid
inverting individual impedance matrices and support singular series impedances.
Sparse LU is used when possible, with sparse QR for indeterminate systems; the
latter assignments are flagged. This pass assembles a fresh sparse system per
call; factorization caching is a future optimization, not currently promised.

For identical series-only construction, the equations reduce to length-weighted
complex-voltage interpolation. For π chains, internal circuit equations are
satisfied given the retained endpoint voltages, but endpoint injection can differ
from the aggregate model. `boundary_current_mismatch_A` measures this difference
across retained terminals when reduced line-current observations are available.

Every original line's phase powers and total complex loss follow from
``s_f=v_f\odot\overline{i_f}`` and ``s_t=v_t\odot\overline{i_t}``.

The input phasors themselves are estimates:

- LinDist3Flow uses solved magnitudes with reference angles. These angles do not
  solve AC power flow. Native transformer/source/generator outputs remain in
  `raw_result`; device current estimates and local transformer fits are provided.
- SOC uses solved diagonal voltage moments for magnitudes and a maximum-correlation
  spanning forest of available voltage products for phase differences. Sources
  anchor the forest. This avoids inversion of indefinite, nearly singular
  separator moments. Unanchored coordinates receive a flagged zero-angle convention.
  `IVRSOC(voltage_recovery=:conditional)` retains the earlier conditional-moment
  estimator for comparisons; it can be unstable on large cases. Neither method
  is PSD completion or an AC-feasibility claim. Device currents are estimated
  from optimized complex power and the recovered channel voltage where available.
- SDP uses its configured voltage candidate. Its current candidates use the
  conditional-moment estimate; choosing dominant-voltage recovery can therefore
  introduce additional disagreement between those estimates.

Reduced device currents are retained where available. Missing inverter filter
currents are recovered from the terminal currents; a three-leg circulating mode
uses the least-norm convention. Missing transformer
currents are fitted to small fixed-tap linear systems, with L3F winding-power
estimates where available. Indeterminate transformer modes use the least-norm
convention. Collapsed switch currents are assigned from original nodal balances
across contraction-tree cuts. Missing/nonfinite device observations remain
explicit in the physical report; current assignment does not fabricate source
injections to hide a balance error.

`physical` contains equation and limit residuals, unassessed channels, and signed
nodal balance. Voltages, currents, and powers have separate SI residual scales.
Ground current at an ideal earth connection is not treated as a KCL violation.
The original solver status and raw optimized powers are preserved.

## Portable provenance

```julia
using JSON3
json = JSON3.write(reconstruction_plan(prepared))
restored = restore_prepared_network(JSON3.read(json, Dict{String,Any}))
```

The version-1 plan stores original and reduced snapshots, applied options, bus
aliases, and chronological reduction events. Original segment parameters,
orientations, terminal maps, and device identities therefore survive. There are
no JuMP references or Julia factorizations in the serialized plan. Treat prepared
objects as immutable and prepare again if topology or electrical parameters change.

## Verification and numerical studies

Default tests cover all four formulation adapters, exact series interpolation,
π-chain internal balance, shunt-bearing stubs, reverse orientation, switch current
recovery, merge blockers, and serialization. The optional integration environment
compares reduced networks directly with BMOPFTools under matching policies:

```sh
julia --project=test/integration test/integration/reduction_parity.jl
julia --project=test/integration examples/benchmark_reduction.jl \
    examples/results/reduction_manifest.json examples/results/reduction_soc.json
```

The benchmark compares unreduced and reduced Ipopt NLPs with fixed Clarabel SOC
profiles. It records original-network voltage errors, operating-limit violations,
current balance, objective differences, build/solve/reconstruction times, and cone
types. It never builds proper SDP cones. See the dated reduction study in
`examples/results/` for measured trade-offs and remaining limitations.
