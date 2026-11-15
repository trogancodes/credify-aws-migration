const fs = require('fs');
const express = require('express');
const mysql = require('mysql2/promise');
const pool = mysql.createPool({
  host: process.env.MDB_HOST || 'localhost', port: +(process.env.MDB_PORT || 3306),
  database: process.env.MDB_NAME || 'credify_lms', user: process.env.MDB_USER || 'credify',
  password: process.env.MDB_PASSWORD, connectionLimit: 10,
  ssl: { ca: fs.readFileSync('/app/rds-ca.pem', 'utf8'), rejectUnauthorized: true },
});
const app = express(); app.use(express.json());
const wrap = (fn) => (req, res) => fn(req, res).catch((e) => { console.error(e.message); res.status(500).json({ error: e.message }); });

app.get('/health', wrap(async (_q, res) => { await pool.query('SELECT 1'); res.json({ status: 'ok' }); }));

app.get('/ledger/summary', wrap(async (_q, res) => {   // heavy: full scan until you add indexes
  const [rows] = await pool.query(
    `SELECT entry_type, COUNT(*) entries, SUM(amount) total FROM ledger_entries
      WHERE created_at > NOW() - INTERVAL 90 DAY GROUP BY entry_type`);
  res.json(rows);
}));

app.get('/ledger/:loanId', wrap(async (req, res) => {
  const [rows] = await pool.query('SELECT * FROM ledger_entries WHERE loan_id=? ORDER BY created_at DESC', [req.params.loanId]);
  res.json(rows);
}));

app.post('/ledger', wrap(async (req, res) => {
  const { loan_id, entry_type, amount } = req.body || {};
  if (!loan_id || !entry_type || !amount) return res.status(400).json({ error: 'loan_id, entry_type, amount required' });
  const [r] = await pool.query(
    'INSERT INTO ledger_entries(loan_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,?,NOW())',
    [loan_id, entry_type, amount, amount]);
  res.status(201).json({ id: r.insertId });
}));

const port = +(process.env.PORT || 4000);
app.listen(port, () => console.log(`credify-lms listening on ${port}`));
