const fs = require('fs');
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const cfg = (host) => ({
  host, port: +(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || 'credify_core',
  user: process.env.DB_USER || 'credify',
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { ca: fs.readFileSync('/app/rds-ca.pem', 'utf8'), rejectUnauthorized: true } : false,
  max: +(process.env.DB_POOL || 10),
});
const writePool = new Pool(cfg(process.env.DB_HOST || 'localhost'));
const readPool = process.env.READ_DB_HOST ? new Pool(cfg(process.env.READ_DB_HOST)) : writePool;

const app = express();
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());
const wrap = (fn) => (req, res) => fn(req, res).catch((e) => { console.error(e.message); res.status(500).json({ error: e.message }); });

app.get('/health', wrap(async (_req, res) => {
  await writePool.query('SELECT 1');
  res.json({ status: 'ok', readReplica: readPool !== writePool });
}));

app.get('/api/stats', wrap(async (_req, res) => {
  const { rows } = await readPool.query(
    `SELECT (SELECT count(*) FROM customers) customers, (SELECT count(*) FROM loans) loans, (SELECT count(*) FROM repayments) repayments`);
  res.json(rows[0]);
}));

app.get('/api/customers/:id', wrap(async (req, res) => {
  const { rows } = await readPool.query('SELECT * FROM customers WHERE id=$1', [req.params.id]);
  rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'not found' });
}));

app.get('/api/customers/:id/loans', wrap(async (req, res) => {
  const { rows } = await readPool.query('SELECT * FROM loans WHERE customer_id=$1 ORDER BY disbursed_at DESC', [req.params.id]);
  res.json(rows);
}));

app.get('/api/lookup', wrap(async (req, res) => {
  const { rows } = await readPool.query('SELECT id, full_name, state FROM customers WHERE email=$1', [req.query.email]);
  res.json(rows);
}));

app.get('/api/loans/:id/repayments', wrap(async (req, res) => {
  const { rows } = await readPool.query('SELECT * FROM repayments WHERE loan_id=$1 ORDER BY paid_at DESC', [req.params.id]);
  res.json(rows);
}));

// Loan application (write path). Also tells the LMS ledger service, best effort.
app.post('/api/loans', wrap(async (req, res) => {
  const { customer_id, product = 'PERSONAL', principal, tenor_months = 3 } = req.body || {};
  if (!customer_id || !principal) return res.status(400).json({ error: 'customer_id and principal required' });
  const { rows } = await writePool.query(
    `INSERT INTO loans(customer_id,product,principal,interest_rate,tenor_months,status,disbursed_at,due_date)
     VALUES($1,$2,$3,10,$4,'ACTIVE',now(), current_date + ($4::int*30)) RETURNING *`,
    [customer_id, product, principal, tenor_months]);
  if (process.env.LMS_URL) {
    fetch(`${process.env.LMS_URL}/ledger`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ loan_id: rows[0].id, entry_type: 'DISBURSEMENT', amount: principal }) }).catch(() => {});
  }
  res.status(201).json(rows[0]);
}));

// THE HEAVY QUERY: month-end style portfolio report. Scans repayments. Uses the read replica when READ_DB_HOST is set.
// Set PORTFOLIO_MATVIEW=true after you create the portfolio_summary materialised view (db/postgres/03_optimise.sql)
// to read the pre-computed result instead of scanning 1.5 million repayment rows on every call.
const HEAVY_PORTFOLIO_SQL = `SELECT l.status, c.state, count(*) AS loans, sum(l.principal) AS principal, coalesce(sum(r.paid),0) AS repaid
       FROM loans l
       JOIN customers c ON c.id = l.customer_id
       LEFT JOIN (SELECT loan_id, sum(amount) AS paid FROM repayments WHERE status='SUCCESS' GROUP BY loan_id) r ON r.loan_id = l.id
      WHERE l.disbursed_at > now() - interval '365 days'
      GROUP BY l.status, c.state
      ORDER BY principal DESC`;
const MATVIEW_PORTFOLIO_SQL = `SELECT status, state, loans, principal, repaid FROM portfolio_summary ORDER BY principal DESC`;
const portfolioSql = process.env.PORTFOLIO_MATVIEW === 'true' ? MATVIEW_PORTFOLIO_SQL : HEAVY_PORTFOLIO_SQL;
app.get('/api/reports/portfolio', wrap(async (_req, res) => {
  const { rows } = await readPool.query(portfolioSql);
  res.json(rows);
}));

const port = +(process.env.PORT || 3000);
app.listen(port, () => console.log(`credify-api listening on ${port}`));
