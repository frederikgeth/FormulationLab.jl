# Fixed reactive-power constraints and explicit excitation

The [mixed-winding comparison](ivr_nwinding_connections.md) found feasible
reference endpoints whose objective or termination status did not agree with
the native solutions. This follow-up tests one exact intervention: replace a
fixed generator Q expressed by two inequalities with one equality. **All 200
equality-treatment reference solves converge strictly and agree with all three
native formulations.** The original inequality treatment remains available and
its failures remain recorded. This is mechanism and physical-correspondence
evidence on manufactured circuits, not an isolated timing experiment.

## Mathematical intervention

For a coil voltage ``u`` and injected current ``i``, write
``q(x)=\operatorname{Im}(u\overline{i})``. A fixed reactive dispatch can be encoded
as

```math
q(x)-q_0\leq0,\qquad q_0-q(x)\leq0,
```

or as the single equality ``q(x)=q_0``. Their feasible sets are identical. The
inequality representation has two opposite active gradients. No direction can
strictly decrease both inequalities, so it fails the inequality part of the
Mangasarian–Fromovitz constraint qualification at every feasible point. If the
two nonnegative multipliers are ``\lambda_+`` and ``\lambda_-``, their contribution
to stationarity is

```math
(\lambda_+-\lambda_-)\nabla q(x).
```

Adding the same nonnegative number to both multipliers leaves this contribution
unchanged. Thus their individual magnitudes need not be identifiable. An equality
removes this particular redundant pair; it does not prove that all remaining
constraints satisfy a constraint qualification or that a local solution is global.

The inspected BMOPFTools revision emits these two generator-Q inequalities.
Native FormulationLab has explicit generator power coordinates with coincident
variable bounds, handled by Ipopt's fixed-variable treatment. Its other dispatch
families already emit an equality when their declared lower and upper powers
coincide. No native production equation or default is changed by this study.

The optional `ivr_fixed_q_hook.jl` acts on a privately built reference model. It
requires identical constraint functions and exactly equal bound values, removes
both inequalities, and registers a new equality with its own semantic key.
It refuses parameter-bound replacements. Removing obsolete keys uses the
reference context dictionary, so this is version-pinned diagnostic infrastructure,
not a general extension API for mutable models. Tests cover zero and nonzero
fixed Q, unchanged proper intervals, valid remaining references and idempotence.
There is no approximate-bound collapse and no reinterpretation of inequality
duals as equality duals. The external BMOPFTools checkout is unchanged.

## Design and outcomes

The zero-excitation panel repeats the preceding 40 cases: YYY/YDY/DYY with both
delta orientations, both flow directions, absent/active winding-2 power limits
and 1/100 kVA assembly bases. Three native lifting choices supply 120 native
solutions. Each reference case crosses two representations with two stopping
policies, giving 160 reference solves.

Baseline settings remain `tol=constr_viol_tol=1e-10`, `acceptable_iter=0`,
`bound_relax_factor=0`, `max_iter=500` and gradient-based NLP scaling. The absolute
panel additionally sets `dual_inf_tol=compl_inf_tol=1e-10`. Both packages use
per-unit coordinates. Objective agreement remains `atol=1e-7, rtol=1e-6`;
coil-current agreement remains `atol=2e-5` A and `rtol=1e-6`.

| Physical panel | Q representation | Stopping | Strict reference solves | Fully admitted reference cases |
|:--|:--|:--|--:|--:|
| Zero excitation | Opposing inequalities | Baseline | 40/40 | 38/40 |
| Zero excitation | Opposing inequalities | Absolute | 19/40 | 19/40 |
| Zero excitation | Equality | Baseline | 40/40 | 40/40 |
| Zero excitation | Equality | Absolute | 40/40 | 40/40 |
| Explicit excitation | Opposing inequalities | Baseline | 59/60 | 55/60 |
| Explicit excitation | Opposing inequalities | Absolute | 32/60 | 32/60 |
| Explicit excitation | Equality | Baseline | 60/60 | 60/60 |
| Explicit excitation | Equality | Absolute | 60/60 | 60/60 |

Each admitted reference case must agree with **all three** native formulations
and pass strict status, physical and full/candidate model-membership gates.
These counts are reference cases, unlike the preceding study's counts of
individual reference/native comparisons. The zero-excitation control reproduces
the previous statuses and discrepancies. Its largest fixed-Q multiplier is
approximately ``2.67\times10^{15}``; the equality treatment's largest is
``2.29\times10^{-8}``. These are model-coordinate multipliers at the tested bases,
not SI sensitivity prices. The largest zero-excitation objective gap falls from
about 0.170 to ``2.0\times10^{-11}`` currency/h across the stopping panels.

