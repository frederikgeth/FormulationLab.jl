from pathlib import Path
import json, zipfile, subprocess, os,signal,time,sys,shutil
# Run from the repository root; input is the previously downloaded pinned bundle.
root=Path(sys.argv[1]).resolve()
cases=[('8500_bal',root/'ieee8500/Master.dss'),('8500_unbal',root/'ieee8500/Master-unbal.dss'),('9500_bal',root/'ieee9500/base/Master-bal-initial-config.dss'),('9500_unbal',root/'ieee9500/base/Master-unbal-initial-config.dss')]
for variant in ('bal','unbal'):
 dest=Path('/tmp/ieee9500-audit')/variant;dest.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(root/f'ieee9500/ieee9500{variant}_dss.zip') as z:
  for name in z.namelist():
   assert not Path(name).is_absolute() and '..' not in Path(name).parts
  z.extractall(dest)
 cases.append((f'9500_{variant}_converted',dest/f'dss/ieee9500{variant}_base.dss'))
# Exercise the upstream-provided linecode alternative on a private copy.
linecodes=Path('/tmp/ieee9500-linecodes-audit')
shutil.copytree(root/'ieee9500/base',linecodes,dirs_exist_ok=True)
p=linecodes/'Master-unbal-initial-config.dss'
s=p.read_text().replace('Redirect  LineGeometry.dss','!Redirect  LineGeometry.dss').replace('!Redirect  LineCodes.dss','Redirect  LineCodes.dss')
s=s.replace('Redirect  LinesSwitchesGeometry.dss','!Redirect  LinesSwitchesGeometry.dss').replace('!Redirect  LinesSwitchesLineCodes.dss','Redirect  LinesSwitchesLineCodes.dss')
p.write_text(s)
cases.append(('9500_unbal_linecodes',p))
results=Path('examples/results');summary=[]
shutil.copyfile(root/'DOWNLOAD_MANIFEST.json',results/'ieee_loading_sources_2026-09-12.json')
for name,path in cases:
 row={'case':name,'path':str(path),'budget_seconds':240};summary.append(row)
 raw=results/f'ieee_loading_{name}_2026-09-12.json';log=Path('/tmp')/f'ieee_loading_{name}.log'
 print('START',name,flush=True);start=time.monotonic()
 with log.open('w') as f:
  p=subprocess.Popen(['julia','--project=test','--startup-file=no','examples/audit_large_ieee.jl',str(path),str(raw)],stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
  try:row['exit_code']=p.wait(timeout=240)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();row['process_budget_exceeded']=True
 row['wall_seconds']=time.monotonic()-start
 if raw.exists():row['stage']=json.loads(raw.read_text()).get('stage')
 (results/'ieee_loading_jobs_2026-09-12.json').write_text(json.dumps(summary,indent=2)+'\n')
 print('DONE',row,flush=True)
