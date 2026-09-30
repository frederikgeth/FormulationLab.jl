"""Summarize benchmark_enwl_cost.jl output; plotting requires matplotlib/numpy.

Usage: python examples/report_enwl_cost.py RESULTS.json[.gz]
The complete observations are also saved as gzip, without deleting the input.
"""
import collections
import gzip
import json
import math
from pathlib import Path
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

path = Path(sys.argv[1])
opener = gzip.open if path.suffix == ".gz" else open
with opener(path, "rt") as f:
    data = json.load(f)
base = path.with_suffix("") if path.suffix == ".gz" else path
stem = base.with_suffix("")
models = ("linivr", "lindist3flow")
labels = {"linivr": "LinIVR", "lindist3flow": "Kron LinDist3Flow"}
colors = {"linivr": "#176b98", "lindist3flow": "#d8752f"}
rows = data["cases"]
ok = lambda d: d.get("status") in ("OPTIMAL", "LOCALLY_SOLVED")
reference_rows = [r for r in rows if ok(r.get("ivr", {}))]
paired = [r for r in reference_rows if all(ok(r.get(m, {})) and ok(r[m].get("replay", {})) for m in models)]
checked = [r for r in paired if all(r[m]["replay"]["solution_check"]["verification_status"] == "checks_passed" for m in models)]

def stats(values):
    a = np.asarray(values, dtype=float)
    return {"n": len(a), "median": float(np.median(a)), "p95": float(np.quantile(a, .95)),
            "min": float(np.min(a)), "max": float(np.max(a))} if len(a) else {"n": 0}

def relative(value, reference):
    return 100 * (value - reference) / abs(reference) if abs(reference) > 1e-10 else None

summary = {"cases": len(rows), "buses_min": min(r["buses"] for r in rows), "buses_max": max(r["buses"] for r in rows),
           "paired_replays": len(paired), "paired_checked_replays": len(checked), "models": {}, "reference_statuses": dict(collections.Counter(r.get("ivr", {}).get("status", "error") for r in rows)),
           "reference_check_statuses": dict(collections.Counter(r.get("ivr", {}).get("solution_check", {}).get("verification_status", "not assessed") for r in rows)),
           "zero_cost_reference_exclusions": sum(abs(r["ivr"]["cost_per_hour"]) <= 1e-10 for r in reference_rows)}
for m in models:
    valid = [r for r in reference_rows if ok(r.get(m, {}))]
    d = {"statuses": dict(collections.Counter(r.get(m, {}).get("status", "error") for r in rows)),
         "replay_statuses": dict(collections.Counter(r.get(m, {}).get("replay", {}).get("status", "not run") for r in rows)),
         "reported_cost_difference_pct": stats([v for r in valid if (v := relative(r[m]["cost_per_hour"], r["ivr"]["cost_per_hour"])) is not None]),
         "replayed_cost_difference_pct_paired": stats([v for r in paired if (v := relative(r[m]["replay"]["cost_per_hour"], r["ivr"]["cost_per_hour"])) is not None]),
         "replayed_cost_difference_pct_paired_checked": stats([v for r in checked if (v := relative(r[m]["replay"]["cost_per_hour"], r["ivr"]["cost_per_hour"])) is not None]),
         "voltage_own_optimum": {}, "voltage_same_dispatch_paired": {}}
    for key in ("vpn", "vng"):
        for population, comparison, target in ((valid, "versus_ivr_optimum", "voltage_own_optimum"), (paired, "versus_same_dispatch_replay", "voltage_same_dispatch_paired")):
            d[target][key] = stats([r[m][comparison][key]["max_abs_V"] for r in population])
            count = sum(r[m][comparison][key]["count"] for r in population)
            d[target][key]["pooled_rmse_V"] = math.sqrt(sum(r[m][comparison][key]["rmse_V"]**2*r[m][comparison][key]["count"] for r in population)/count)
    replays = [r for r in rows if ok(r.get(m, {}).get("replay", {}))]
    d["replay_vpn_violation_cases"] = [r["name"] for r in replays if r[m]["replay"]["voltage_limits"]["max_vpn_violation_V"] > 1e-4]
    d["replay_check_statuses"] = dict(collections.Counter(r[m]["replay"].get("solution_check", {}).get("verification_status", "not assessed") for r in replays))
    d["replay_operational_failures"] = [{"name": r["name"], "max_vpn_violation_V": r[m]["replay"]["voltage_limits"]["max_vpn_violation_V"],
        "error_codes": dict(collections.Counter(f["code"] for f in r[m]["replay"]["findings"]))} for r in replays
        if r[m]["replay"]["solution_check"]["verification_status"] == "failed"]
    d["max_replay_dispatch_error_VA"] = max(r[m]["replay"]["max_generator_dispatch_error_VA"] for r in replays)
    d["failed_replays"] = [{"name": r["name"], "status": r[m].get("replay", {}).get("status", "not run")} for r in rows if not ok(r.get(m, {}).get("replay", {}))]
    summary["models"][m] = d
