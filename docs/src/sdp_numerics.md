# Numerical profiles and Clarabel

`IVRSDP()` now uses the `:clarabel` numerical profile. Formulation choices remain
independent of the optimizer: this profile can also be solved with Mosek. Clarabel
and Mosek remain optional dependencies; BMOPFTools is not a dependency.

```julia
using FormulationLab, Clarabel
result = solve_opf(input, IVRSDP(objective=:source_import, s_base=1e4);
    solver_options=(verbose=false,))

# Dense reference, without derived current cuts or objective normalization:
reference = solve_opf(input, IVRSDP(profile=:reference, objective=:source_import))

# Each choice can be controlled independently for experiments:
formulation = IVRSDP(decomposition=:chordal, current_bounds=true,
                     lnc=:lines, port_rlt=true)
```

| Option | Clarabel profile | Reference profile |
|:--|:--|:--|
| `basis` | `:auto` | `:orthonormal` |
| `cone` | `:real` | `:hermitian` |
| `shunt_coordinates` | `:current` | `:admittance` |
| `scale_objective` | `true` | `false` |
| `current_bounds` | `true` | `false` |
| `preprocess` | `true` | `false` |
| `decomposition` | `:auto` | `:dense` |
| `recovery` | `:anchor` | `:dominant` |
| `consistency` | `:auto` | unused on dense path |
| `lnc` | `:off` | `:off` |
| `port_rlt` | `true` | `true` |
| `clique_merge` | `:size` | unused on dense path |
| `clique_size` | `32` for `:size`, `12` for `:cost` | unused on dense path |
| `clique_overlap_weight` | `1.0` | unused on dense path |
| `state_scaling` | `:voltage_region` | `:global` |

These are engineering choices, not a guarantee that Clarabel will solve every
instance. `ALMOST_OPTIMAL` and failed solves are not silently promoted to optimal
results. For automatically selected Clarabel optimizers, the chordal path with local
moments uses
`static_regularization_constant=1e-5` and `iterative_refinement_max_iter=30`.
The dense and shared-moment paths retain Clarabel defaults. Accuracy tolerances are not relaxed.
An explicitly supplied optimizer factory is never retuned, and `solver_options`
can override the automatically selected settings. The automatic decomposition currently retains a dense cone for reduced
orders at most 32. It also retains the dense cone when a clique restriction spans
the entire reduced state. Otherwise it uses a chordal PSD-completion formulation.
Explicit `:dense` and `:chordal` requests support comparisons; the full-span shortcut
also applies to `:chordal` because decomposition cannot reduce the cone order there.

## Electrical coordinates and preprocessing

All physical inputs remain in SI. Internally, voltage is divided by the maximum
source magnitude, current by `s_base / v_base`, and power by `s_base`. The power
base is still user-specified and defaults to 10 kVA. It is not inferred from solved
voltages or dispatch. A representative per-phase feeder throughput is a useful
starting point for choosing it; power-base selection alone does not fix a poorly
conditioned cone representation.

The electrical rows are equilibrated before nullspace elimination. Automatic
basis selection uses the structure-preserving physical basis (`:physical_sparse`)
for reduced orders at most 32 and
uses the sparse basis for larger systems. The `:sparse` basis uses SuiteSparse QR and a triangular solve for the free state
coordinates. This preserves structural zeros instead of introducing dense
roundoff-sized coefficients through an SVD. The alternative physical
basis selects independent physical coordinates using pivoted QR of the nullspace
transpose. If their row indices are `p`, the change is `N ← N / N[p,:]`. The selected
rows are the identity by construction. This changes coordinates, not physics.
The `:physical_sparse` path retains the same independent physical coordinates
but reconstructs their dependent rows using sparse electrical solves; see
[the derivation and fallback checks](soc_profiles.md). The legacy `:physical`
option remains available. No small coefficient is dropped merely because it is small. Rank decisions use
Float64 linear algebra, so this is not an interval-certified elimination.

### Voltage-region preconditioning

`state_scaling=:voltage_region` applies an additional diagonal change of state
coordinates **before** electrical elimination. If `D` is the positive diagonal
scaling matrix, the builder eliminates `A*D*x=0` and returns `N=D*Nx` in the
original per-unit coordinates. Every downstream voltage/current map, power,
bound, LNC, audit and result therefore keeps the same units and meaning. For a
moment, this is the invertible congruence `W=D*Wx*D'`; it preserves PSD.

