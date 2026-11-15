#!/usr/bin/env python3
from common import pg
with pg() as c:
    with c.cursor() as cur:
        cur.execute('REFRESH MATERIALIZED VIEW CONCURRENTLY portfolio_summary')
print('Student 5: portfolio_summary refreshed on primary.')
