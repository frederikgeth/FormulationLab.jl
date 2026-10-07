# Certified zero-power load currents

The [external observation study](ivr_external_observations.md) found many retained
load channels with exactly zero nominal P and Q. The optional
`IVRNLP(zero_load_elimination=true)` removes their coil-current coordinates only
when a nonzero voltage certificate makes the substitution exact. The default is
`false`; all earlier formulation and scaling options remain available.

## Equivalence domain

For one non-impedance load coil, write its physical equations as

```math
U\overline I=P_n f_P(|U|^2/V_n^2)
             +\mathrm{j}Q_n f_Q(|U|^2/V_n^2).
```

Constant power has both factors equal to one. Constant current, ZIP and
exponential factors use their declared, validated parameters and positive
voltage domain. If ``P_n=Q_n=0`` **exactly**, and ``|U|\geq\underline U>0``, then
``I=0``. Conversely, substituting ``I=0`` satisfies both original power equations
for every voltage in that domain. No tolerance classifies a small nonzero demand
as zero.

The compiler accepts a positive lower bound on the **same physical coil voltage
row**, or an explicitly fixed nonzero source phasor on that row. It matches signed
voltage differences algebraically. Nominal voltages, previously solved voltages
and bounds on different voltage differences do not supply a certificate. A
phase-to-phase lower bound alone does not establish a phase-to-neutral lower
bound. Missing or inconsistent certificates leave the current explicit.

This condition is essential: at ``U=0``, the equation ``U\overline I=0`` permits
nonzero current. A regression witness fixes one source phase to zero and another
to 230 V, with a 1 A zero-power load on the zero-voltage phase. Both the original
and opt-in formulations retain and accept that physical point.

The substitution follows conductor and passive/device elimination, before
coordinate scaling. It requires a retained singleton current coordinate with
coefficient ±1. Deleting that coordinate and substituting zero through every
reconstruction row gives a bijection between the original and reduced feasible
sets on the certified domain. Every electrical equation, operating limit and
power objective continues to use the original physical observations through
that reconstruction. This is an exact reduction, not a relaxation.

The two zero-power law equalities are omitted. Voltage-law power auxiliaries and
the voltage-magnitude auxiliary dedicated to that eliminated channel are also
omitted; their physical values remain uniquely recoverable. Other channels in
the same load remain explicit. Impedance loads retain their existing linear-law
elimination path. The option does not eliminate generator or IBR currents.

## Recovery, provenance and reuse

The original network records, voltage/current rows, bounds and result fields
are retained. Removed load currents and powers export as exact zeros in SI units;
their terminal-current and power observations remain available. A supplied
physical point with a nonzero eliminated current is rejected by the reconstruction
check; it is never silently projected to zero.

`numerical_diagnostics[:zero_load_elimination_report]` lists selected channels,
their certified voltage interval and source, retained zero channels and their
reason, and the number of eliminated complex coordinates. Enabled result exports
include this report under `_formulationlab`; canonical physical tables keep the
same fields. An unbounded upper voltage is represented by `nothing`/JSON `null`.

The [constraint inventory](ivr_constraint_inventory.md) preserves both load-law
declarations with status `eliminated_zero_power` and no emitted references. It
checks the recorded rows, zero demand, zero reconstruction and continued voltage
certificate. Nonlinear residual traces evaluate their original physical laws
with native residual zero. This provenance does not replace an input-schema
coverage proof or independent physical audit.

`update_ivr_loads!` can update retained constant-power channels and can keep an
eliminated channel at zero. Attempting to set either P or Q of an eliminated
channel to a nonzero value throws before **any** load in that update is changed.
Rebuild for that change. A retained channel later updated to zero stays explicit;
the API does not silently change model structure.

## Small reproducible example

This example adds no solver-specific assumptions to the equivalence test:

```@example zero_load
using FormulationLab, JuMP, Ipopt
include(joinpath(@__DIR__, "..", "..", "examples", "ivr_compiler_cases.jl"))
net = ivr_compiler_case(conductors=2, segments=2)
net["load"]["d1"]["p_nom"] .= 0.0
net["load"]["d1"]["q_nom"] .= 0.0
full = build_opf(net, IVRNLP())
reduced = build_opf(net, IVRNLP(zero_load_elimination=true);
    optimizer=Ipopt.Optimizer)
@assert num_variables(full.model) - num_variables(reduced.model) == 2
result = solve_ivr_nlp_opf(reduced; solver_options=(
    print_level=0, tol=1e-10, constr_viol_tol=1e-10,
    acceptable_iter=0, bound_relax_factor=0.0))
@assert result.solve.optimal && physical_residuals(net, result).passed
point = ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)
@assert ivr_nlp_point_report(full, point).passed
@assert iszero(only(result.current_candidate[(:load, "d1")]))
reduced.numerical_diagnostics[:zero_load_elimination_report].eliminated_complex_coordinates
```

The live regression panel covers single-phase, delta and wye loads; constant
power/current, ZIP and exponential laws; two power bases; direct, power-lifted
and observation-lifted forms; and partial-channel elimination. It checks
full-model membership in both directions, physical residuals, objective agreement,
bound violations, exact exports and atomic update refusal. Positive and negative
tiny nonzero demand remain explicit.

