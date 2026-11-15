#!/usr/bin/env python3
import argparse
from common import pg
p=argparse.ArgumentParser();p.add_argument('endpoint');a=p.parse_args()
with pg(application=True,host=a.endpoint) as c:
    with c.cursor() as cur:
        cur.execute('SELECT pg_is_in_recovery()')
        if cur.fetchone()[0] is not True: raise RuntimeError('Endpoint is not a PostgreSQL standby.')
        cur.execute('SELECT count(*) FROM portfolio_summary')
        n=cur.fetchone()[0]
        if n < 1: raise RuntimeError('Replica view contains no rows yet.')
        print('Student 5: replica is read-only, application login works, portfolio rows:',n)
