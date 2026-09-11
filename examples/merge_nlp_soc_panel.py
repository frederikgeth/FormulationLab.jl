import json
from pathlib import Path
root=Path('examples/results')
r=json.loads((root/'nlp_soc_panel_2026-09-11.json').read_text())
rows={c['name']:c for c in r['cases']}
for c in json.loads((root/'nlp_soc_bounded_2026-09-11.json').read_text()):
 d=rows.setdefault(c['name'],dict(name=c['name'],collection=c['collection'],path=c['path']))
 d.setdefault('bounded_attempts',[]).append({k:c.get(k) for k in ('mode','stage','wall_timeout','wall_limit_seconds','total_process_seconds','timing_note')})
 for key in ('buses','s_base_VA','changes','parse_seconds','parser_provenance','load_models','transformer_families','nlp','nlp_error','input_error','soc','soc_error'):
  if key in c:d[key]=c[key]
 if c['wall_timeout'] and not c.get('soc') and c['mode']!='nlp':
  d['soc_error']='External 240 s process budget reached in stage '+c.get('stage','unknown')+' (includes startup/warm-up); no completed SOC result.'
manifest=json.loads((root/'nlp_soc_panel_manifest.json').read_text())
r['cases']=[rows[c['name']] for c in manifest if c['name'] in rows]
r['dataset_revisions']={'BMOPFDraftData':'e2601a2db7fbdea075c2cbb08ff00a759d734402','DistributionTestCases':'d7177256cfac4925a7b97223a167fba654cffe6f'}
r['PowerIO_julia_version']='0.11.0'
(root/'nlp_soc_combined_2026-09-11.json').write_text(json.dumps(r))