summary["max_linear_cost_disagreement_per_hour"] = max(abs(r["linivr"]["cost_per_hour"]-r["lindist3flow"]["cost_per_hour"]) for r in rows if all(ok(r.get(m, {})) for m in models))
summary["linear_cost_agreement_within_1e-8"] = sum(abs(r["linivr"]["cost_per_hour"]-r["lindist3flow"]["cost_per_hour"]) < 1e-8 for r in rows if all(ok(r.get(m, {})) for m in models))
summary["max_objective_reconstruction_error"] = max(r[m]["objective_reconstruction_error"] for r in rows for m in ("ivr", *models) if ok(r.get(m, {})))
summary["reference_cost_per_hour"] = stats([r["ivr"]["cost_per_hour"] for r in reference_rows])
summary["reference_max_neutral_V"] = max(max(r["ivr"]["voltage"]["vng_V"].values()) for r in reference_rows)
summary["linivr_wins_same_dispatch_vpn"] = sum(r["linivr"]["versus_same_dispatch_replay"]["vpn"]["max_abs_V"] < r["lindist3flow"]["versus_same_dispatch_replay"]["vpn"]["max_abs_V"] for r in paired)
summary["linivr_lower_replayed_cost"] = sum(r["linivr"]["replay"]["cost_per_hour"] < r["lindist3flow"]["replay"]["cost_per_hour"] for r in paired)
stem.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2)+"\n")
raw_gz = Path(str(base)+".gz")
if path != raw_gz:
    with gzip.open(raw_gz, "wt") as f:
        json.dump(data, f, separators=(",", ":"))

# Scientific comparison: one point per feeder, identical accepted replay subset.
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
                     "svg.fonttype": "none", "figure.facecolor": "white"})
fig, axes = plt.subplots(2, 2, figsize=(11.6, 8.0), layout="constrained")
for ax, metric, title in ((axes[0, 0], "vpn", "Phase-to-neutral magnitude error"), (axes[0, 1], "vng", "Neutral-to-ground magnitude error")):
    for m in models:
        x = np.sort([r[m]["versus_same_dispatch_replay"][metric]["max_abs_V"] for r in paired])
        ax.step(x, np.arange(1, len(x)+1)/len(x)*100, where="post", label=labels[m], color=colors[m], linewidth=2)
    ax.set(xscale="log", xlabel="Maximum error within feeder (V)", ylabel="Cumulative fraction of feeders (%)", title=title, ylim=(0, 102))
    ax.grid(alpha=.2, which="both"); ax.legend(loc="lower right")
ax = axes[1, 0]
for m, marker in (("linivr", "o"), ("lindist3flow", "+")):
    rr = [r for r in reference_rows if ok(r.get(m, {})) and abs(r["ivr"]["cost_per_hour"]) > 1e-10]
    ax.scatter([r["buses"] for r in rr], [relative(r[m]["cost_per_hour"], r["ivr"]["cost_per_hour"]) for r in rr],
               s=24, alpha=.75, marker=marker, color=colors[m], label=labels[m])
ax.axhline(0, color="0.5", linewidth=.8)
ax.set(xlabel="Number of buses", ylabel="(Model cost − IVR cost) / |IVR cost| (%)", title="Reported generation cost at each optimum")
ax.grid(alpha=.2); ax.legend()
ax = axes[1, 1]
for m in models:
    vals = sorted(relative(r[m]["replay"]["cost_per_hour"], r["ivr"]["cost_per_hour"]) for r in paired if abs(r["ivr"]["cost_per_hour"]) > 1e-10)
    ax.step(vals, np.arange(1, len(vals)+1)/len(vals)*100, where="post", color=colors[m], label=labels[m], linewidth=2)
