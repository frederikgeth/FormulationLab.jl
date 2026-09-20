# Architecture

The dependency direction is BMOPF JSON → PowerIO → FormulationLab → optimizer.
FormulationLab never imports PowerOptLab or BMOPFTools. JuMP is infrastructure, not the electrical data model.

`LinDist3Flow`, `IVRSDP`, `IVRSOC` and experimental `BranchFlowSDP` select mathematical formulations. `build_opf` and
`solve_opf` separately accept optimizer factories. `formulation_kind` distinguishes
an approximation from a relaxation; LP/SOCP/SDP cone types alone do not do so.

The initial migration retains the proven LinDist3Flow compiler's dictionaries
and named variable/constraint maps. This is an intentionally bounded migration,
not the final shared component representation. Its scaling is now numerical code
rather than a side effect of initializing another package's optimization model.

`io/bmopf.jl` is the single PowerIO adapter. It currently reads source-preserving
BMOPF emission, preserving fields which typed calculation interfaces may omit.
Parser diagnostics and input digest remain available on `BMOPFInput`. It does
not call PowerIO's formulation-specific matrix builders. Raw dictionaries remain
useful for tests and construction, without a claim of schema validity.

The first SDP assembles linear current/voltage laws independently from the L3F
approximations. Shared matrix decoding and connection-incidence helpers have no
solver state. A dense nullspace implementation is a reference for small cases;
it is not intended as the scalable production representation.

Sparse/chordal SDP representations, fixed SOC relaxations, LNCs, shared network
reduction, and original-network reconstruction are implemented. Formulation,
reduction, strengthening, numerical settings and recovery remain separate layers.
The [formulation decision record](formulation_choices.md) identifies the retained
configurations, scientific lineage, measured limitations and next experiments.

The next performance work targets Clarabel solve time. An exact nonlinear
formulation and optional ExaModels backend remain future work; physical residual
evaluation already exists, while AC-feasible recovery is not guaranteed. DC and
time-series semantics remain separately scoped. Geometry compilation belongs
upstream of the electrical coefficient boundary.

The static AC extension now covers general multiwinding transformers, voltage
sequence limits, static IBRs, and explicit load envelopes. The pinned field
inventory records scope exceptions; control laws and adjustable taps remain out.

The branch-flow prototype uses bus voltage moments, classic current/power blocks
for radial series lines, and component-local overlap blocks for connection
currents and fixed transformers. Complete lifted ``v i^H`` matrices meet at
matrix KCL. Its component contract remains independent of IVRSDP's broader
static-AC compiler. General multiwinding devices must be treated as hyperedges
rather than ordinary lines.

Cuts must record validity assumptions and safe bounds. Equivalent solver encodings
must be distinguished from changes in relaxation strength. Benchmark reports must
separate conic primal–dual gap from AC-OPF gap. No profile may silently replace
an electrical component or discard a limit.