Regions join buses across lines and closed switches, but not transformers. The scale
hints, in priority order, are prescribed source magnitudes, transformer nominal
winding voltages, and declared bus voltage bounds or load nominal voltages.
Among hints of equal priority, the geometric mean is used. A region without a
hint retains the global base. All live terminals of a bus, including neutrals,
receive the same voltage scale. Current scales are inferred inversely from the
voltage-region scales of their physical channels, preferring direct current
observations over composite maps; unmatched coordinates retain scale one.
Incidence-row norms do not change the scale of a uniform-voltage feeder.
Delta coil maps remain explicit. Nominal coil and terminal magnitudes can differ;
these hints are numerical preconditioners, not inferred operating points.

Scales are rounded to powers of two and bounded between `2^-40` and `2^40`.
No hint creates an operating bound or changes a tap or finite ground impedance.
The scaled electrical rows are equilibrated again. If the detected nullity
differs from the original basis, or the relative electrical residual exceeds
`1e-10`, the builder uses the original basis. Diagnostics record scale extrema,
region/fallback counts and whether this basis fallback occurred. This check
costs an extra basis construction; it is intended to protect numerical behavior,
not reduce model-building time.

This is the Clarabel SDP profile's default; `state_scaling=:global` retains the
previous elimination coordinates and remains the reference profile's default.
Local clique normalization already addresses part of the scaling problem, so
additional region scaling does not necessarily improve a particular feeder.

### Optional cost-aware clique amalgamation

```julia
formulation = IVRSDP(
    clique_merge=:cost,
    clique_size=12,
    clique_overlap_weight=1.0,
    state_scaling=:voltage_region,
)
```

The legacy `clique_merge=:size` greedily merges adjacent tree bags up to
`clique_size` **original state coordinates**. The alternative `:cost` computes
electrically reduced ranks first. Its `clique_size` caps the **reduced order of
each proposed merge**; an original indivisible clique may exceed the cap.
The cost policy defaults to cap 12 and weight 1 following the conservative
benchmark sweep; explicit keywords can override both. The size policy remains
the default because the tested cost policies did not consistently improve time.
It accepts only merges that decrease the structural surrogate

```math
C=\sum_k (r_k^3+8)+\lambda\sum_{(k,p)}s_{kp}^3,
```

where `r_k` is a complex PSD order, `s_kp` is an independent separator rank,
and `λ=clique_overlap_weight`. A rank-`s` complex Hermitian separator requires
`s^2` real consistency equations. The constant per-cone overhead and separator
weight are engineering heuristics: this surrogate does **not** estimate actual
KKT fill, factorization time, or Clarabel's exact treatment of scalar/SOC blocks.
The separator term is most relevant to local consistency; shared consistency
has a different linear-system structure and needs separate measurement.

Only adjacent clique-tree bags are amalgamated. This preserves running
intersection and all required electrical/product supports. Independent separator
consistency is retained in full, so this changes the representation of the SDP,
not its strength. Existing dense/full-span shortcuts still apply. Diagnostics
include separator ranks, total potential real separator dimension, and the
surrogate cost; these describe the candidate clique cover even if it falls back
to a dense cone. They are not counts after affine preprocessing.

