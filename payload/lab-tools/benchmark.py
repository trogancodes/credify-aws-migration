#!/usr/bin/env python3
import argparse
import datetime
import json
import subprocess
import urllib.request
from common import CONFIG, ROOT, KIT, pg

p=argparse.ArgumentParser()
p.add_argument('label', choices=['baseline','after'])
a=p.parse_args()
url='http://' + CONFIG['alb_dns']
with urllib.request.urlopen(url+'/health', timeout=20) as r:
    health=json.load(r)
if bool(health.get('readReplica')) != (a.label=='after'):
    raise RuntimeError('Running API replica configuration does not match this benchmark phase.')
if a.label=='baseline':
    with pg() as c:
        with c.cursor() as cur:
            cur.execute("SELECT indexname FROM pg_indexes WHERE schemaname='public' AND indexname NOT LIKE '%_pkey'")
            if cur.fetchall(): raise RuntimeError('Secondary indexes exist: cannot record an untuned baseline.')
            cur.execute("SELECT to_regclass('public.portfolio_summary')")
            if cur.fetchone()[0]: raise RuntimeError('Materialised view already exists before baseline.')
            cur.execute('EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM loans WHERE customer_id=12345 ORDER BY disbursed_at DESC')
            plan='\n'.join(row[0] for row in cur.fetchall())
else:
    plan='See tuning/plan-after.txt and the SQL evidence.'
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
out=ROOT/'evidence'/a.label/stamp
out.mkdir(parents=True)
(out/'query-plan.txt').write_text(plan+'\n')
(out/'context.json').write_text(json.dumps({'name':CONFIG['name'], 'url':url, 'health':health,'label':a.label,'time_utc':stamp}, indent=2))
command=['node',str(KIT/'tools/loadtest.js'),url,'20','60']
print('Student 5 |',a.label,'|', ' '.join(command), flush=True)
# Identical original loadtest.js. No changes to its workload or percentiles.
with (out/'console.txt').open('w') as log:
    process=subprocess.Popen(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    for line in process.stdout:
        print(line,end='',flush=True);log.write(line);log.flush()
    if process.wait(): raise RuntimeError('Load test process failed; preserve its output.')
print('Evidence saved:',out,flush=True)