## External preflight protocol

`examples/benchmark_ivr_zero_loads.jl` consumes the declared `INPUT.json` saved by
the external observation study. It does not add or change demand, DERs or limits.
The eight preflight arms cross zero-load elimination off/on, ordinary transformer
currents retained/eliminated and powers-only/broad observations, under quadratic
cost and exchange tracking. All units, solver settings and physical starts match
the preceding external study. Preflight timings remain ineligible.

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test \
  --startup-file=no examples/benchmark_ivr_zero_loads.jl \
  /path/to/declared-scenario/INPUT.json /path/to/new-evidence-folder
```

The isolated comparison uses the four powers-only arms, keeping both
ordinary transformer-current representations and changing only the zero-load
option within each pair. Broad observations remain in the correctness panel
and available for further measurements. A smaller model alone does not establish
a faster solve; admission and isolated Ipopt wall time are separate requirements.

All **48 external preflight solves** pass under the original strict settings,
with objective agreement across the eight arms. The reduction certifies every
zero-P/Q channel in these three scenarios: **39, 458 and 1,471 complex currents**,
respectively. Their original zero-load records are retained. The resulting real
variable reductions are **78, 937 and 3,101**; the last two also omit 21 and 159
voltage-law auxiliary variables. On the largest powers-only tracking case,
iterations rise from 32 to 33 despite the smaller model. This is why dimension
reduction alone cannot establish a speed benefit.

All 48 SI result files pass the FormulationLab and BMOPFTools readers. An
independent exported-state audit checks exact zeros on every eliminated channel,
unchanged physical leaf paths, **60,096 coil-power identities** and **1,152
transformer rated-port values/limits**. Raw scenarios, complete preflight records,
inventories, exports and scripts are retained outside Git in
`ZERO_LOAD_ELIMINATION_20261007`.

An independent inventory comparison finds the same **218, 2,171 and 7,369**
operating-limit/generator-definition declarations in every arm of the respective
feeder. All load-law declarations also remain present in the inventory; 78, 916
and 2,942 P/Q declarations change to the explicitly omitted zero-power status.
This separates removal of redundant law equations from loss of operating limits.
The stronger input-schema completeness claim remains outside this audit.

## Isolated Ipopt wall time — 7 October 2026

All **384 measured solves and 48 warmups** pass the frozen admission protocol:
physical SI residuals, own/full-model membership, reverse-anchor membership and
objective agreement. Each of two fresh-process batches uses eight four-arm
Williams sweeps per case, balancing positions and immediate within-sweep
predecessors. Confirmation reverses case and sweep order. The two-second monitor
records **264 snapshots** without observed competing Julia. This sampled check
cannot exclude other system load or shorter jobs. No failed trials or outliers
are discarded within the admitted campaign.

Confirmation medians below are milliseconds of Ipopt optimizer-call wall time.
Compilation, model construction, extraction and audits are excluded. The
electrical inputs, per-unit settings, objectives and physical starts are unchanged.

| Buses | Objective | Explicit control | Explicit zero-reduced | Eliminated control | Eliminated zero-reduced |
|---:|---|---:|---:|---:|---:|
| 17 | Cost | 6.366 | 5.061 | 6.255 | 4.924 |
| 17 | Tracking | 6.038 | 4.804 | 5.942 | 4.801 |
| 110 | Cost | 170.107 | 141.930 | 170.887 | 143.664 |
| 110 | Tracking | 198.591 | 175.027 | 187.668 | 167.114 |
| 333 | Cost | 754.568 | 670.509 | 810.519 | 669.541 |
| 333 | Tracking | 946.824 | 837.340 | 908.904 | 881.027 |

Explicit/eliminated denotes ordinary transformer currents; all arms use
powers-only lifting and the other established reductions. The zero-load option
lowers the median in **all twelve matched comparisons in both batches**. The
geometric mean reduced/control ratio is 0.855 in exploration and **0.846** in
confirmation with explicit transformer currents, and 0.848 and **0.852** with
eliminated currents. These correspond to confirmation reductions of **15.4% and
14.8%**, giving each of the six case/objective cells equal weight.

A zero-reduced arm wins all six cells in both batches. The complete current
representation winner repeats in only five cells; tiny differences between
nearby alternatives should not be treated as robust rankings. On the largest
tracking case, transformer-current elimination helps the unreduced control but
hurts the zero-reduced formulation. Thus those two reductions are not independent
runtime benefits. Keep both current representations when profiling a workload.

For these declared external scenarios, powers-only lifting with certified
zero-load elimination is the best-supported shortlist. This result does not
select a universal default, establish global optimality, or extend to changing
zero/nonzero demand patterns without rebuilding. Broad observations remain
available and physically validated; their timing with zero-load elimination
has not been measured in this campaign. Source freezes, all raw repeats,
isolation snapshots and the final admission report are archived under `TIMING`.

The separate [observation interaction study](ivr_zero_load_observations.md)
holds this reduction enabled and compares all five existing observation choices.
It also checks whether differently named choices produce distinct emitted models
before interpreting their timing differences.
