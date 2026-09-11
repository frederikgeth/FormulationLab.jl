import subprocess,json,os,time
from pathlib import Path
manifest=json.load(open('examples/results/nlp_soc_panel_manifest.json'));results=[]
env=os.environ.copy()
# Run from the repository root with the optional integration environment installed.
# Finish DistributionTestCases first, then explicitly bounded large ENWL attempts.
jobs=[(c,'all') for c in manifest if c['collection']=='DistributionTestCases']+[(c,'nlp') for c in manifest[10:12]]+[(c,'linear') for c in manifest[9:12]]
for idx,(c,mode) in enumerate(jobs):
 print('START',c['name'],mode,flush=True);out=f'/tmp/bounded_case_{idx}.json';start=time.monotonic()
 with open(f'/tmp/bounded_case_{idx}.log','w') as log:
  p=subprocess.Popen(['julia','--project=test/integration','--startup-file=no','examples/benchmark_nlp_soc_worker.jl',c['path'],out,mode],env=env,stdout=log,stderr=log)
  try: p.wait(timeout=240);timeout=False
  except subprocess.TimeoutExpired: p.terminate();timeout=True
  if timeout:
   try: p.wait(timeout=15)
   except subprocess.TimeoutExpired: p.kill();p.wait()
 row=json.load(open(out)) if Path(out).exists() else {}
 row.update(name=c['name'],collection=c['collection'],wall_timeout=timeout,wall_limit_seconds=240,total_process_seconds=time.monotonic()-start,exit_code=p.returncode)
 results.append(row);json.dump(results,open('examples/results/nlp_soc_bounded_2026-09-11.json','w'))
 print('DONE',c['name'],row.get('stage'),row.get('input_error',row.get('soc_error','')),flush=True)