ax.set(xscale="log", xlabel="(Replayed cost − IVR cost) / |IVR cost| (%)", ylabel="Cumulative fraction of feeders (%)",
       title="Realised generation cost at approximate dispatch", ylim=(0, 102))
ax.grid(alpha=.2); ax.legend(loc="lower right")
fig.suptitle(f"ENWL cost minimisation: {len(rows)} feeders; {len(paired)} paired nonlinear replays", fontsize=15)
fig.savefig(stem.with_suffix(".png"), dpi=180)
fig.savefig(stem.with_suffix(".svg"))
# Matplotlib emits trailing spaces inside multiline SVG path attributes.
svg_path = stem.with_suffix(".svg")
svg_path.write_text("\n".join(line.rstrip() for line in svg_path.read_text().splitlines())+"\n")
plt.close(fig)

fmt = lambda x: f"{x:.5g}" if isinstance(x, (int, float)) else "—"
lines = ["# ENWL generation-cost comparison — 30 September 2026", "",
    f"The panel covers all **{len(rows)} JSON networks**, from **{summary['buses_min']} to {summary['buses_max']} buses**, in the supplied ENWL `reduced` directory. These files have previously reduced topology but retain four-wire conductors. LinIVR and the nonlinear reference retain those conductors. Only LinDist3Flow applies an additional neutral Kron projection.", "",
    "## Comparable economic problem", "",
    "The supplied files contain a priced `generator.grid` at the source bus alongside an independent unpriced ideal voltage source. As written, the optimizer can drive that generator to its negative P limit while the voltage source supplies free power. This gives an artificial export credit. The as-supplied audit below retains that behavior; it is not used to claim useful cost accuracy.", "",
    "For the main panel, copies of each network transfer the grid generator's cost and active-power bounds to the voltage source and remove the duplicate generator. All DER prices and active bounds are retained; no source-import objective or uniform replacement tariff is substituted. Export is credited at the original grid tariff. Reactive bounds are absent in these files and remain absent: Q is unpriced and otherwise unbounded by device capability. LinDist3Flow's input validation was extended to accept that same contract.", "",
    "All three solvers receive identical prices, uniformly divided by the case's maximum tariff for numerical conditioning. Every reported cost is independently recomputed from original coefficients as Σ cₖPₖ/1000 (currency/hour). This positive objective scaling does not change the mathematical optimizer. Source files are never edited. The raw observations record hashes, transformations, numerical settings and dependency revisions.", "",
    "LinDist3Flow uses source-propagated reference phasors and its permissive, audited Kron projection. The only reported model-change codes are ideal-neutral grounding and removal of neutral-conductor current ratings. Phase ratings and phase-to-neutral voltage bounds are retained. Its reported neutral voltage is the imposed zero-ground assumption; it has no neutral-voltage state. No loaded AC solution enters either approximate model.", "",
    "## Solve and replay outcomes", "",
    f"Nonlinear IVR statuses: `{summary['reference_statuses']}`. Reference checker outcomes: `{summary['reference_check_statuses']}`. Ipopt gives local candidates, not global optimality certificates.", "",
    "| Model | Optimisation status counts | Four-wire replay status counts |",
    "|:--|:--|:--|"]
for m in models:
    d = summary["models"][m]
    lines.append(f"| {labels[m]} | {d['statuses']} | {d['replay_statuses']} |")
lines += ["", "Replay fixes every non-slack generator's active **and reactive** power. The original four-wire nonlinear circuit then determines the slack injection and its losses; source box constraints remain enforced. A local-infeasibility status is not a proof that the fixed dispatch has no AC solution. Near-converged results are excluded, not silently promoted to accepted solutions.", "",
    f"The paired replay statistics below use the same **{len(paired)} feeders** for both approximations. Voltage violations use a 0.0001 V reporting threshold. The BMOPFTools solution checker explicitly leaves some dimensions unassessed, including full device-equation/KCL verification and complete limit coverage; a passed checker is not a comprehensive feasibility certificate.", ""]
for m in models:
    d = summary["models"][m]
    lines.append(f"- {labels[m]}: accepted-replay checker outcomes `{d['replay_check_statuses']}`; {len(d['replay_vpn_violation_cases'])} accepted replays exceed phase-to-neutral limits; maximum fixed-DER dispatch residual {fmt(d['max_replay_dispatch_error_VA'])} VA.")
