"""Render the fixed-profile controlled study; standard library only."""
import json
import statistics
import sys
from pathlib import Path

source = Path(sys.argv[1])
data = json.loads(source.read_text())
lines = ["# Controlled Clarabel SOC comparison", "", f"Evidence baseline: `{data['revision']}`. "
         f"Julia {data['julia']}, Clarabel {data['clarabel']}, {data['cpu']}, "
         f"{data['blas_threads']} BLAS thread, {data['repeats']} serial repeats.", "",
         "Fresh solver setup and default starts on every run; model construction is reused. "
         "Profile order rotates between repeats. Small-case warm-up precedes measurements. "
         "Native solve time is Clarabel's internal `solve!` timer; setup, JuMP/MOI attachment, "
         "result extraction and original-network reconstruction are excluded. "
         "KKT update time includes matrix updates, refactorization and the constant-RHS solve; the separate KKT solve timer covers predictor/corrector solves. Both can include iterative refinement, which is not separately instrumented.", "",
         "All variants use fixed SOC/power cones, the same source-import objective, "
         "fixed taps, source-bus generator removal, BMOPFTools-compatible reduction and "
         "per-unit preparation. Tolerances: feasibility 1e-7, absolute gap 1e-6, relative gap 1e-7. "
         "Static regularization is 1e-7 and refinement limit 30 except `refine5`. "
         "Every solve is capped at 90 seconds. No incumbent-dependent strengthening is used.", "",
         "Objective differences use the freshly evaluated reduced-network BMOPFTools/Ipopt "
         "local solution, not a global optimum. Accepted rows require the package's publishable "
         "status. Raw values and residuals remain in the JSON, including failures.", ""]

def med(rs, key):
    vals = [r[key] for r in rs if isinstance(r.get(key), (int, float))]
    return statistics.median(vals) if vals else None

def fmt(x, digits=3):
    return "—" if x is None else f"{x:.{digits}f}"

def timer(rs, name):
    def get(r):
        t = r.get('timers', {})
        for part in name.split('/'):
            t = t.get('children', {}).get(part, {})
        return t.get('seconds')
    vals = [v for r in rs if (v := get(r)) is not None]
    return statistics.median(vals) if vals else None

for case in data['cases']:
    lines += [f"## {case['name']}", "",
              f"Buses: {case['original_buses']} → {case['reduced_buses']}. "
              f"Per-phase base: {case['s_base_VA']:.6f} VA. "
              f"Original NLP: {case.get('nlp_original', {}).get('status', 'pending')}; "
              f"reduced NLP: {case.get('nlp_reduced', {}).get('status', 'pending')}.", "",
              "| Profile | Accepted / runs | Native median s [min, max] | Iterations | KKT update s | KKT solve s | NLP − SOC W |",
              "|:--|--:|--:|--:|--:|--:|--:|"]
    for profile in data['profiles']:
        rs = [r for r in case['runs'] if r['profile'] == profile['name']]
        if not rs:
            continue
        accepted = [r for r in rs if r.get('publishable')]
        times = [r['native_solve_seconds'] for r in rs if 'native_solve_seconds' in r]
        interval = f"{fmt(statistics.median(times))} [{fmt(min(times))}, {fmt(max(times))}]" if times else "—"
        lines.append(f"| {profile['name']} | {len(accepted)}/{len(rs)} | {interval} | "
                     f"{fmt(med(rs,'iterations'),0)} | {fmt(timer(rs,'solve!/IP iteration/kkt update'))} | "
                     f"{fmt(timer(rs,'solve!/IP iteration/kkt solve'))} | {fmt(med(accepted,'nlp_minus_soc_W'))} |")
    lines += ["", "| Profile | Actual layout / basis | Moment block orders | Variables | nnz(A) | nnz(KKT L) | Extraction median s |",
              "|:--|:--|:--|--:|--:|--:|--:|"]
    for profile in data['profiles']:
        name = profile['name']
        m = case['models'].get(name)
        if not m:
            continue
        rs = [r for r in case['runs'] if r['profile'] == name]
        first = next((r for r in rs if 'linear_solver' in r), {})
        diag = m['numerics']
        orders = m['block_orders']
        shape = ', '.join(f"{n}×{orders.count(n)}" for n in sorted(set(orders)))
        lines.append(f"| {name} | {diag.get('decomposition')} / {diag.get('basis')} | {shape} | "
                     f"{m['variables']} | {first.get('A_nnz','—')} | {first.get('linear_solver',{}).get('nnzL','—')} | "
                     f"{fmt(med(rs,'extraction_seconds'))} |")
    lines += [""]
driver = 'benchmark_soc_sparse_strengthening.jl' if all(p['name'].startswith('sparse_kim') for p in data['profiles']) else 'benchmark_soc_controlled.jl'
lines += ["## Reproduction", "", "```sh",
          "JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=test/integration --startup-file=no \\",
          f"  examples/{driver} examples/results/{source.name} {data['repeats']}",
          f"python3 examples/summarize_soc_controlled.py examples/results/{source.name}",
          "```", "", f"Raw data: [{source.name}]({source.name}).",
          "Input paths/hashes, preparation changes, model layouts, internal timers, residuals, "
          "cone inventory, per-run outcomes and first-repeat reconstruction checks are in the raw data.", ""]
source.with_suffix('.md').write_text('\n'.join(lines))
