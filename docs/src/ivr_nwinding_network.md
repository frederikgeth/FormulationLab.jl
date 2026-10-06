# Mixed-device multiwinding networks

This experiment extends the [four-bus timing panel](ivr_nwinding_timing.md) to
electrically coupled networks with voltage-dependent demand, inverter filters
and power objectives. It is a **manufactured scaling study**. A read-only search
of 3,136 plain JSON files, including ignored files, in the supplied
`BMOPFDraftData/output` and `benchmarks` trees found no explicit multiwinding
records. Compressed files were not searched. External-network validation of
this elimination pass therefore remains open.

## Physical construction and scope

The tracked `examples/benchmark_ivr_nwinding_network.jl` constructs 2, 8 or 24
live four-winding non-star units, giving 23, 83 or 243 buses and 15, 57 or 169
lines. Three ordinary single-phase transformers connect a balanced 2.3 kV
source to a shared 230 V bus and trunk. Each unit retains the preceding fixture's
pair leakage matrix, winding resistances, nominal ratios and winding-4 excitation.
Its secondary windings feed two line sections each. Every winding carries
current; no inactive port or ordinary-star fit is introduced.

Per-unit demand and local transformer/line impedances stay fixed. Common supply
and trunk impedances scale as ``1/N`` for ``N`` units. All line current ratings
are ``100N`` A per conductor and line apparent-power limits ``10^5N`` VA per
phase. These are declared loose scenario limits. Winding-2/4 nameplates remain
300/180 VA total, or 100/60 VA per coil under the aligned BMOPFTools policy.
They are unchanged across numerical formulations.

The connection sequence cycles YYYY/YDYY/YYYD/DYYY, with delta roll alternating
between cycles. The two-unit case contains YYYY and YDYY(+1); the larger cases
contain both delta rolls. Consequently, size and connection mix are confounded
when comparing the two-unit case with the others. All formulation comparisons
within a case use identical physical input.

Each unit has nine single-phase loads, four generators and two filtered battery
IBRs. Loads use constant-current, ZIP and fractional exponential laws; nominal
active demand totals 870 W per unit. Explicit 0.8–1.2 nominal coil-voltage bands
at winding, midpoint and endpoint buses certify positive load-law domains.
Winding-3 feeder sections include charging. Inverters retain explicit P/Q/S,
availability and DC capabilities. These new physical scenarios are not claimed
equivalent to the preceding four-bus inputs or to an external feeder.

The regression changes one unit's voltage-dependent demand and verifies a
voltage change in another unit through the shared supply. Thus the larger
network is not a collection of independent solves. The existing update API
accepts constant-power loads only: the test checks refusal without mutation,
then rebuilds the changed voltage-law case. This study does not extend that API.

## Power objectives and numerical controls

Let ``P_s,Q_s`` be aggregate grid exchange, ``\mathcal D`` the ``M=6N`` dispatch
channels, ``P_d,Q_d`` PCC dispatch powers, and ``P_d^{\mathrm{priced}}`` generator
power or IBR internal active power. All physical powers below are in W/var.
The declared quadratic cost is

```math
F_{\mathrm{cost}}=0.25\,P_s/1000
 +0.10\sum_{d\in\mathcal D}P_d^{\mathrm{priced}}/1000
 +0.5\sum_{d\in\mathcal D}P_d^2/10^6.
```

The exchange-tracking workload uses ``P_\star=0.35\sum_\ell P_\ell^{\mathrm{nom}}``:

```math
F_{\mathrm{track}}=\frac{10^{-6}}{M}
 [(P_s-P_\star)^2+Q_s^2]
 +10^{-8}\sum_{d\in\mathcal D}[(P_d-100)^2+Q_d^2].
```

These coefficients define the experiment, without asserting a market model
or a global optimum. Both objectives use `objective=:power`; source exchange,
IBR internal power and PCC power remain distinct physical channels.

Cross each size/objective with 1/100 kVA assembly bases. Four arms compare
ordinary-only versus all-transformer current elimination, each with power or
bounded-observation lifting. All use per-unit coordinates, nominal transformer
scaling, composed rows, voltage ground scaling, 500 VA power auxiliaries, signed
observation sharing and load-power lifting. The explicit multiwinding-current
control retains the existing ordinary-transformer reduction.

Per-generator power-base overrides are empty, so generator power coordinates
inherit the assembly base. The 1/100 kVA comparison therefore changes both
current coordinates and generator power columns; it does not isolate their
individual effects. The factorial follow-up below varies them separately.