This controlled change strongly supports the redundant fixed-Q inequalities as
the mechanism behind these failures. It does not establish that all poor
stationarity originates in this representation. Tighter absolute tolerances
remain a separate treatment, not a universal remedy. No solver-time ranking is
inferred from these runs, which may overlap other correctness jobs.

## Explicit excitation and recovery

The second panel retains finite leakage, unequal nominal turns and the active
300 VA scalar winding-2 cap (100 VA per coil). It crosses the five connection
configurations, two directions, two bases and three separate excitation
locations: **60 physical/base cases**, 180 native and 240 reference solves.
For winding nominal coil voltage ``V_k``, the declared per-coil admittance is

```math
y_k=\frac{2-\mathrm{i}3}{V_k^2}\ \mathrm{S}.
```

Each branch therefore consumes 2 W and 3 var at nominal voltage. Input uses
`no_load_shunt = Dict("winding" => k, "g" => 2/V_k^2, "b" => -3/V_k^2)`.
BMOPFTools normalization materializes this declaration as an ordinary shunt at
the chosen winding terminals. Native FormulationLab stamps the same physical
branch within the transformer. Neither implementation refers the branch across
leakage. The ambiguous legacy `g_no_load`/`b_no_load` fields are absent, and their
existing differing conventions remain unchanged.

Let ``D_k`` be the declared winding incidence, ``u_k=D_kv_k`` the coil voltage,
and ``j_k`` the bare transformer coil current. The terminal current is

```math
i_k=D_k^{\mathsf T}(j_k+y_ku_k)
```

on the exciting winding and ``D_k^{\mathsf T}j_k`` elsewhere. Ampere-turn and
leakage equations retain ``j_k``. Winding limits retain the bare coil power
``u_k\overline{j_k}``; including excitation in the limited coil current would
change the declared model. Native output separately recovers coil and terminal
currents and powers. Legacy coil records plus input admittance and exported bus
phasors suffice for independent terminal-current reconstruction. The reference
also reports its materialized shunt separately; an audit must count it only once.

All 180 native solves pass physical and model checks. The new native suite has
**4,320 assertions**, including recovery of every identifiable current channel,
cross-formulation membership, JSON round trips, unchanged input, rejection of
omitted excitation, and rejection of a separately tightened 270 VA winding cap.
The 120 equality-treatment reference solves pass every comparison. Their maximum
Q multiplier is about 3.00 in model units, illustrating that finite nonzero
multipliers are expected with a reactive excitation load.

The original excitation control retains one `ALMOST_LOCALLY_SOLVED` baseline
status. Under absolute settings it retains 13 `SLOW_PROGRESS`, 13
`ALMOST_LOCALLY_SOLVED` and two `OTHER_ERROR` statuses. One `OTHER_ERROR` endpoint
also fails the SI physical audit even though its scaled full-model membership
test passes. Independent export reconstruction finds fixed-Q error about
``7.99\times10^{-4}`` var and KCL error ``1.41\times10^{-5}`` A there. This is a
concrete reason to keep physical-unit and model-coordinate gates separate.

## Independent audit and reproduction

The Python audit reconstructs 400 reference and 300 native exports, including
excluded reference endpoints. It checks 6,020 ungrounded KCL balances, 1,680
coil-cap observations, 1,260 excitation-coil contributions, coupled leakage,
ampere-turn balance, source voltages, powers and cost. All admitted reference
and all native exports pass; the two stricter audit violations on the excluded
endpoint above remain recorded. All 300 native exports also round-trip through
BMOPFTools' reader. Its NaN/Inf compatibility convention is retained by the
standard package writer; `nonfinite=:null` is the separate strict-JSON option.

```sh
julia --project=test test/ivr_nwinding_excitation_tests.jl
julia --project=test/integration test/integration/ivr_fixed_q_hook_tests.jl
julia --project=test/integration test/integration/ivr_nwinding_equalities_reference.jl /tmp/q-equality/report.json
julia --project=test/integration test/integration/ivr_nwinding_equalities_reference.jl /tmp/q-excitation/report.json --excitation
```

Keep the two reports in different directories. Inspect `accepted`, `status`,
physical checks and each native comparison; successful process completion is
not an all-rows-passed claim. The dependency remains BMOPFTools revision
`a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`. Inputs, source hashes, outputs,
initial writer/audit failures and their corrections are retained outside Git in
`NWINDING_EQUALITIES_20261006`.

Next steps are a frozen, diverse, isolated Ipopt timing panel and a broader
inventory of coincident nonlinear bounds. Non-unit reference tap fields,
four-winding non-star live leakage, general multiwinding-current elimination
and complex-proportional sharing remain open. All existing transformation
options and the unmodified reference controls remain available.
