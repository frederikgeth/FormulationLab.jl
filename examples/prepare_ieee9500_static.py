"""Stage the upstream IEEE 9500 linecode variant and explicit idle batteries.

Usage: python examples/prepare_ieee9500_static.py ORIGINAL_BASE NEW_DIRECTORY
No edits are made to the source. This is a named static scenario, not a storage
model: two initially full 250 kW batteries each consume 2.5 kW idling loss.
"""
import json
from pathlib import Path
import re
import shutil
import sys

source, target = map(Path, sys.argv[1:])
if target.exists():
    raise SystemExit("Destination must not exist")
storage = (source / 'EnergyStorage.dss').read_text()
pattern = re.compile(r'New Storage\.Battery([12]) phases=3 bus1=(m2001-ESS[12]) kVA=250 kV=0\.480\s*~ kWrated=250 kWHrated=500 %reserve=30\s*~ state=charge %charge=60 PF=1 // kW=150', re.I)
assert len(pattern.findall(storage)) == 2, 'Unrecognized battery data; refusing to guess'
replacement = pattern.sub(lambda m: f'New Load.StaticBattery{m[1]} phases=3 bus1={m[2]} conn=wye kv=0.480 kw=2.5 kvar=0 model=1', storage)
shutil.copytree(source, target)
(target / 'EnergyStorage.dss').write_text(replacement)
for master in target.glob('Master-*-initial-config.dss'):
    text = master.read_text()
    for old, new in [('Redirect  LineGeometry.dss', '!Redirect  LineGeometry.dss'),
                     ('!Redirect  LineCodes.dss', 'Redirect  LineCodes.dss'),
                     ('Redirect  LinesSwitchesGeometry.dss', '!Redirect  LinesSwitchesGeometry.dss'),
                     ('!Redirect  LinesSwitchesLineCodes.dss', 'Redirect  LinesSwitchesLineCodes.dss')]:
        assert old in text, f'Missing redirect: {old}'
        text = text.replace(old, new)
    master.write_text(text)
(target / 'static-scenario.json').write_text(json.dumps({
    'source': str(source.resolve()), 'line_parameters': 'upstream linecode alternative',
    'batteries': 'initially full; fixed idle consumption 2500 W each, zero var',
    'warning': 'No storage energy states, charge schedules or controls. Constant-power idle loss is a static approximation.'
}, indent=2) + '\n')
