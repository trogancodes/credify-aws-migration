#!/usr/bin/env python3
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('baseline');p.add_argument('after');a=p.parse_args()
b=json.loads(Path(a.baseline).read_text());r=json.loads(Path(a.after).read_text())
print('Endpoint | p50 before/after | p95 before/after | errors before/after | R1')
for k in ['customer_loans','loan_repayments','loan_application','portfolio_report']:
    x,y=b[k],r[k];limit={'customer_loans':150,'portfolio_report':800}.get(k)
    status='n/a'
    if limit: status='PASS' if y['requests']>0 and y['errors']==0 and y['p95_ms']<limit else 'NOT PASSED'
    print(f"{k} | {x['p50_ms']}/{y['p50_ms']} ms | {x['p95_ms']}/{y['p95_ms']} ms | {x['errors']}/{y['errors']} | {status}")
    if x['p95_ms']>0: print(f"  p95 change: {(x['p95_ms']-y['p95_ms'])/x['p95_ms']*100:.1f}% improvement")
