"""Export portable, path-free results for the simulation project report."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
read=lambda p: json.loads((root/p).read_text())
r=read('build/verification/report.json')
summary={'status':r['status'],'finished_utc':r['finished_utc'],'tools':r['tools'],
         'stages':[{'name':s['name'],'passed':s['passed']} for s in r['stages']],
         'skipped':r['skipped'],'limitations':r['limitations']}
c=read('build/campaign/report.json')
summary['campaign']={k:c[k] for k in ('seed','passed','failed')}
summary['formal_proofs']=read('build/formal/report.json')+read('build/formal_port/report.json')
summary['lint_configurations']=len(read('build/lint/report.json')) if (root/'build/lint/report.json').exists() else None
summary['cocotb']=[]
if any(s['name']=='cocotb' and s['passed'] for s in r['stages']):
 for latency in (0,1):
  tree=ET.parse(root/f'build/cocotb_{latency}.xml')
  tests=tree.findall('.//testcase')
  summary['cocotb'].append({'latency':latency,'tests':len(tests),'failures':sum(t.find('failure') is not None or t.find('error') is not None for t in tests)})
(root/'docs/results.json').write_text(json.dumps(summary,indent=2)+'\n')
