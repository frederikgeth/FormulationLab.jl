# Supplied operating-bound declarations

The [emitted-constraint inventory](ivr_constraint_inventory.md) checks that
every solver constraint has recorded provenance. A complementary question is
whether every supplied operating-bound channel has corresponding provenance.
If both a bound's row and its provenance were lost, counting the remaining
emitted constraints could still report completeness.

`examples/ivr_declared_bound_inventory.jl` starts from the normalized
`IVRNLPBuild.network`, independently enumerates the supported declarations and
their physical consumers, and reconciles them with the live inventory. It does
not solve or change the model. Its diagnostic JSON is separate from the
[canonical physical results](results.md).

## Reconciliation criterion

Each expected channel has an identity comprising its category, normalized input
path, source-array position (or scalar), consuming component, side or winding,
and physical channel. A single linecode rating can have several consumers; a
scalar winding cap can expand to several coil caps. The enumeration uses input
terminal maps and connection conventions, not the number of emitted rows or
the assembler's equipment-limit list.

Let ``D`` be these expected identities and ``P`` the identities in recorded
bound provenance. Reconciliation requires

```math
D=P,
```

with agreement on each channel's declared value, interpretation divisor,
resolved SI limit and lower/upper/equality relation. Duplicate provenance is
rejected. The report separately identifies missing channels, unexpected
provenance and mismatched values. Supplied fixed-tap intervals must also contain
their declared fixed setting. This last check concerns construction data; it
does not introduce a tap decision or an NLP inequality.

`complete_declared_bound_coverage` is true only when these checks pass. It is
independent of `complete_emitted_coverage`: an added user constraint can leave
all supplied bounds accounted for while making emitted coverage incomplete.
Conversely, deleting both a bound's row and its provenance can leave emitted
coverage complete while declaration coverage fails.

## Classified declarations

| Input family | Accounted-for operating declarations | Important distinction |
|:---|:---|:---|
| Bus | Phase-ground, phase-neutral, phase-pair, neutral and sequence magnitude bounds | Scalar expansion and terminal-array positions follow the accepted exact-IVR contract. |
| Line and linecode | `i_max`, `s_max` at both ends | From-side channel indexing applies at both ends. A line override supersedes that linecode field for that consumer. |
| Fixed switch | `i_max`, `s_max` at both ends | An open-switch or grounded-voltage observation may make a bound identically satisfied; its declaration still needs provenance. |
| Generator and source | P/Q boxes, apparent-power and current caps | Source phase/full-terminal arrays and generator coil/return-current conventions remain distinct. |
| IBR | PCC P/Q/S/I, `p_avail`, internal `p_dc_min/max`, `v_ref_internal` | DC-link and internal-voltage declarations require the corresponding static capability contract. |
| Ordinary transformer and regulator | Side current caps, policy-dependent `s_rating`, fixed tap intervals | Delta coil, terminal and rated-port channel conventions are retained. |
| General multiwinding transformer | Winding `i_max`, `s_max`, fixed tap intervals | Scalar winding-total caps are divided by coil count only under the explicit BMOPFTools policy; vectors remain per-coil. |

The `inactive` records distinguish `overridden`, `unused_linecode`,
`ignored_nameplate` and `base_metadata`. They retain the raw declaration and,
for an override, the affected consumer. A linecode can be active for one line
and overridden for another. Multiwinding `s_rating` remains metadata; ordinary
transformer `s_rating` is an operating cap only under its explicit policy.
Nominal load powers, capacitor ratings and positive-voltage domains are not
silently relabelled as additional operating caps.

Scalar acceptance is field-specific. Source apparent-power caps support scalar
broadcasting; multi-coil generator and line ratings and source current ratings
require explicit arrays. A single-phase generator can combine a scalar
apparent-power cap with a one-entry coil-current array. The regression suite
checks both accepted and rejected forms; the inventory does not broaden the
builder's input contract.

The helper refuses unclassified bound-shaped fields: names ending in `_min` or
`_max`, and the explicitly recognized availability, reference-voltage and rating
fields. Descriptive `meta`, `extras`, `_meta`, wire data and geometry are outside
this scan. This is a guard against an unclassified declaration, not a general
schema validator or a way to discover arbitrary future field semantics.

## Example: inheritance and a missing bound

No optimizer is needed:

```@example declared_bounds
using FormulationLab, JuMP, JSON3
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_compiler_cases.jl"))
include(joinpath(dirname(pathof(FormulationLab)), "..", "examples", "ivr_declared_bound_inventory.jl"))
const DBI = IVRDeclaredBoundInventory
net = ivr_compiler_case(conductors=2, segments=2)
net["line"]["l1"]["i_max"] = [100.,100.]
net["linecode"]["unused"] = deepcopy(net["linecode"]["wire"])
build = build_opf(net, IVRNLP())
report = DBI.report(build)
@assert report.complete_declared_bound_coverage && report.complete_emitted_coverage
@assert !report.complete_input_coverage
@assert Set(q.status for q in report.inactive) == Set((:overridden,:unused_linecode))
@assert JSON3.read(JSON3.write(report)).complete_declared_bound_coverage
(matched_channels=length(report.matched), inactive_declarations=length(report.inactive))
```

The next block deliberately damages a fresh model to demonstrate the difference
between the two inventories. Direct model edits are not a supported update API.

```@example declared_bounds
damaged = build_opf(net, IVRNLP())
rows = damaged.model.ext[:ivr_bus_limit_rows]
entry = popat!(rows, findfirst(q -> q.b=="b1" && q.key=="vpn_max", rows))
foreach(ref -> delete(damaged.model,ref), entry.constraints)
report = DBI.report(damaged)
@assert report.complete_emitted_coverage
@assert !report.complete_declared_bound_coverage
@assert length(report.missing)==1
only(report.missing).source_path
```

Use `catalog(build)` for live constraint references and `report(build)` for a
serializable snapshot. Reports enumerate channels in a deterministic order and
recompute generator-bound references after supported updates. Source paths refer
to normalized construction data. Ordinary-transformer tap aliases are copied
to internal keys while retaining both spellings; the inventory checks their
agreement and accounts for both retained intervals. These paths are not JSON
pointers into an arbitrary original file spelling.

## Evidence and limitations

The regression suite exercises 2/3/4-wire inputs, all bus-voltage bound families,
source and generator boxes, static IBR budgets, switch ends, all six ordinary
transformer/regulator subtypes, multiwinding scalar/vector caps, both nameplate
policies, fixed taps, lifting, conductor specialization and power bases. Negative
tests remove rows and provenance, remove zero-bound tautologies, duplicate or
corrupt records, change declared values, and add an unknown bound field. Shared
and coincident equalities retain each original declaration. JSON checks cover
both passing and incomplete reports.

This establishes a narrower claim than mathematical equivalence. The inventory
does not independently re-derive the electrical observation attached to every
constraint, validate arbitrary direct JuMP edits, or detect every possible
unknown input meaning. Use the [equivalence arguments](ivr_theory.md),
[per-bound negative physical witnesses](ivr_nlp.md#Operating-bound-coverage),
and [independent SI checks](ivr_validation.md) with it. Direct mutation of
`build.network` remains unsupported; fixed-setting checks are against the
current normalized data, not a reassembly of transformer circuit equations.

**`complete_input_coverage` remains false.** A passing declaration inventory must
not be promoted into full input-schema coverage, a feasibility certificate,
a global-optimality claim or a performance result. No numerical formulation,
physical result field or solver default is changed by this diagnostic.
