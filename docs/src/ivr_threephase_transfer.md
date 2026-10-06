# Three-phase transfer and transformer nameplate limits

This study moves beyond the DSuite panels to an independent French MV/LV feeder.
It first exposed a physical-contract difference: the native exact-IVR default
leaves transformer `s_rating` unenforced, whereas BMOPFTools enforces an ordinary
transformer's nameplate at a specified winding port. The new explicit policy
closes that ordinary-transformer gap without changing the legacy problem or
removing any numerical option. The external experiment is a **correctness and
solver-admission preflight**, not a timing comparison.

## Rated-port contract and independent evidence

Use `IVRNLP(transformer_nameplate=:bmopftools)` when preserving the inspected
reference's ordinary-transformer nameplate caps. Single-phase and center-tap
units rate the from coil; Yd/Dy units rate each wye phase at one third of the
bank VA; regulators rate each from-side through coil at the undivided rating.
The [complete contract](ivr_nlp.md#Explicit-transformer-nameplate-policy)
distinguishes series current from wye phase-terminal current, documents missing
and invalid-zero data, and explains the unchanged multiwinding interpretation.
This is an explicit choice of physical bounds, not an exact coordinate transform.
All candidates in the new external preflight use the enforced policy.

Independent analytical witnesses cover six ordinary transformer/regulator
families, forward/reverse power, two electrical bases, three lifting choices and
transformer-current elimination. Tightened nameplates reject unchanged points
in both the encoded model and the independent SI auditor. A 200 W load behind
a 100 VA ideal transformer provides a motivating dispatch example: with local
generation priced and source exchange free, enforcing the cap requires 100 W
of local generation; the legacy uncapped problem requires none. Direct,
power-lifted and observation-lifted models reproduce this result and export
the same rated physical quantity.

The optional live test `test/integration/ivr_nameplate_reference.jl` compares
active-cap and absent-cap single-phase cases against BMOPFTools revision
`a8b52e069bfd4a7a57434c91bc0470ac03cfdd55`, at 1 and 100 kVA electrical bases.
All 108 assertions pass, including 12 native formulation/base/cap combinations,
transformer `s`/`s_max` fields and reading native JSON through BMOPFTools.
A supplied zero rating is rejected by both implementations. This reference
check does not establish all-family device-law parity or global optimality.

## Independent feeder and controlled interventions

The source is `FrenchPowerGrids/original/11_MVFeeder2143.bmopf.json` from the local
BMOPFDraftData output collection: 52 buses, 47 lines, four delta/wye transformers,
86 load records and nominal net demand 963.337467 kW. Source SHA-256 is
`6e197819b9578801d91df267168e6b8d70bf4a138459fc35f69f2085a6f49d21`.
Its supplied phase-neutral/phase-phase voltage, line-current and transformer
nameplate limits are preserved. No original electrical record is edited.
The source conversion retains explicit LV neutrals, coupled conductors and
separate transformer core shunts. Its own documented distinction between
per-coil BMOPFTools caps and aggregate Roseau loading remains; this study does
not claim equivalence with Roseau's feasible set or reverse that conversion.
The source dataset uses the Etalab Open Licence 2.0; external data and exact
addition manifests remain outside Git.

`examples/benchmark_ivr_threephase_transfer.jl` selects 38 original WYE/DELTA
load records with nonnegative three-channel P and positive total P. It adds
19 static generators and 19 IBRs: 18 four-leg LV units and one three-leg MV unit.
Each channel's P capacity is twice the site's mean nominal demand, with P from
zero to capacity, Q within half capacity and apparent power within capacity.
The total active capacity is 1926.674933 kW. Each IBR's total internal DC ceiling
is 60% of its summed P capacity; PCC availability is 80%. These are declared
scenario additions, not claims about actual installed equipment.

The four scenarios cross two factors:

- **Filter impedance:** R/X are 0.005/0.002 or 0.05/0.02 times the unloaded
  coil-voltage-squared/P-capacity base. Shunt susceptance, topology and all
  dispatch/DC bounds remain identical. Both impedances are finite; no ideal
  delta generator replaces the three-leg converter's internal freedom.
- **Parallel demand law:** an additional 10% of original selected P/Q is present
  in both treatments. One uses constant power; the other cycles constant-current,
  ZIP and exponential laws. Nominal demand, connection and nominal coil voltage
  are identical. ZIP P fractions are (0.2, 0.3, 0.5), Q fractions (0.4, 0.5, 0.1);
  exponential powers use P/Q exponents 0.4/−0.5. Original loads are untouched.

Thus changing the load-law factor does not also change nominal load, and changing
the filter factor does not also replace a generator with an IBR. Low and high
filter levels are physical interventions, not scaling choices. The unit tests
verify exact before/after replay, original-field preservation and factor isolation.

## Admission protocol and results

The six retained profiles are full power lifting, reduced power lifting,
reduced power lifting with generator reuse, signed bounded observations without
and with reuse, and cap-four signed observations with reuse. Numerical settings
match the prior mixed-device study: assembly/dispatch 10 kVA, power lifts 1 kVA,
nominal transformer units, composed rows, voltage-ground scaling, MUMPS AMD and
STRICT 1e-10 tolerances. Both Ipopt `none` and `gradient-based` policies are used
with one Julia/BLAS thread. Every profile encodes the same unloaded physical start.

Cost prices source P at 0.25/kWh, generator P and IBR internal P at 0.10/kWh,
plus PCC P/Q quadratic coefficients 0.02 and 0.002 in kW/kvar. Internal IBR
pricing includes filter copper loss. Tracking targets source P/Q at 500 kW/0 var
with the same midpoint-dispatch regularization as the
[mixed-device study](ivr_mixed_devices.md). Objective divisor one is fixed.

The table reports admitted candidates out of six, not runtime ranks.

| Scenario | Objective | None | Gradient |
|---|---|---:|---:|
| `low_constant_power` | `quadratic_cost` | 6/6 | 6/6 |
| `low_constant_power` | `exchange_tracking` | 6/6 | 6/6 |
| `low_voltage_dependent` | `quadratic_cost` | 3/6 | 2/6 |
| `low_voltage_dependent` | `exchange_tracking` | 3/6 | 6/6 |
| `high_constant_power` | `quadratic_cost` | 6/6 | 6/6 |
| `high_constant_power` | `exchange_tracking` | 6/6 | 6/6 |
| `high_voltage_dependent` | `quadratic_cost` | 3/6 | 1/6 |
| `high_voltage_dependent` | `exchange_tracking` | 4/6 | 4/6 |

All **48 constant-power combinations** pass. Across the voltage-dependent
scenarios, **26 of 48** pass. The 22 rejections comprise 17
`ALMOST_LOCALLY_SOLVED`, four `OTHER_ERROR` and one `LOCALLY_INFEASIBLE` status.
No tolerance is relaxed, failed profile removed, or failed trial relabelled as
accepted. The full-power profile passes every cell. A separate diagnostic
solves the full model and maps its point into each rejected reduced model;
**all 22 admit that point**. Hence a solver's infeasibility status here is not
evidence that the underlying constrained electrical problem is infeasible.
The numerical cause remains to be diagnosed; reduction, lifting and load-law
interactions cannot yet be ranked reliably.

The **74 admitted endpoints** pass independent physical checks, own/full and
reverse membership, complete-start checks and SI JSON round trips. All **296
bound witnesses** reject tightened original voltage, original line current,
original transformer nameplate or added IBR DC limits. All **41 admitted tracking
endpoints** activate phase 1 of the inherited 110 kVA
`11_MVLV10320_Transformer` cap: 36.666667 kVA per wye phase. Cost endpoints leave
that cap slack. Every inherited bound's signed slack is retained in the evidence.
Independent export-based objective reconstruction differs by less than
5.56e-10; within-cell admitted objective spread is below 2.05e-10.

For admitted cost endpoints, summed filter loss rises from roughly 367–374 W
to 3383–3423 W as impedance increases. Under tracking it rises from roughly
1316–1318 W to 13,161–13,178 W. These are physical scenario outcomes, not solver
speed effects. Tracking objectives at the two filter levels remain very close
because tracking prices PCC power and the internal ceilings remain nonbinding
at these endpoints; it does not directly price internal filter losses.

## Consequences for earlier evidence

The earlier native contract deliberately excluded `s_rating`; its regression
inventory therefore did not prove preservation of BMOPFTools nameplate limits.
The new field policy makes that scope visible. A retrospective independent check
of **112 saved urban/rural preflight exports**, covering **912 rated phase
observations**, finds no nameplate violation; maximum utilization is 0.179210.
Those endpoints remain feasible under the extra caps. This does **not** retime
models containing the additional rows, establish earlier-panel completeness, or
retroactively change the physical contract under which previous rankings ran.
All historical raw evidence and alternatives remain available.

## Reproduction, limitations and next steps

Call `IVRThreePhaseTransferStudy.scenario(original; filter_level=:low,
load_law=:constant_power)` for one declared treatment. Its returned manifest
contains exact additions and site choices. The inherited mixed-device profile
builder is unchanged; this separate runner forces `transformer_nameplate=:bmopftools`.
The [tutorial](tutorial_exact_ivr.md) demonstrates both the active-cap dispatch
example and isolated scenario construction on manufactured inputs.

The full preflight, rejected statuses, 74 SI exports, original input, all four
addition manifests, bound slacks, live-reference results and retrospective audit
are retained in `THREEPHASE_TRANSFER_20261006` outside Git. Initial test setup
mistakes and reporting errors are retained separately: a missing screen reference,
a one-load rather than four-load fixture, missing analytical bond observations,
a missing empty-point voltage argument, and failure serialization attempted after
an unadmitted solve. The live reference corrected an initial assumption about
zero ratings: BMOPFTools rejects them at its input boundary. None of these fixes
relaxes a physical or solver acceptance test.

No timing campaign is run. Next, diagnose the voltage-dependent reduced-model
failures with complete solver logs and derivative/scaling checks, retaining the
full-model feasible points. After admission is reliable, freeze the complete
panel and run isolated paired timing batches ranked only by Ipopt wall time.
Broader live transformer-family parity, the different scalar multiwinding power-
limit conventions, and original-network preprocessing reconstruction remain open.
