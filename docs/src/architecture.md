# Architecture

The dependency direction is BMOPF JSON → PowerIO → FormulationLab → optimizer.
FormulationLab never imports PowerOptLab or BMOPFTools. JuMP is infrastructure, not the electrical data model.

`LinDist3Flow` and `IVRSDP` select mathematical formulations. `build_opf` and
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

Next milestones, in order:

1. Audit the input boundary against pinned BMOPF schemas, including retained
   transformer/control fields. Expand field-level coverage and refusal tests.
2. Extend the fixed transformer foundation to general multiwinding units,
   phase-neutral/phase-phase/sequence limits, and broader independent oracles.
3. Add sparse/chordal representations and establish equivalence to the dense
   reference for each supported domain.
4. Add an exact nonlinear formulation plus physical residual evaluation and
   feasible-solution recovery. ExaModels becomes an optional backend here.
5. Derive named SOC relaxations and valid-cut families with explicit assumptions,
   then benchmark gap, residuals, success rate, build/solve time, and memory.
6. Expand to the proposed BMOPF IBR, DC, and time-series semantics. General load
   laws and discrete controls require separately specified relaxation policies.

Cuts must record validity assumptions and safe bounds. Equivalent solver encodings
must be distinguished from changes in relaxation strength. Benchmark reports must
separate conic primal–dual gap from AC-OPF gap. No profile may silently replace
an electrical component or discard a limit.
