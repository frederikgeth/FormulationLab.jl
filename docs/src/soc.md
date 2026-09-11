# Fixed SOC relaxation

`IVRSOC` shares the electrical equations, fixed taps, physical component maps,
load envelopes and optional voltage LNCs of `IVRSDP`. It replaces every complex
Hermitian PSD block, before real embedding, with its diagonal nonnegativity and
principal two-dimensional SOC constraints:

```math
H_{ii}\geq0,\qquad |H_{ij}|^2\leq H_{ii}H_{jj}.
```

Blocks of order at most two are represented exactly. Larger blocks can remain
indefinite. Power cones for voltage-dependent loads are retained. No profile
introduces a PSD cone. The coordinates and clique cover affect strength.

## Usage

```julia
using FormulationLab, Clarabel
f = IVRSOC(s_base=10_000.0, objective=:source_import,
           strengthening=:linear)
build = build_opf(network, f)
report = bound_report(build)
result = solve_soc_opf(build; solver_options=(verbose=false,))

# Fixed complex projections from Geth and Foster's three-cycle construction:
f = IVRSOC(s_base=10_000.0, strengthening=:kim, max_triplets=16,
           directions=(1.0+0im, 1.0im), lnc=:lines)
```

Construction uses only input data, affine maps and the existing clique cover.
`solve_soc_opf` optimizes once. The former `PSDSeparationOptions` API has been
removed. Spectral calculations after solving are diagnostics only.

| Profile | Physical voltage–current SOCs | Constant-power secants | Fixed three-map projections |
|:--|:--|:--|:--|
| `:none` | Yes | No | No |
| `:linear` (default) | Yes | Yes | No |
| `:kim` | Yes | Yes | Budgeted |

`physical_projections=false` disables the physical voltage–current SOCs for
experiments. Use `strengthening=:none` as well to isolate coordinate-wise minors.
LNCs are independently selected with `lnc=:lines` or explicit `VoltageLNC`s.

## Physical projections and linear cuts

For physical voltage and current maps, including nullspace transformation,

```math
w=\mathbb E[|V|^2],\quad \ell=\mathbb E[|I|^2],\quad
s=\mathbb E[V\overline I],\qquad |s|^2\leq w\ell.
```

These SOCs retain consequences of PSD lost by coordinate-wise minors. They
include delta coils and explicit neutral currents. Auxiliary variables expose
scaled cone coordinates to Clarabel: each diagonal is scaled separately and
the cross term uses their geometric mean. Passive lines also receive
nonnegative total active-loss constraints.

For a constant-power load, let `c=|S|²` in per unit and let valid squared-voltage
bounds be `0<a≤w≤b<∞`. Every original AC state satisfies `ell=c/w`. Convexity of
`c/w` gives the **upper chord**, a valid linear inequality:

```math
\ell + \frac{c}{ab}w \leq \frac{c}{a}+\frac{c}{b}.
```

Together with the physical SOC this bounds current on both sides. It improves
on the constant cap `ell≤c/a`. It also applies to delta load sub-elements, using
their line-to-line voltages. Missing or zero lower voltage bounds cause the
cut to be skipped. These are valid cuts for the original nonconvex problem;
they need not be consequences of an unstrengthened SDP relaxation.

## Fixed complex three-map constraints

For a Hermitian physical moment triple `G`, choose a pivot `p`, other indices
`j,k`, and a fixed complex coefficient `eta`. PSD implies

```math
\begin{aligned}
\alpha &= G_{pp},\\
t &= G_{jj}+|\eta|^2G_{kk}+2\Re(\eta G_{jk}),\\
|G_{pj}+\eta G_{pk}|^2 &\leq \alpha t,\qquad \alpha,t\geq0.
\end{aligned}
```

