# Architecture

The dependency direction is BMOPF JSON → PowerIO → FormulationLab → optimizer.
FormulationLab never imports PowerOptLab or BMOPFTools. JuMP is infrastructure, not the electrical data model.

The [formulation guide](formulations.md) defines the mathematical layers; the
[notation chapter](notation.md) defines symbols, units and ordering. This page
describes how those layers are separated in software.

`LinDist3Flow`, `IVRSDP`, `IVRSOC`, experimental `IVRNLP`, `LinIVR` and
`BranchFlowSDP` select mathematical formulations. `build_opf` and
`solve_opf` separately accept optimizer factories. `formulation_kind` distinguishes
an exact model, approximation or relaxation; LP/SOCP/SDP cone types alone do not do so.

The initial migration retains the proven LinDist3Flow compiler's dictionaries
and named variable/constraint maps. This is an intentionally bounded migration,
not the final shared component representation. Its scaling is now numerical code
rather than a side effect of initializing another package's optimization model.

`io/bmopf.jl` is the single PowerIO adapter. It currently reads source-preserving
BMOPF emission, preserving fields which typed calculation interfaces may omit.
Parser diagnostics and input digest remain available on `BMOPFInput`. It does
not call PowerIO's formulation-specific matrix builders. Raw dictionaries remain
useful for tests and construction, without a claim of schema validity.

Exact IVR, SDP/SOC and LinIVR share a solver-independent current/voltage circuit assembler
in `formulations/ivr_electrical.jl`, independently from the L3F approximations.
Exact IVR adds quadratic power products and updateable generator variables;
LinIVR adds a sparse passive-reference solve and affine device-power products;
SDP/SOC add moment representations. Shared matrix decoding and connection-incidence
helpers have no solver state. A dense nullspace implementation is a reference for small cases;
it is not intended as the scalable production representation.

At the JuMP emission boundary, exact IVR and LinIVR accumulate each sparse
linear row into one fresh complex affine expression. Input circuit rows and
coordinate expressions remain unchanged, including when several rows share a
coordinate object. This avoids allocating a scaled temporary for every term;
it changes neither physical coordinates nor operating expressions. Numerical
reference-state and supplied-point evaluation use the separate scalar path.
The optimization is local to one expression, not a cross-build cache.

The electrical assembler computes neutral roles from its input and passes that
index to fixed-transformer, multiwinding and capacitor stamping. These consumers
read the same index instead of rescanning every bus for each winding or bank.
Standalone stamping/plan callers discover roles locally when needed. The index
is never shared across separate assemblies; a fresh build reassesses changed
terminal conventions and invalid declarations. This reuses classification work,
not electrical coefficients or solver state.

Line passivity classification accepts an exactly zero scaled impedance or
admittance matrix without computing its eigenvalues. Nonzero matrices retain
the existing Hermitian-part eigenvalue test, including its zero threshold.
This is particularly useful for absent line charging: both line-end shunt
matrices are zero. No tolerance-based deletion, linecode-level passivity cache
or change to the SOC nonnegative-loss constraint is introduced.

Exact IVR retains the complex power polynomial for every device observation,
including line ends, switches, capacitor banks and transformer terminals/coils.
It materializes separate real/reactive expressions only for loads, generators,
sources and inverter ports/internal channels, where the device loop uses them
in equations, operating bounds or objective terms. Other physical limits still
use their recorded voltage/current channels. Reported powers and their
coefficients are unchanged; this only avoids unused expression copies.

Exact IVR can additionally compose local linear substitutions with its
conductor-coordinate maps. The shared assembler records defining load-current
and line-KVL rows; `compilation/ivr_elimination.jl` selects unit pivots and builds
new projection/reconstruction maps. The physical assembly and observation rows
remain intact. Only defining equalities are omitted from the NLP, and every
operating expression uses the reconstructed state. The supplied-point auditor
therefore continues to bind original physical currents and voltages before
checking the coordinate mapping. These opt-in passes do not invoke network
preparation, discard bus bounds or change equipment data.

Sparse/chordal SDP representations, fixed SOC relaxations, LNCs, shared network
reduction, and original-network reconstruction are implemented. Formulation,
reduction, strengthening, numerical settings and recovery remain separate layers.
The [formulation decision record](formulation_choices.md) identifies retained
configurations, measured limitations and next experiments. Published origins
are collected separately in the [literature map](literature.md).

The next conic performance work targets Clarabel solve time. Experimental
`IVRNLP` adds exact static equations and reusable load, generator-bound and price updates,
using affine source prescriptions in the shared assembler. Optional conductor
specialization certifies complete radial sections or pendant regions behind
retained boundaries, keeping reference-conductor voltages. Transformations
through mixed junctions and an optional ExaModels backend remain future work. Physical residual
evaluation exists, while AC-feasible recovery from relaxations is not guaranteed. DC and
time-series semantics remain separately scoped. Geometry compilation belongs
upstream of the electrical coefficient boundary.

The SDP/SOC static AC extension covers general multiwinding transformers, voltage
sequence limits, static IBRs, and explicit load envelopes. Exact IVR supports
its own static applicability domain, including exact current/ZIP/exponential
laws on certified coil-voltage domains rather than load envelopes. The pinned field
inventory records scope exceptions; control laws and adjustable taps remain out.

The branch-flow formulation uses bus voltage moments, classic current/power
blocks for pi-model lines, and component-local overlap blocks for connection
currents, switches and transformers. Complete lifted ``UI^H`` matrices meet at
matrix KCL. Radial single-source cases retain the light local structure. Meshes,
multiple sources, general multiwinding hyperedges and cross-bus LNCs additionally
use a voltage-closure Gram whose bus and adjacent-edge submatrices overlap the
local blocks. This supplies cycle and source-angle consistency without replacing
the branch-flow current and power variables by the IVRSDP compiler.

Cuts must record validity assumptions and safe bounds. Equivalent solver encodings
must be distinguished from changes in relaxation strength. Benchmark reports must
separate conic primal–dual gap from AC-OPF gap. No profile may silently replace
an electrical component or discard a limit.
