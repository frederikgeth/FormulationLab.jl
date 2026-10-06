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
individual effects. A subsequent scaling experiment should vary them separately.

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

Two isolated timing attempts were started, and both detected competing Julia
work. The monitor interrupted only the study's process group; other workloads
were untouched. **Both entire campaigns are excluded**, including rows completed
before interference. All partial reports and isolation logs remain archived.
There is no eligible larger-network speed ranking from this checkpoint. The
frozen two-batch, eight-sweep protocol is ready to rerun during a quiet window;
the earlier small-panel average benefit cannot be assumed to transfer.

## Reproduction

```sh
julia --project=test test/ivr_nwinding_network_tests.jl
julia --project=test examples/benchmark_ivr_nwinding_network.jl /tmp/nwinding-network/exploration exploration
julia --project=test examples/benchmark_ivr_nwinding_network.jl /tmp/nwinding-network/confirmation confirmation
```

Use `JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1`, fresh processes and recorded
isolation from other Julia work. The external `NWINDING_FEEDER_TRANSFER_20261006`
archive retains generated inputs, preflight exports, both timing attempts, diagnostics,
source hashes, validation scripts and inventory scope. The archive name does
not imply successful external-feeder transfer. Plans and raw evidence remain
outside Git.
