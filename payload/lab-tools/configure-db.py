#!/usr/bin/env python3
"""Load original untuned data and create least-privilege logins. Never logs secrets."""
import argparse
import sqlparse
from psycopg2 import sql
from common import KIT, pg, maria, secret

p = argparse.ArgumentParser()
p.add_argument('--lock-erp', action='store_true', help='After Odoo initialization, revoke CREATEDB only.')
args = p.parse_args()
if args.lock_erp:
    with pg('erpdb') as c:
        with c.cursor() as cur:
            cur.execute('ALTER ROLE credify_erp NOCREATEDB')
    print('Student 5: ERP database-creation privilege revoked.', flush=True)
    raise SystemExit(0)

print('Student 5: configuring untuned databases. Seed operations can take several minutes.', flush=True)
with pg() as c:
    with c.cursor() as cur:
        cur.execute("SELECT to_regclass('public.customers')")
        if cur.fetchone()[0] is None:
            cur.execute((KIT / 'db/postgres/01_schema.sql').read_text())
        cur.execute('SELECT count(*) FROM customers')
        n = cur.fetchone()[0]
        if n == 0:
            cur.execute((KIT / 'db/postgres/02_seed.sql').read_text())
        for table, expected in [('customers',100000),('loans',300000),('repayments',1500000)]:
            cur.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table)))
            actual = cur.fetchone()[0]
            print(f'{table}: {actual:,} (initial expected {expected:,})', flush=True)
            if actual != expected:
                raise RuntimeError('Initial seed count differs. Stop; do not reseed a benchmarked database.')
        auth = secret('api-db')
        cur.execute('SELECT 1 FROM pg_roles WHERE rolname=%s', (auth['username'],))
        if not cur.fetchone():
            cur.execute(sql.SQL('CREATE ROLE {} LOGIN').format(sql.Identifier(auth['username'])))
        cur.execute(sql.SQL('ALTER ROLE {} LOGIN PASSWORD %s').format(sql.Identifier(auth['username'])), (auth['password'],))
        cur.execute('GRANT CONNECT ON DATABASE credify_core TO credify_api')
        cur.execute('GRANT USAGE ON SCHEMA public TO credify_api')
        cur.execute('GRANT SELECT ON customers, loans, repayments TO credify_api')
        cur.execute('GRANT INSERT ON loans TO credify_api')
        cur.execute('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO credify_api')
        cur.execute('SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()')
        print('Core TLS:', cur.fetchone()[0], flush=True)

with maria() as c:
    with c.cursor() as cur:
        cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema='credify_lms' AND table_name='ledger_entries'")
        if cur.fetchone()[0] == 0:
            for stmt in sqlparse.split(sqlparse.format((KIT/'db/mariadb/01_schema.sql').read_text(), strip_comments=True)):
                if stmt.strip(): cur.execute(stmt)
        cur.execute('USE credify_lms')
        cur.execute('SELECT count(*) FROM ledger_entries')
        if cur.fetchone()[0] == 0:
            for stmt in sqlparse.split(sqlparse.format((KIT/'db/mariadb/02_seed.sql').read_text(), strip_comments=True)):
                if stmt.strip(): cur.execute(stmt)
        cur.execute('SELECT count(*) FROM ledger_entries')
        n = cur.fetchone()[0]
        print(f'ledger_entries: {n:,} (initial expected 500,000)', flush=True)
        if n != 500000:
            raise RuntimeError('Ledger seed count differs. Stop and inspect before retrying.')
        c.commit()
        auth = secret('lms-db')
        cur.execute("CREATE USER IF NOT EXISTS 'credify_lms'@'%%' IDENTIFIED BY %s REQUIRE SSL", (auth['password'],))
        cur.execute("ALTER USER 'credify_lms'@'%%' IDENTIFIED BY %s REQUIRE SSL", (auth['password'],))
        cur.execute("GRANT SELECT, INSERT ON credify_lms.* TO 'credify_lms'@'%'")
        cur.execute("SHOW STATUS LIKE 'Ssl_cipher'")
        print('MariaDB TLS:', cur.fetchone()[1], flush=True)
    c.commit()

with pg('erpdb') as c:
    with c.cursor() as cur:
        auth = secret('erp-db')
        cur.execute('SELECT 1 FROM pg_roles WHERE rolname=%s', (auth['username'],))
        if not cur.fetchone():
            cur.execute(sql.SQL('CREATE ROLE {} LOGIN').format(sql.Identifier(auth['username'])))
        cur.execute(sql.SQL('ALTER ROLE {} LOGIN CREATEDB PASSWORD %s').format(sql.Identifier(auth['username'])), (auth['password'],))
print('Done. Do not rerun after baseline. Odoo creates its own database in the browser.', flush=True)