This is a rotated SOC, with a linear nonnegative right factor. It is the
fixed-vector Schur-complement projection explored in
[Geth and Foster (2021)](https://arxiv.org/abs/2104.06695). Keeping the complex
cross terms is essential. The default directions `1` and `i`, over all three
pivots, give six projections per selected triple plus its three principal
pair SOCs. They are outer constraints, not diagonal-dominance restrictions.

The implementation enumerates consecutive three-map voltage and current
groups of devices, in deterministic rounds across component IDs, with voltage
groups before current groups. It deduplicates proportional maps, skips wholly
fixed source groups, and only accepts sparse triples covered by an existing
clique. It does not enlarge the cover. `max_triplets` bounds added cone count;
selection stops after that many accepted triples. The selected groups and
counts are in `build.electrical.numerical_diagnostics[:fixed_strengthening]`.
This is a cheap structural policy, not a claim that these are optimal directions.
Finite fixed projections do not generally reproduce a three-dimensional PSD
cone; see [Fawzi (2016)](https://arxiv.org/abs/1610.04901).

## Bounds and result interpretation

`bound_report(build)` exposes magnitude intervals in per unit, their last
bound-tightening provenance, map labels, and missing DER capability fields.
The common preprocessing propagates triangle and reverse-triangle inequalities
through complex electrical equations, KCL, connection maps and fixed taps.
Declared bounds and exact source phasors seed it. Power boxes and nameplates
can imply current limits when the same physical voltage has a positive lower
bound. `bound_sweeps` (default 8) bounds the preprocessing work; it performs no
optimization. Propagated domains feed current cuts, load envelopes, and LNCs.
No nominal phase-angle sector or absent DER rating is invented.

`SOCResult` returns objective, solver bound, physical powers, moment blocks,
and a normalized negative-eigenvalue residual. It does not PSD-complete an
indefinite moment or claim recovered AC feasibility. Successful results have
`stop_reason=:one_shot`, one history record and zero iterative cuts. Only fully
optimal, feasible solver outcomes publish an objective; other statuses return
NaN. Solver bounds and residuals are numerical diagnostics, not rigorous
optimality certificates. Inspect physical violations as well as solver status.

The default Clarabel SOC settings use static regularization `1e-7` and up to
30 iterative-refinement steps, with absolute duality-gap tolerance `1e-7` in
the normalized objective. Feasibility and relative-gap tolerances retain
Clarabel's `1e-8` defaults. The slightly larger absolute-gap tolerance stops
before late numerical stagnation observed on the 87-bus feeder; it is not a
relaxation of physical feasibility checks. Translate the reported primal–dual
gap through `objective_scale` when interpreting it in watts. An explicit
optimizer overrides this profile.

## Reproducible measurements

Run the fixed SDP/physical/linear/Kim comparison with:

```sh
julia --project=test examples/benchmark_soc_enwl.jl /path/to/ENWLbenchmark/reduced output.json
```

The script removes source-bus generators in memory, retains the finite source
neutral shunt, selects per-phase power bases from load/DER scales, warms up all
profiles, and records times, objectives, solver bounds, residuals and input
hashes. Historical iterative experiments remain in
`examples/results/enwl_soc_clarabel_2026-09-11.json`; they describe the removed
API and are not measurements of the current fixed profiles.

### Fixed-profile results (2026-09-11)

Julia 1.12.6, Clarabel 0.11.1, one BLAS thread; one warmed measurement per
variant. Times are indicative, not statistical averages. The default `:linear`
profile returned `OPTIMAL` on every reduced ENWL feeder:

| Buses | SOC import (W) | Cached NLP minus SOC (W) | SOC solve (s) | SDP solve (s) | SOC build (s) |
|---:|---:|---:|---:|---:|---:|
| 5 | -1705.610441 | -0.000005 | 0.006 | 0.005 | 0.019 |
| 8 | 1221.895773 | 0.002223 | 0.012 | 0.008 | 0.030 |
| 23 | -406.992772 | 0.295078 | 13.476 | 5.769 | 0.633 |
| 87 | -2667.501689 | 3.233983 | 0.524 | 1.979 | 13.776 |

The cached NLP values come from the preceding BMOPFTools/Ipopt source-import
comparison, with the same input hashes and source-generator removal. They were
not recomputed for this change. Differences are numerical objective comparisons,
not certified AC optimality gaps; the tiny negative 5-bus difference is rounding.
The reference artifact preserves the checks' unassessed dimensions.

The default's maximum scaled constraint violations were `2.69e-10`, `7.07e-9`,
`3.86e-10`, and `5.03e-8`. Its solver primal–dual gaps were approximately
`0.000063`, `0.000079`, `0.000802`, and `0.003412 W`, respectively. These are
small compared with the 23/87-bus relaxation gaps, but the lifted points are not
certified AC feasible.

| Optional profile | 5 buses | 8 buses | 23 buses | 87 buses |
|:--|:--|:--|:--|:--|
| Kim: import (W), solve (s) | -1705.610442; 0.037 | 1221.898047; 0.060 | `ALMOST_OPTIMAL`; 27.024 | -2667.280206; 0.598 |
| Linear + LNC: import (W), solve (s) | -1705.610436; 0.006 | 1221.895773; 0.023 | -406.992782; 18.396 | `ALMOST_OPTIMAL`; 0.599 |

Kim used 16 triples (144 additional SOCs) on each feeder. It improves the 87-bus
NLP objective difference to `3.012500 W`, but its 23-bus failure argues against
making it universal. LNCs added 12, 21, 66 and 258 domains and did not materially
improve these objectives; they remain opt-in. Failed outcomes publish no
objective. In this build, even physical SOC without secants returned
`ALMOST_OPTIMAL` on 87 buses, illustrating sensitivity to redundant constraints.

Retain the automatic electrical layout. Exploratory forced chordal covers with
merge sizes 8 or 16 returned `NUMERICAL_ERROR` on the 23-bus case. The current SOC
still loses to direct SDP there. On 87 buses its faster solve is overshadowed by
shared model construction, which remains about 14 seconds. No structure cache
is introduced in this change.

All five fixed variants also returned `OPTIMAL` on six fixed-transformer fixtures:
single-phase, center-tap, delta–wye, wye–delta, single-phase autotransformer, and
open-delta regulator, at tap 1.03 with an impedance load. Objectives agree with
the matching SDP within `1e-8 W`. These small analytical fixtures test consistency;
they do not establish gap closure for difficult transformer-rich OPF instances.

Raw records are in `examples/results/enwl_fixed_soc_clarabel_2026-09-11.json`,
`examples/results/enwl_cached_nlp_reference_2026-09-11.json`, and
`examples/results/transformers_fixed_soc_clarabel_2026-09-11.json`.
The ENWL script attaches the cached reference only when the input hash matches.
For the transformer fixtures, run
`julia --project=test examples/benchmark_soc_transformers.jl output.json`.

## Original-network output

`prepare_network` applies the shared BMOPFTools-compatible topology reduction.
`reconstruct_solution` restores original buses and lines from the SOC voltage
correlation-tree estimate, while retaining the raw relaxed solution separately.
See [Network reduction and original-network states](@ref) for the recovery
equations, approximation diagnostics, and limitations.
