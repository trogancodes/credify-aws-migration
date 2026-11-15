#!/usr/bin/env python3
"""Explicit one-time tuning, only after saved baseline. No Terraform provisioners."""
import argparse
import json
import sqlparse
from common import pg, maria, ROOT, KIT

p=argparse.ArgumentParser()
p.add_argument('--baseline-json', required=True)
a=p.parse_args()
from pathlib import Path
baseline=Path(a.baseline_json).resolve()
if ROOT/'evidence' not in baseline.parents: raise RuntimeError('Use your saved local evidence JSON.')
data=json.loads(baseline.read_text())
for endpoint in ['customer_loans','portfolio_report']:
    if endpoint not in data or data[endpoint].get('requests',0)<1:
        raise RuntimeError('Baseline must include real samples for both R1 endpoints.')
out=ROOT/'evidence'/'tuning';out.mkdir(parents=True,exist_ok=True)
log=[]
c=pg();c.autocommit=True
try:
    with c.cursor() as cur:
        cur.execute("SELECT to_regclass('public.portfolio_summary')")
        if cur.fetchone()[0]: raise RuntimeError('View already exists; inspect previous tuning rather than blindly rerunning.')
        source=sqlparse.format((KIT/'db/postgres/03_optimise.sql').read_text(), strip_comments=True)
        for statement in sqlparse.split(source):
            if not statement.strip(): continue
            print('Running:',statement.splitlines()[0],flush=True)
            cur.execute(statement)
            log.append(cur.statusmessage)
        cur.execute('GRANT SELECT ON portfolio_summary TO credify_api')
        cur.execute('EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM loans WHERE customer_id=12345 ORDER BY disbursed_at DESC')
        (out/'plan-after.txt').write_text('\n'.join(r[0] for r in cur.fetchall())+'\n')
        cur.execute('SELECT count(*) FROM portfolio_summary')
        log.append('portfolio_summary rows: '+str(cur.fetchone()[0]))
finally: c.close()
with maria() as c:
    with c.cursor() as cur:
        source=sqlparse.format((KIT/'db/mariadb/03_optimise.sql').read_text(), strip_comments=True)
        for statement in sqlparse.split(source):
            if statement.strip():
                print('Running:',statement.splitlines()[0],flush=True)
                cur.execute(statement)
                log.append('MariaDB: '+statement.splitlines()[0])
    c.commit()
(out/'sql-results.txt').write_text('\n'.join(log)+'\n')
print('\n'.join(log),flush=True)
print('Tuning complete. Verify the view on the replica before phase tuned.',flush=True)