The approach follows the clique-amalgamation tradeoff studied by
[Garstka, Cannon and Goulart](https://arxiv.org/abs/1911.05615), with a distinct,
simple reduced-rank surrogate here. PSD-completion equivalence relies on the
[Grone–Johnson–Sá–Wolkowicz completion theorem](https://doi.org/10.1016/0024-3795(84)90207-6).
We do not implement the weaker selective-consistency relaxation proposed by
[Andersen, Hansson and Vandenberghe](https://arxiv.org/abs/1308.6718) in this mode.

These options also pass through `IVRSOC`, but changing coordinates or the clique
cover can change the strength of an SOC outer relaxation. SDP equivalence does
not imply SOC equivalence. Existing SOC presets and `SOCOptions()` explicitly
retain `state_scaling=:global`. An explicitly supplied `SDPOptions` object in
`SOCOptions(electrical=...)` uses the supplied object's settings.

For shunts, explicit current coordinates impose `j = Y*v` with each row divided
by its largest admittance magnitude. KCL then uses `j` directly. Zero admittance
rows introduce no current. This supports singular and coupled shunt matrices and
retains finite grounding impedance, including very large admittances. It does not
replace a finite grounding shunt with an ideal ground.

Zero upper voltage/current bounds expose linear directions forced to zero in any
PSD moment. Those directions are included in the electrical elimination. Already
satisfied source-voltage bounds and zero lower squared-voltage bounds are omitted;
contradictory prescribed-source bounds remain explicit infeasibility constraints.
The affine preprocessor downscales large rows by powers of two (it never
amplifies a tiny row that could represent nullspace roundoff) and merges only identical
scaled coefficient vectors. It combines equal lower and upper bounds into one
equality and retains contradictory bounds. It does not merge approximately
parallel rows.

## Equivalent PSD representations

For reduced order greater than two, `cone=:real` uses a free real symmetric
matrix `X ⪰ 0` of order `2m` and the projection

```math
H = \tfrac12\left(X_{11}+X_{22}+\mathrm{i}(X_{21}-X_{12})\right).
```

The image is exactly the complex Hermitian PSD cone: every PSD `X` gives PSD `H`,
and every PSD `H` has a real PSD preimage. This avoids tying the real blocks with
additional structural equalities. It introduces more scalar variables than the
Hermitian embedding; smaller cone order can therefore matter more than variable
count. Order-one cones are nonnegative scalars; order-two complex PSD cones are
represented exactly by rotated SOCs. Neither shortcut weakens the relaxation.

For chordal decomposition, a sparsity graph covers every electrical equation's
support, every required voltage/current product, and every predeclared LNC.
Minimum-degree elimination adds fill edges, producing a chordal graph and maximal
cliques. Adjacent tree bags are amalgamated up to `clique_size=32` original
state coordinates to avoid excessive numbers of small cones; larger initial
bags are retained. A maximum-weight clique tree supplies the running-intersection structure.
Automatic consistency uses a shared reduced moment for orders at most 32 and
local moments for larger systems. `consistency=:local` uses independent PSD
moments on each clique's
electrical coordinates. These are obtained by restricting the global electrical
nullspace, so dependencies implied elsewhere in the network are retained.
Local coordinates are scaled by their electrical basis-row norms, so tiny neutral
voltages do not force an otherwise well-scaled PSD variable toward a singular
face. Separator moment equalities use the corresponding product scales.
Equality of moments on independent separator coordinates enforces all required
overlap consistency without redundantly equating electrically dependent entries.
The alternative `consistency=:shared` uses one unrestricted reduced Hermitian
moment to supply all clique entries. It eliminates overlap equalities, but can
produce a much denser solver system. Its larger clique restrictions use real
symmetric PSD embeddings; the `cone` choice applies to local moments and the dense
fallback.

Why is this equivalent? A global feasible PSD moment restricts to feasible clique
moments. Conversely, consistent PSD clique moments have a PSD completion `W`.
Every row `a` of the electrical system has its support in a clique and satisfies
`a*W*a' = 0`. PSD then implies `a*W = 0`, so the completion lies in the electrical
nullspace. All objective and operating-limit products are covered by the graph
and unchanged by completion. This argument does not require radial topology or
independent transformer phases. Dropping arbitrary cross-phase blocks would not
provide this guarantee.

The build's `moment` is a partial Gram container on the chordal path.
`value.(build.moment)` computes a numerical dense completion; `build.nullspace` is
then the identity because these entries already use the original scaled state.
On the dense path, the two fields retain their reduced-moment/basis meanings.
An arbitrary product outside the clique cover raises an error. Declare such LNCs
in `SDPOptions(voltage_lncs=...)` before building, so their support is covered.
Late cuts on already covered products remain supported.

## Derived current bounds

For the same physical channel, `S = V*conj(I)`, a finite bound `|S| ≤ Smax` and
strictly positive bound `|V| ≥ Vmin` imply

```math
\widehat{|I|^2} \le (S_{\max}/V_{\min})^2.
```

This is a valid cut for the AC model, not an identity already implied by the SDP.
The implementation uses constant-power load magnitudes, finite generator/source
power boxes, and declared apparent-power ratings. It uses matching physical
voltage maps, prescribed source phasors and conservatively propagated domains. Delta and terminal-pair channels need
a positive bound on their coil voltage; terminal-to-ground bounds are not
substituted for line-to-line bounds. Missing positive bounds cause the cut to be
skipped. Voltage-dependent loads are not assigned constant-power current bounds.
Declared tighter current ratings are retained. Small outward padding addresses
ordinary rounding, not rigorous certification. Existing LNCs remain independently
selectable; enabling all available cuts is not necessarily numerically beneficial.

## Objectives, recovery and diagnostics

Objective normalization is independent of electrical per unit. The model objective
is divided by its largest nonzero coefficient magnitude (with a small positive
floor). `SDPBuild.objective_scale` gives the divisor. `SDPResult.objective` and
`solver_objective_bound` are converted back to the original objective units:
source import is W, and costs retain their original units. Direct users of
`objective_value(build.model)` must multiply by `build.objective_scale`.
Use `solve_sdp_opf(build; solver_options=...)` to solve an inspected or modified
build without assembling it a second time.

The default voltage candidate uses the source-anchored column of the voltage Gram:
`z_candidate = W[:,anchor] / conj(v_anchor / v_base)`. In exact arithmetic this
preserves the reference phasor and homogeneous electrical equations, including
when an unconstrained floating mode dominates the largest eigenvector. It need
not satisfy nonlinear power laws or voltage lower bounds. The reference profile
retains dominant-eigenvector recovery. Neither candidate is an AC certificate.

Chordal completion uses a separator pseudoinverse with relative tolerance
`sqrt(eps(Float64))`; numerical low-rank completion is also not a PSD certificate.
The total moment rank ratio depends on coordinates and free completion choices.
The separate voltage rank ratio, decomposition, clique orders, electrical basis
residual, current-cut count and objective scale are recorded in
`solve_diagnostics(result).numerical`. Solver bounds remain uncertified numerical
reports. Compare physical residuals and an independently feasible AC solution
before claiming an optimality gap.

`examples/benchmark_sdp.jl` compares the reference, default, and default-plus-LNC
profiles on the same source-import objective. Source-bus generator removal is
explicitly opt-in. It records statuses, residuals, timing, numerical settings and
objective units, and accepts an optional Mosek optimizer without adding a runtime
dependency. Solver time limits may not bound model construction or factorization
setup; use external process limits for unattended large-case sweeps.

## ENWL validation, 11 September 2026

The default profile was checked on four selected files from
`BMOPFDraftData/benchmarks/ENWLbenchmark/reduced`; this is not a full 128-case sweep.
Underscore-prefixed metadata and generators on voltage-source buses were removed
in memory. Original finite shunts and all other static component data were retained.
Both the SDP and the previously obtained BMOPFTools/Ipopt comparison minimize
source active-power import. Negative import denotes export. LNCs are off.

| Case | Buses | Power base (VA) | Clarabel import (W) | Ipopt import (W) | Maximum voltage difference (V) |
|:--|--:|--:|--:|--:|--:|
| `network_23_Feeder_3.json` | 5 | 1333.33 | -1705.610445 | -1705.610446 | 1.5e-05 |
| `network_11_Feeder_2.json` | 8 | 1829.47 | 1221.897996 | 1221.897996 | 2.95e-05 |
| `network_9_Feeder_3.json` | 23 | 6865.26 | -406.697689 | -406.697694 | 1.14e-05 |
| `network_18_Feeder_5.json` | 87 | 14666.67 | -2664.267679 | -2664.267706 | 7.77e-07 |

All four default-profile solves returned `OPTIMAL`. The largest recorded scaled
model constraint violation was 3.6e-12. The 87-bus model uses 40 clique cones with
reduced orders 5–10, replacing a dense complex cone of order 54. It built in
13.7 seconds and solved/recovered in 2.0 seconds in this run. This is a single
local timing measurement, not a controlled performance benchmark; the first
case also includes compilation. Default accuracy tolerances were retained.

For the 87-bus case, the numerical dual objective was -2664.267787 W, below the
Ipopt value -2664.267706 W. The SDP primal value is about 0.000027 W above Ipopt.
These remain floating-point reports rather than a certified optimality gap.
An additional smaller-case sweep using the physical basis returned `OPTIMAL`
for all 12 combinations of the three feeders, LNCs on/off, and QDLDL/CHOLMOD.
LNCs substantially increased solve time on the 23-bus case while barely changing
its already-tight bound; they remain optional. CHOLMOD failed on a larger
experimental model, so QDLDL remains the default linear solver.

Machine-readable default-profile results are in
`examples/results/enwl_clarabel_2026-09-11.json`. To reproduce, load each input
with JSON3, then call `benchmark_sdp` from `examples/benchmark_sdp.jl` with
`remove_source_generators=true`, the corresponding power base from the table,
and `variants=(:clarabel,)`. BMOPFTools/Ipopt were used externally for comparison;
neither was added as a runtime dependency.

## Dense-IVR and BranchFlow ENWL ladder, 21 September 2026

A second experiment compares BMOPFTools/Ipopt with Mosek solves of the dense
reference `IVRSDP` and `BranchFlowSDP` on 24-, 45-, and 96-bus reduced ENWL
feeders. Inputs and reported objectives remain in SI units; the optimization
models use per-unit coordinates internally. SDP results are accepted only after
an `OPTIMAL` termination and a maximum scaled JuMP residual no larger than
`1e-7`.

At the primary 10 kVA base with all available strengthening, the 24- and 45-bus
objectives agree with the feasible Ipopt objectives to about 0.0014 W or less.
Both formulations pass the residual gate at all three tested bases on those two
feeders. Dense IVR reaches the 180 s limit at every tested base on the 96-bus
case. BranchFlow solves the 96-bus case at 10 and 30 kVA, but its two accepted
objectives differ by about 0.235 W. The 10 kVA objective is about 0.075 W above
the feasible Ipopt point, so it must not be presented as a trustworthy lower
bound despite the solver status and small model residual.

The ablations expose two structural facts. First, these ENWL generator records
do not have finite P/Q boxes that activate the port-RLT construction, so the
port-RLT variants add no cuts. Second, automatic line LNCs require the
BranchFlow global voltage closure: on the 96-bus feeder they increase the model
from 10,548 to 176,724 variables and the recorded solve from about 0.4 s to
about 11 s. Implied-current bounds are much cheaper. Sparse/chordal IVR and
improved BranchFlow scaling are therefore higher-priority next experiments than
extending this dense reference ladder to still larger feeders.

The checkpointed data, full ablation tables, exact environment revisions and
reproduction command are in
`examples/results/enwl_sdp_ladder_mosek_2026-09-21.json`,
`examples/results/enwl_sdp_ladder_mosek_2026-09-21.md`, and
`examples/benchmark_enwl_sdp_ladder.jl`.

## Bound provenance and schema conventions

`bound_report(build)` returns `PhysicalBoundReport`. Entries contain a normalized
physical map, lower/upper magnitudes in per unit, a descriptive label, and the
last tightening provenance. Infinite endpoints mean no finite bound was derived.
The report also lists absent generator/IBR capability fields. An omitted reactive
limit is not silently replaced with a value inferred from active power.

Up to `bound_sweeps` (default 8) passes apply triangle and reverse-triangle
inequalities to the homogeneous electrical equations and registered connection
maps. Source phasors and declared voltage/current limits seed propagation;
constant powers or finite capability boxes can imply current bounds in subsequent
passes. No OPF, power-flow incumbent, or optimization-based bound tightening is
used. Derived domains feed load envelopes and automatic line LNCs as well as
current bounds. Small outward rounding margins are used, without claiming
interval-arithmetic certification. Disabling propagation with `bound_sweeps=0`
retains directly declared bounds and power/voltage deductions.

The pinned BMOPF 0.2.0 schema supplies the following conventions:

- Three-phase `vpp_min/max` entries follow `(1,2), (2,3), (3,1)` in phase-map order.
- Line `i_max` covers every conductor at both ends; line `s_max` covers phase
  conductors only. Line-specific values override linecode values.
- Source P/Q arrays can cover phase conductors without a neutral entry. Legacy
  full-terminal arrays remain accepted; a missing neutral power limit is unbounded.
- Generator and IBR three-wire dispatch/nameplate limits constrain phase-conductor
  powers. Delta **load** powers instead constrain line-to-line sub-elements.
  Delta converter filter/internal winding maps retain their winding interpretation.
- Transformer `s_rating` is a power-base field, not an extra thermal operating
  constraint. Explicit winding current ratings retain their schema meaning.

A bound report is an audit of this static AC model, not a claim that a dataset
contains realistic engineering capability limits. In particular, the reduced ENWL
DERs omit reactive boxes and nameplates. Supplying those requires engineering data.