lines += ["", "## Voltage accuracy", "",
    "Magnitude error means | |Vφ−Vn|model − |Vφ−Vn|AC | for phase-to-neutral voltage and | |Vn|model − |Vn|AC | for neutral-to-ground voltage. The table summarizes each feeder's maximum error; RMSE pools individual bus/channel observations. LinIVR's complex-phasor errors are also retained in the raw data. LinDist3Flow's reference angles are not treated as solved phase angles.", "",
    "### Approximation error at its own fixed dispatch", "",
    "| Model | Quantity | Median feeder max (V) | 95th percentile (V) | Worst (V) | Pooled RMSE (V) |",
    "|:--|:--|--:|--:|--:|--:|"]
for m in models:
    for metric, label in (("vpn", "phase-to-neutral"), ("vng", "neutral-to-ground")):
        d = summary["models"][m]["voltage_same_dispatch_paired"][metric]
        lines.append(f"| {labels[m]} | {label} | {fmt(d['median'])} | {fmt(d['p95'])} | {fmt(d['max'])} | {fmt(d['pooled_rmse_V'])} |")
lines += ["", f"LinIVR has the smaller maximum phase-to-neutral error on **{summary['linivr_wins_same_dispatch_vpn']}/{len(paired)}** paired replays. The zero-neutral error for Kron LinDist3Flow equals the actual neutral displacement at its dispatch; this measures omitted physics, not a solved neutral estimate.", "",
    "### Difference between independently optimised states", "",
    "| Model | Quantity | Median feeder max (V) | 95th percentile (V) | Worst (V) |",
    "|:--|:--|--:|--:|--:|"]
for m in models:
    for metric, label in (("vpn", "phase-to-neutral"), ("vng", "neutral-to-ground")):
        d = summary["models"][m]["voltage_own_optimum"][metric]
        lines.append(f"| {labels[m]} | {label} | {fmt(d['median'])} | {fmt(d['p95'])} | {fmt(d['max'])} |")
lines += ["", "This second table includes dispatch differences as well as voltage-model error. The approximations' first-order cost does not price incremental losses, leaving flat directions in Q; nonlinear IVR can select reactive dispatch that reduces resistive losses. Thus there need not be a unique voltage profile associated with an approximate economic optimum.", "",
    "## Objective accuracy", "",
    "All percentages use 100 × (candidate cost − nonlinear-IVR cost) / |nonlinear-IVR cost|. Negative reported-cost differences mean optimistic model objectives; they are not relaxation bounds. Replayed cost includes the nonlinear slack injection at the approximate DER dispatch. Near-zero reference costs are excluded from percentage statistics, with the count recorded in the summary.", "",
    "| Model / evaluation | Median difference (%) | 95th percentile (%) | Minimum (%) | Maximum (%) |",
    "|:--|--:|--:|--:|--:|"]
for m in models:
    for k, label in (("reported_cost_difference_pct", "reported optimum"), ("replayed_cost_difference_pct_paired", "nonlinear replay")):
        d = summary["models"][m][k]
        lines.append(f"| {labels[m]} / {label} | {fmt(d['median'])} | {fmt(d['p95'])} | {fmt(d['min'])} | {fmt(d['max'])} |")
lines += ["", f"The approximate objectives agree within 10⁻⁸ currency/hour on **{summary['linear_cost_agreement_within_1e-8']}/{len(reference_rows)}** jointly solved cases. The largest difference is **{fmt(summary['max_linear_cost_disagreement_per_hour'])} currency/hour**. Both largely omit incremental loss costs, but their feasible dispatch regions differ because of voltage and neutral-current constraints. Near-equal objectives do not imply near-equal voltages or equally good AC dispatch. Independently reconstructed objectives agree with solver objectives within {fmt(summary['max_objective_reconstruction_error'])} currency/hour.", "",
    f"LinIVR gives lower replayed cost on **{summary['linivr_lower_replayed_cost']}/{len(paired)}** paired cases. This is observed performance of the selected solver optima, not a guarantee: unpriced reactive dispatch can change with solver tie-breaking. A positive replay cost difference is relative to the locally solved IVR reference, not a certified global optimality gap.", "",
    f"Among the **{len(checked)} paired replays passing the assessed operational checks**, LinIVR's median/worst replay cost difference is {fmt(summary['models']['linivr']['replayed_cost_difference_pct_paired_checked']['median'])}% / {fmt(summary['models']['linivr']['replayed_cost_difference_pct_paired_checked']['max'])}%; LinDist3Flow's is {fmt(summary['models']['lindist3flow']['replayed_cost_difference_pct_paired_checked']['median'])}% / {fmt(summary['models']['lindist3flow']['replayed_cost_difference_pct_paired_checked']['max'])}%. The broader statistics above deliberately retain converged replays that violate limits; such costs are not feasible-dispatch performance claims.", "",
    f"![Voltage and cost comparison]({stem.name}.png)", "",
    "## As-supplied economic audit", "",
    "| Case | Buses | Four-wire IVR cost/h | LinIVR cost/h | Kron LinDist3Flow cost/h |",
    "|:--|--:|--:|--:|--:|"]
