"""Render the retained benchmark JSON; no solver results are recomputed."""
import json, sys
from pathlib import Path
r=json.loads(Path(sys.argv[1]).read_text())
lines=['# ENWL and DistributionTestCases: Ipopt NLP versus fixed SOC','',
'One warmed run per case/profile; one BLAS thread; 90-second solver limits. Build time is separate from solve time. Times are wall seconds and include profile-specific work in the corresponding stage. No iterative cuts are used.','',
'ENWL selection: 12 evenly spaced ranks by bus count among 128 reduced feeders (ties sorted by filename). DistributionTestCases selection: modified IEEE 13/34/123, CIGRE, and LV snapshots t500/t1000. Source-bus generators are removed. Other dispatch remains available; taps are fixed and control laws are omitted. Both engines minimize source active-power import. Input preparation uses BMOPFTools parsing/migration, and DSS conversion uses its PowerIO-backed importer. Input files are unchanged.','',
'BMOPFTools uses transformer `s_rating` as an operating limit; FormulationLab treats it as a base quantity. Consequently transformer-case gaps are not clean measurements of relaxation strength alone. Voltage-dependent load laws are retained, not converted to constant power.','',
'Gaps below use Ipopt source import minus the SOC numerical primal objective, in watts. They are not certified optimality gaps: Ipopt provides a local candidate, SOC dual bounds are numerical, and mismatched constraints or validation findings can invalidate an interpretation as relaxation error. Negative imports denote export. Failed or nearly optimal SOC runs are not accepted as bounds.','',
'| Case | Buses | NLP status | NLP build / solve s | SOC profile | SOC status | SOC build / solve s | NLP − SOC W |',
'|---|---:|---|---:|---|---|---:|---:|']
fmt=lambda x: '—' if x is None else f'{x:.4g}'
for c in r['cases']:
 n=c.get('nlp',{}); ns=n.get('status','input/build error')
 ss=c.get('soc',[]) or [dict(variant='linear',termination='BUDGET' if str(c.get('soc_error','')).startswith('External') else 'ERROR')]
 for s in ss:
  good=ns in ('LOCALLY_SOLVED','OPTIMAL') and s.get('termination')=='OPTIMAL'
  gap=n.get('source_W',0)-s['objective_W'] if good and s.get('objective_W') is not None else None
  lines.append(f"| {c['name']} | {c.get('buses','—')} | {ns} | {fmt(n.get('build_seconds'))} / {fmt(n.get('solve_seconds'))} | {s.get('variant','—')} | {s.get('termination','error')} | {fmt(s.get('build_seconds'))} / {fmt(s.get('solve_seconds'))} | {fmt(gap)} |")
lines += ['', '## Validation and failures','']
for c in r['cases']:
 notes=[]
 for key in ('input_error','nlp_error','soc_error'):
  if key in c: notes.append(key+': '+c[key])
 for s in c.get('soc',[]):
  if 'error' in s: notes.append('SOC '+s['variant']+': '+s['error'])
 n=c.get('nlp',{})
 if n:
  counts={}
  for f in n.get('findings',[]):
   if f['severity']!='INFO': counts[f['code']]=counts.get(f['code'],0)+1
  notes.append('NLP maximum model residual: '+fmt(n.get('max_model_residual'))+'; independent BMOPFTools finding counts: '+str(counts))
 if notes: lines.append('- **'+c['name']+'**: '+'; '.join(notes))
lines += ['', 'Raw JSON retains exact statuses, numerical solver bounds, parser provenance, all findings, input hashes, per-unit bases, model sizes, strengthening counts and compilation/solve timings. The SOC `max_scaled_violation` field uses MOI’s distance upper bound; it is not the geometric rotated-cone distance used by the newer containment audit.','']
root=Path(sys.argv[1]).parent
probe=root/'soc_tolerance_probe_2026-09-11.json'
if probe.exists():
 lines += ['', '## Stopping-tolerance experiment', '',
  'Same default SOC constraints; `tol_feas=1e-7`, `tol_gap_abs=1e-6`, `tol_gap_rel=1e-7`. No incumbent-dependent strengthening. Geometric residuals replace MOI’s rotated-cone distance upper bound with the Euclidean SOC distance.', '',
  '| Case | Status | Build / solve s | Geometric violation | NLP − SOC W |', '|---|---|---:|---:|---:|']
 for c in json.loads(probe.read_text()):
  lines.append(f"| {c['name']} | {c.get('status','ERROR')} | {fmt(c.get('build_seconds'))} / {fmt(c.get('solve_seconds'))} | {fmt(c.get('geometric_constraint_violation'))} | {fmt(c.get('nlp_minus_soc_W'))} |")
lines += ['', '## Controlled import and nameplate diagnostics', '',
 'These are explicitly modified inputs. They must not replace or be counted as successes for the original-input panel. Removing `s_rating` disables BMOPFTools nameplate caps; it is not a certified general transformation of every transformer representation.']
for stem in ('ieee13_impedance_repair','cigre_no_nameplate_caps','ieee34_no_nameplate_caps'):
 p=root/(stem+'_2026-09-11.json')
 if not p.exists():continue
 c=json.loads(p.read_text());n=c.get('nlp',{});ss=c.get('soc',[])
 lines += ['', '**'+stem+'**: '+c.get('repair','')]
 lines.append('NLP: '+n.get('status',c.get('nlp_error','not completed'))+'; source import '+fmt(n.get('source_W'))+' W.')
 for x in ss:
  lines.append('SOC: '+x.get('termination','unknown')+'; source import '+fmt(x.get('objective_W'))+' W.')
 if 'soc_error' in c:lines.append('SOC: '+c['soc_error'])
lines += ['', '## Implications', '',
 '- Ipopt is the stronger speed/reliability baseline on the sampled ENWL feeders and the two LV snapshots. These local feasible solutions do not establish global optimality.',
 '- Prioritize SOC construction profiling and numerical reliability before adding more strengthening. Fixed Kim cuts improve some converged bounds but are not uniformly reliable or economical on this panel.',
 '- Relaxing stopping tolerances rescues some cases, but residuals and numerical dual bounds still require inspection. It does not cure construction scaling.',
 '- Imported IEEE/CIGRE outcomes must be interpreted with parser diagnostics and the transformer rating contract. They are not evidence that the unchanged original DSS circuit is infeasible.', '']
Path(sys.argv[2]).write_text('\n'.join(lines))
