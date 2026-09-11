"""Render the fixed SOC reduction study from checked-in raw JSON records."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "results"
SOURCES = ["reduction_soc_2026-09-11.json", "reduction_recovery_2026-09-11.json",
           "reduction_strengthening_2026-09-11.json", "reduction_transformers_2026-09-11.json"]
data = [json.loads((ROOT / name).read_text()) for name in SOURCES]

def number(x, digits=3):
    return "—" if x is None else f"{x:.{digits}f}"

def short(name):
    return name.replace("lvtestcase/snapshots/lvtestcase_pmd_", "LV ").replace("network_", "ENWL ").replace(".json", "").replace(".dss", "")

out = ["# Network reduction and fixed Clarabel SOC: 2026-09-11", "",
"BMOPFTools-compatible preparation reduces both 907-bus LV snapshots to 118 buses. "
"With the default 32-coordinate clique-size setting and linear strengthening, Clarabel now returns OPTIMAL "
"on both snapshots in approximately 14–15 seconds of model construction and solve time. "
"The previous unreduced runs exceeded the 240-second process budget without a result. "
"This is a budget comparison, not a precisely measured speedup.", "",
"## Protocol", "",
"Julia 1.12.6, Clarabel 0.11.1, Ipopt 1.16.0; one BLAS thread. All conic runs use SOC and any inherited "
"load power cones, with an assertion rejecting semidefinite cones. One model, one solve: no iterative OA. "
"Fixed taps, no control laws, source-bus generators removed, other generators retained; objective is net source "
"active-power import. Per-unit base is max(total apparent nominal load, installed active generation, 3000 VA)/3. "
"Clarabel tolerances are feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7, with a 90-second solve limit. "
"Warm-up is excluded; new component compilation can remain. Timings are single-run, indicative measurements; "
"some verification processes ran concurrently. No claim is made about subsecond timing differences.", "",
"The NLP comparison uses BMOPFTools with Ipopt on both original and reduced inputs. "
"NLP solutions are local optima, checked with BMOPFTools' solution checker. "
"The objective difference below is NLP minus SOC in watts; percent divides by the absolute NLP net-import objective. "
"Near-cancelling generation and demand can inflate this percentage (notably the 96-bus ENWL case). "
"These are numerical comparisons, not certified gaps, especially after approximate circuit reduction. "
"ALMOST_OPTIMAL and numerical failures remain visible and are excluded from accepted objective/state comparisons.", "",
"## Reducibility of the existing panel", "",
"| Case | Original buses | Reduced buses |",
"|---|---:|---:|"]
for c in json.loads((ROOT / "reduction_scan_2026-09-11.json").read_text()):
    r=c.get("false",{})
    out.append(f"| {short(c['name'])} | {r.get('buses_before','—')} | {r.get('buses_after','—')} |")
out += ["", "Allowing intermediate bus-bound removal did not reduce these counts further. "
"All 12 sampled ENWL inputs were already irreducible under the compatibility policy. "
"IEEE13 and IEEE123 are topology scans only: their earlier conversion/missing-impedance problems were not repaired in this study.", "",
"For both LV snapshots, original and reduced NLP source objectives agree to the reported precision: "
"22,418.515509 W (t500) and 48,869.907839 W (t1000). No approximate-reduction events were applied there. "
"The reduction implementation's π approximation is exercised by analytical tests; these LV results do not quantify π approximation error.", "",
"## Fixed-profile sweep", "",
"`linear32` is the existing default with clique_size=32; `linear12` uses 12. "
"`physical12/32` removes fixed linear strengthening, retaining physical SOC projections. "
"`kim12_8/kim32_8` enables eight data-selected triplets with the indicated clique size. "
"The requested clique size need not change a model that selects a dense layout.", "",
"| Case | Profile | Status | Build s | Solve s | NLP − SOC W | Difference % |",
"|---|---|---|---:|---:|---:|---:|"]
for group in (data[0],data[2]):
    for c in group["cases"]:
        for s in c.get("soc",[]):
            out.append(f"| {short(c['name'])} | {s['profile']} | {s.get('status','error')} | {number(s.get('build_seconds'))} | {number(s.get('solve_seconds'))} | {number(s.get('nlp_minus_soc_W'),6)} | {number(s.get('nlp_minus_soc_percent'),5)} |")
out += ["", "## Original-network recovery", "",
"The initial conditional-moment recovery was unstable: on LV t500 it produced a maximum voltage-magnitude "
"difference of 357.53 V and maximum KCL residual of roughly 29,433 A despite an OPTIMAL conic solve. "
"The new default uses diagonal voltage moments and a maximum-correlation phase forest anchored at sources. "
"It does not invert indefinite separator Grams. Original passive branches are then reconstructed with their original circuit equations.", "",
"| Case | Profile | Status | Max magnitude error V | Max phasor error V | Max KCL A | Reconstruction s |",
"|---|---|---|---:|---:|---:|---:|"]
for group in (data[1],data[2]):
    for c in group["cases"]:
        for s in c.get("soc",[]):
            out.append(f"| {short(c['name'])} | {s['profile']} | {s.get('status','error')} | {number(s.get('max_voltage_magnitude_difference_V'))} | {number(s.get('max_phasor_difference_V'))} | {number(s.get('max_kcl_A'))} | {number(s.get('reconstruction_seconds'))} |")
out += ["", "Accepted LV and 96-bus ENWL tree-recovery runs show no reconstructed bus-voltage or line-current-limit "
"violations in the recorded checks, but sizable KCL residuals remain. These outputs are useful voltage estimates; "
"they must not be presented as AC-feasible dispatches or assumed-accurate line loadings. Full residual diagnostics "
"and warnings accompany reconstruction. Kim32 reduces LV KCL residuals to about 18 A and 31 A; that is still material. "
"Objective accuracy alone is not a state-accuracy test.", "",
"Preparation takes approximately 0.2–0.5 seconds on the LV snapshots; reconstruction with the full physical check "
"takes approximately two seconds. These are additional to build/solve times. The reduced NLP takes roughly "
"0.02 seconds to build and 0.01 seconds to solve, so it remains much faster locally than the present SOC compiler. "
"This study supports reduction and the portability goal; it does not establish that SOC is the fastest local optimizer.", "",
"## Transformer diagnostic inputs", "",
"These are explicitly derived inputs: transformer s_rating fields are removed, aligning the earlier known "
"BMOPFTools nameplate-cap disagreement. They do not replace original-input results.", "",
"| Case | Buses | Original NLP | Reduced NLP | SOC | Build + solve s | Difference W |",
"|---|---|---|---|---|---:|---:|"]
for c in data[3]["cases"][1:]:
    r=c["reduction"];s=c["soc"][0]
    out.append(f"| {short(c['name'])} | {r['buses_before']} → {r['buses_after']} | {c['nlp_original']['status']} | {c['nlp_reduced']['status']} | {s.get('status')} | {number(s.get('build_seconds',0)+s.get('solve_seconds',0))} | {number(s.get('nlp_minus_soc_W'))} |")
out += ["", "IEEE34 still fails numerically in Clarabel after reduction; reduction does not resolve its conditioning problem. "
"Its reduced NLP objective is about 175.48 W below the original NLP objective, measuring a circuit-reduction effect "
"separately from the convex relaxation. CIGRE remains solvable, with approximately 0.0548% objective difference "
"and 5.89 V maximum reconstructed magnitude difference.", "",
"## Recommendation", "",
"Keep BMOPFTools-compatible reduction and the default linear32 SOC profile as the general starting point. "
"Smaller cliques were less reliable on the larger networks. Kim12_8 is a useful case-specific trade-off on ENWL "
"96: about 14.64 W difference versus 33.61 W for linear32, for roughly 19 versus 17.5 seconds of build/solve time. "
"Kim32_8 is reliable on both LV snapshots but offers only small objective improvements; it is optional rather "
"than a new blanket default. Removing linear strengthening did not produce a compelling advantage.", "",
"The next performance work should target repeated model construction and cached sparse preparation. "
"The next state-quality experiment should be a bounded AC power-flow correction at the selected dispatch, "
"separate from the fixed conic formulation. No such correction is included or implied by the present results.", "",
"## Reproduction and raw data", "",
"Run `julia --project=test/integration examples/benchmark_reduction.jl MANIFEST OUTPUT`, using the matching "
"reduction_manifest, reduction_recovery_manifest, reduction_strengthening_manifest, or reduction_transformer_manifest "
"under this directory. `julia --project=test/integration examples/scan_reduction.jl` repeats the topology scan. The initial sweep manifest explicitly selects conditional recovery; later manifests use "
"the voltage-tree default. Run `python3 examples/summarize_reduction.py` to regenerate this report.", ""]
for name in SOURCES: out.append(f"- [{name}]({name})")
(ROOT / "reduction_study_2026-09-11.md").write_text("\n".join(out)+"\n")