for r in data["as_supplied_audit"]:
    lines.append(f"| {r.get('name', 'input error')} | {r.get('buses', '—')} | " + " | ".join(fmt(r.get(m, {}).get("cost_per_hour")) for m in ("ivr", *models)) + " |")
lines += ["", "These very close, typically negative costs are dominated by the duplicate grid device's artificial export credit. They should not be interpreted as validation of the lossless economic models.", "",
    "## Non-accepted replays", "", "| Model | Case | Status |", "|:--|:--|:--|"]
for m in models:
    for r in summary["models"][m]["failed_replays"]:
        lines.append(f"| {labels[m]} | {r['name']} | {r['status']} |")
lines += ["", "### Converged replays with assessed limit violations", "",
    "| Model | Case | Maximum Vpn violation (V) | Error codes and counts |", "|:--|:--|--:|:--|"]
for m in models:
    for r in summary["models"][m]["replay_operational_failures"]:
        lines.append(f"| {labels[m]} | {r['name']} | {fmt(r['max_vpn_violation_V'])} | {r['error_codes']} |")
lines += ["", "## Per-feeder results", "",
    "Costs are currency/hour. Voltage columns are maximum phase-to-neutral magnitude errors against each model's own nonlinear replay. A dash means that replay was not accepted.", "",
    "| Case | Buses | IVR cost/h | LinIVR cost/h | L3F cost/h | LinIVR replay Δcost (%) | L3F replay Δcost (%) | LinIVR ΔV (V) | L3F ΔV (V) |",
    "|:--|--:|--:|--:|--:|--:|--:|--:|--:|"]
for r in rows:
    vals = [r.get(m, {}).get("cost_per_hour") for m in ("ivr", *models)]
    regret = [relative(r[m]["replay"]["cost_per_hour"], r["ivr"]["cost_per_hour"]) if ok(r[m].get("replay", {})) and ok(r["ivr"]) else None for m in models]
    errors = [r[m].get("versus_same_dispatch_replay", {}).get("vpn", {}).get("max_abs_V") for m in models]
    lines.append(f"| {r['name']} | {r['buses']} | " + " | ".join(map(fmt, vals+regret+errors)) + " |")
lines += ["", "## Reproduction and scope", "",
    "Run `julia --project=test/integration examples/benchmark_enwl_cost.jl DIRECTORY OUTPUT.json`, then `python examples/report_enwl_cost.py OUTPUT.json` (matplotlib/numpy). The optional third Julia argument limits the panel to the first N cases sorted by size. Timings include compilation and are not a speedup benchmark.", "",
    f"Julia {data['julia']}; Clarabel {data['clarabel']}; Ipopt {data['ipopt']}; BMOPFTools revision `{data['bmopftools_revision']}`. Nonlinear CPU limit: {data['nonlinear_cpu_limit_seconds']} seconds per solve. Results use one solver run per model/dispatch, without an AC warm start for either approximation.", "",
    f"[Complete observations]({raw_gz.name}) · [Aggregate JSON]({stem.name}.summary.json) · [Vector figure]({stem.name}.svg)", "",
    "The results support LinIVR as a substantially better neutral-aware voltage approximation on this panel. They do not establish that its first-order generation-cost objective is accurate or that every approximate dispatch is AC feasible. The next economic formulation experiment should account for quadratic losses or resolve flat reactive-dispatch directions with an explicitly declared secondary objective, followed by the same nonlinear replay protocol."]
stem.with_suffix(".md").write_text("\n".join(lines)+"\n")
print(json.dumps(summary, indent=2))
