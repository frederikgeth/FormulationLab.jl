# IEEE 9500 infeasibility diagnosis — 12 September 2026

The corrected IEEE 9500 static scenario is infeasible because its fixed demands
conflict with line-current limits and transformer nameplate limits. Two
independent single-limit experiments establish concrete causes. Their ratings
and loads agree with the source deck; these examples do not indicate a
per-unit scaling error. No production limits or formulation code were changed.

## Scenario and method

Use the same unbalanced linecode variant, nine open switches, frozen written
taps and two explicit 2.5 kW idle-battery loads as the corrected import study.
Input is `/tmp/ieee9500_final.json`, exported with Rust PowerIO `f6fb8081` via
PowerIO.jl 0.11.0. The adjacent JSON records its SHA-256, Julia and Clarabel
versions, status and timing for each experiment. Power base is 1 MVA.

Build the rated model once. Remove only branch thermal cone constraints on this
private diagnostic model, retaining generator/IBR capabilities, loads, source
voltage, voltage equations and all other constraints. Save the removed cone
objects and evaluate them at the unrated feasible solution. Restore selected
families or individual cones to test whether each can independently cause
infeasibility. This avoids changing electrical data or inadvertently changing
leakage bases by deleting transformer ratings from the input.

| Constraints restored after removing branch thermal cones | Result |
|:--|:--|
| All original limits | `INFEASIBLE` |
| None | `OPTIMAL` |
| All line-current limits only | `INFEASIBLE` |
| All transformer apparent-power limits only | `INFEASIBLE` |
| Only `Tpx338899C0`, receiving terminal 1, 195 A | `INFEASIBLE` |
| Only `T226192762B`, primary 5 kVA nameplate | `INFEASIBLE` |
| All except the 57 cone rows violated by the selected unrated solution | `OPTIMAL` |

The last row removes 50 endpoint/phase current cones on 19 lines and seven
center-tap primary nameplate cones. It is a sufficient diagnostic relaxation,
**not a minimal correction set**. Other dispatch choices can change which of
those 57 rows are violated. In particular, the seven transformer violations
must not all be labelled unavoidable solely from this one solution.

## A transformer conflict that follows directly from the data

`LoadXfmrCodes.dss:612` assigns `T226192762B` to `CT5`.
The `CT5` definition at line 6 specifies a 5 kVA primary winding. PowerIO exports
`s_rating=5000`, which the L3F model enforces as a hard primary apparent-power
limit. Its two downstream constant-power loads are:

| Load | Active W | Reactive var |
|:--|--:|--:|
| `226192762B0a` | 3845.054805 | 963.661571 |
| `226192762B0b` | 1911.549452 | 479.079452 |
| Total | **5756.604257** | **1442.741023** |

There is no downstream generator. Active demand alone exceeds 5 kVA, since
`|S| ≥ P`. The model's exciting-branch conductance is nonnegative and cannot
cancel this active demand. Thus this nameplate bound is impossible even before
accounting for reactive demand or physical copper losses. The single-cone
experiment confirms the same conclusion numerically.

At the selected unrated L3F solution, primary apparent power is approximately
5.951 kVA (1.190 times nameplate). A separate, converged OpenDSS service circuit
using the exact CT5, 50 ft service and load parameters, supplied at a favorable
1.05 pu primary voltage, requires **6.084 kVA**. It independently confirms the
overload; it is not a replay of full-feeder voltages.

OpenDSS power flow does not impose the BMOPF nameplate constraint as an OPF
feasibility condition. Its reported emergency primary current for this isolated
transformer is 1.041667 A, corresponding to 7.5 kVA at nominal 7.2 kV. That is a
different operating allowance from the imported 5 kVA nameplate. A converged
OpenDSS solution therefore does not imply feasibility under our hard nameplate
policy. Do not silently reinterpret `s_rating` as emergency capability.

## An independent line-current conflict

`TriplexLines.dss:546` defines `Tpx338899C0` as a 50 ft `4/0Triplex` service.
`TriplexLineCodes.dss:16` specifies `Normamps=156 {156 1.25 *}`: the subsequent
positional emergency-amp assignment evaluates to **195 A**. This agrees with
PowerIO's `i_max=[195,195]` and OpenDSS's evaluated emergency current.

The first load on `SX3122814C` is 34.046217 kW + j8.532786 kvar, or
**35.099193 kVA**. Its receiving current constraint requires

```
|V| >= |S| / I_max = 35099.192538 / 195 = 179.995859 V.
```

Maximizing that receiving terminal's squared voltage in the full L3F model,
with all branch thermal cones removed and DER capabilities retained, gives
approximately **127.999 V** (`OPTIMAL`). Even at that numerical maximum, the
fixed demand requires approximately **274.215 A**. The single receiving-current
cone alone is infeasible. The gap to 180 V is far beyond solver tolerances.

At the selected unrated solution, the largest current estimate is 1.535 times
195 A, approximately 299.34 A. Independent OpenDSS evaluation of this service
with two stiff anti-phase 126 V sources gives **288.539 A** on the first leg
and 270.475 A on the second. Receiving voltages are 121.645 and 122.174 V, both
above the loads' 0.88 pu constant-power threshold. The engine's low-voltage load
fallback therefore does not explain away this overload.

## Scope of the AC check

Both isolated service circuits converge using OpenDSSDirect 0.9.9. They test
source parameter interpretation and physical overloads at explicit favorable
boundary voltages. They do not certify all 9500 buses or match the optimized
DER dispatch in the full L3F model.

The attempted unchanged full static-deck replay stops earlier: the installed
OpenDSS engine rejects `PVSystem.PVFarm1` with `Mode=7` in `Generators.dss:7`
(error 401, invalid PVSystem model value). This is an additional reference-deck
compatibility issue. No substitution for that model was made to produce a
purported full-feeder reference. Resolve its intended behavior explicitly before
making a full AC comparison; generator Model=7 and PVSystem Model=7 must not be
assumed interchangeable.

## Consequences and next steps

1. Keep the existing hard bounds for OPF. Raising them is a scenario/policy
   decision, not a numerical repair justified by these findings.
2. For a power-flow diagnostic, allow an explicitly named overload-reporting
   scenario and report every loading ratio. The unrated solution is useful for
   this purpose but is not a feasible solution of the rated OPF.
3. If normal/emergency operation is desired, define separate nameplate and
   operating-limit semantics, including provenance, before changing the
   PowerIO/BMOPF boundary. Emergency transformer allowances alone will not fix
   the triplex emergency-current violation.
4. Create feasible study scenarios with explicit demand scaling/curtailment or
   equipment upgrades, then compare formulations on the same scenario. An
   infeasible fixed-demand case cannot yield a meaningful feasible OPF gap.
5. Resolve the invalid PVSystem model and freeze matching DER/capacitor states
   before full-feeder AC validation. The isolated checks already suffice to
   establish these two rating conflicts.

## Reproduction and validation

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test examples/diagnose_ieee9500_ratings.jl /tmp/ieee9500_final.json /tmp/diagnosis.json
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test examples/check_ieee9500_service_oracles.jl /tmp/service-oracles.json
```

Results are committed as `ieee9500_rating_diagnosis_2026-09-12.json` and
`ieee9500_service_oracles_2026-09-12.json`. The diagnostic scripts were run;
Documenter is rebuilt for the updated conclusions. No production source or
solver defaults change, so the prior 5,694-test implementation result is retained
rather than represented as a new full test run.