Timing uses two fresh Julia processes, reversed case/schedule order in
confirmation, one excluded warm-up per arm/case and eight measured sweeps in
two Williams blocks. Positions and within-sweep immediate predecessors are
balanced. Every representation starts from the same unloaded SI circuit point.
Strict settings, acceptance gates and the optimizer-call timer follow the
[preceding protocol](ivr_nwinding_timing.md#Question-and-controlled-experiment):
Ipopt wall time alone, without compilation, construction, preceding cache
transfer, extraction or audits. All failures and outliers remain in the reports.

## Physical correspondence and recovery

All 48 preflight solves pass strict termination, own/full/reverse feasible-point
membership, objective agreement, complete shared-start encoding and independent
non-star equations. The smallest maximum coil-current magnitude over any winding
is 0.1579 A, establishing that every port is live in this panel.

All 48 physical exports pass both FormulationLab and BMOPFTools readers. An
independent Python audit reconstructs pi-line equations, ordinary and non-star
transformer equations, winding excitation, mixed load laws, inverter filter
quantities and both objectives from SI observations. It checks 19,200 ungrounded
KCL balances, 6,528 coil-power channels, 8,304 recovered winding-terminal
currents, 3,264 coil caps, 14,688 voltage bands, 29,760 line-current bounds and
1,088 IBR internal-power channels. Exported physical
structures agree across formulation, objective and base at each size.

The current allocation between an ideal voltage source and its coincident ideal
ground is not unique. That source-ground current remains explicitly unavailable;
its zero power follows from the exactly grounded voltage. It is not inferred
from an arbitrary allocation. All exactly recovered channels retain their
existing physical meanings and JSON names.

The 242 new regression assertions include individual winding-cap rejection
witnesses under every candidate, live-port checks, objective correspondence,
JSON round trips and the shared-supply intervention. Initial development failures
were an overly narrow bus-dictionary type and a test incorrectly requesting a
voltage-law load update. Both original failures and the corrected tests remain
in the external archive; no solver or physical tolerance was relaxed.

## Structural diagnostics and timing exclusions

All sixteen separate 24-unit diagnostic solves and their sixteen warm-ups pass.
MUMPS reports actual pivot order 2 for request 7. These runs overlap other Julia
work: their native wall timers are retained but excluded from performance
interpretation. Model dimensions and storage counters provide a separate view
of the reformulation. For quadratic cost at the 1 kVA assembly base:

| Current/lifting choice | Variables | Unique Jacobian | Unique Hessian | Iterations | Maximum INFO(9) |
|:--|--:|--:|--:|--:|--:|
| Explicit, powers | 6608 | 56384 | 14976 | 22 | 735352 |
| Eliminated, powers | 6032 | 57848 | 16416 | 23 | 791423 |
| Explicit, bounded observations | 8960 | 62336 | 12116 | 23 | 849254 |
| Eliminated, bounded observations | 8672 | 65288 | 12116 | 25 | 828989 |

Power-lifted elimination removes 576 real variables while adding 1,464 Jacobian
and 1,440 Hessian entries. Its maximum reported factor double-storage count
increases by about 7.6%. Bounded-observation elimination removes only 288 real
variables and adds 2,952 Jacobian entries, while preserving the Hessian count;
its storage count decreases by about 2.4%. These counters are neither process
peak memory nor a measured factor-fill ratio. Derivative counts precede Ipopt
fixed-variable preprocessing. They cannot by themselves establish a speed win.

The base/objective interaction is substantial even before timing is considered.
For quadratic cost, explicit power lifting takes 22 iterations at both bases;
eliminated power lifting takes 23 at 1 kVA and 38 at 100 kVA. Under tracking,
the corresponding pairs are 21/49 and 29/50. This supports testing power bases
and recovered-observation support jointly, while keeping the physical objective
and limits fixed. It does not identify a universal scaling threshold.

Three isolated timing attempts were started, and all detected competing Julia
work. The monitor interrupted only the study's process group; other workloads
were untouched. **All three entire campaigns are excluded**, including rows completed
before interference. All partial reports and isolation logs remain archived.
There is no eligible larger-network speed ranking from this checkpoint. The
frozen two-batch, eight-sweep protocol is ready to rerun during a quiet window;
the earlier small-panel average benefit cannot be assumed to transfer.
The third attempt records 83 isolation samples and rechecks the 262-file freeze.
All production, runner and dependency contents match the first two attempts;
only the nonexecuted test-suite registration differs. Its complete and partial
rows are retained without speed interpretation.

## Separating assembly and generator units

The follow-up `examples/benchmark_ivr_nwinding_scaling.jl` crosses assembly
base ``S\in\{10^3,10^5\}`` VA with explicit generator power base
``G\in\{10^3,10^5\}`` VA. Each of the four current/lifting representations
receives all four combinations, at all three sizes and both objectives:
96 physical preflight endpoints. Every generator receives an explicit override.
The original diagonal comparison ``G=S`` is retained within this factorial.

At fixed ``S``, changing ``G`` rescales generator P/Q columns only. Their
physical equations and boxes retain the form

```math
p_{\mathrm{circuit}}(z)=(G/S)\widehat p_g,\qquad
P_g^{\min}/G\leq\widehat p_g\leq P_g^{\max}/G,
\qquad P_g=G\widehat p_g.
```

Changing ``S`` at fixed ``G`` is broader: it changes inherited current units
and assembly-normalized nonlinear power rows, including IBR power/DC bounds.
IBRs use circuit power expressions rather than separate generator dispatch
columns. Hence this factorial separates generator-column effects from the
remaining assembly-base effects; it **does not isolate current columns alone**.
Objective divisor 1, 500 VA generic/load-power auxiliaries, physical data,
nominal voltage scaling, row policy and solver settings remain fixed.
Ipopt gradient scaling can respond to the changed rows and derivatives.

The timing protocol groups four scaling arms within each fixed
size/objective/representation cell, with the same eight balanced sweeps and
reversed confirmation schedule as above. This plans 1,536 measured solves and
192 excluded warm-ups across two fresh processes. For an eligible cell, report
both conditional contrasts
``T(S,10^5)/T(S,10^3)`` and ``T(10^5,G)/T(10^3,G)``.
The ratio of the former contrasts at high and low ``S`` describes interaction;
a diagonal ratio alone cannot identify either factor. These are descriptive
optimizer-call wall-time comparisons, conditional on strict physical and
objective gates. Compilation costs remain excluded.

The regression verifies correspondence under every crossed setting, exact
physical generator-power recovery from independently scaled columns, rejected
generator-bound violations, independent non-star equations and complete common
SI starts. Objective terms and option dictionaries are owned independently by
each arm. The preflight anchor is shared across all sixteen candidates for a
size/objective pair, allowing cross-representation and cross-base membership
checks. No speed claim follows from nonisolated preflight iteration counts.

### Factorial preflight results — 6 October 2026

All **96/96** endpoints pass strict termination, physical and own/full/reverse
membership, objective agreement, complete starts and independent non-star
checks. All 96 exports pass both readers and independent SI audits, including
38,400 KCL balances, 13,056 coil powers, 6,528 winding caps, 29,376 voltage bands
and 2,176 inverter internal-power channels. Physical export structures match
across all sixteen representations/scales per size/objective. Maximum audited
KCL residual is ``6.38\times10^{-7}`` A (rounded upward), below the ``10^{-6}`` A
gate; this finite residual should not be mistaken for symbolic exactness.
The targeted regression passes **1,010/1,010 assertions**. An initial test
compared copied objective objects by identity; the corrected test compares
serialized field contents. All 96 initial failures were this test comparison,
not failed physical solves; the original test and log remain archived.

At 24 units, the single-preflight iteration counts are:

| Workload | Representation | S=1, G=1 | S=1, G=100 | S=100, G=1 | S=100, G=100 |
|:--|:--|--:|--:|--:|--:|
| cost | Explicit, powers | 22 | 31 | 30 | 22 |
| cost | Explicit, bounded | 23 | 28 | 30 | 38 |
| cost | Eliminated, powers | 23 | 30 | 28 | 38 |
| cost | Eliminated, bounded | 25 | 31 | 28 | 36 |
| tracking | Explicit, powers | 21 | 29 | 23 | 49 |
| tracking | Explicit, bounded | 22 | 34 | 25 | 47 |
| tracking | Eliminated, powers | 29 | 33 | 23 | 50 |
| tracking | Eliminated, bounded | 32 | 38 | 23 | 46 |

Bases in the table are kVA. At fixed 100 kVA assembly units, 1 kVA generator
columns reduce tracking iterations from 49 to 23 (explicit powers) and from
50 to 23 (eliminated powers). Conversely, explicit-power cost needs 22
iterations at both diagonal settings, but 31 and 30 at the off-diagonal
settings. Thus the generator/assembly interaction depends on the physical
objective and representation; a uniformly smaller generator base is not a
universal convergence prescription. Fixing generator units at 1 kVA also
reverses the tracking assembly-base trend for eliminated powers: 29 iterations
at 1 kVA versus 23 at 100 kVA. The earlier diagonal contrast hid that distinction.

These are convergence diagnostics from nonisolated runs, with no wall-time
ranking and no change to recommended defaults. Next, isolate circuit-current
columns using explicit regional current bases at fixed assembly/generator
units, with transformer boundaries defining independent regions. This would
separate current-coordinate effects from power-row normalization. The factorial
wall-time confirmation also remains pending; iteration reductions alone do not
establish an optimizer speed benefit.

## Reproduction

```sh
julia --project=test test/ivr_nwinding_network_tests.jl
julia --project=test test/ivr_nwinding_scaling_tests.jl
julia --project=test examples/benchmark_ivr_nwinding_network.jl /tmp/nwinding-network/exploration exploration
julia --project=test examples/benchmark_ivr_nwinding_network.jl /tmp/nwinding-network/confirmation confirmation
```

The factorial timing runner accepts the same two arguments (output directory,
`exploration` or `confirmation`). Its correctness evidence is archived separately
in `NWINDING_SCALING_FACTORIAL_20261006`.

Use `JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1`, fresh processes and recorded
isolation from other Julia work. The external `NWINDING_FEEDER_TRANSFER_20261006`
archive retains generated inputs, preflight exports, all three timing attempts, diagnostics,
source hashes, validation scripts and inventory scope. The archive name does
not imply successful external-feeder transfer. Plans and raw evidence remain
outside Git.
