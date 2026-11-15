-- Run ONLY after your baseline load test. Then repeat the load test and compare.
-- Tip: check plans with EXPLAIN (ANALYZE, BUFFERS) before and after.
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block: run each statement on its own.
CREATE INDEX CONCURRENTLY idx_loans_customer     ON loans(customer_id);
CREATE INDEX CONCURRENTLY idx_loans_status_disb  ON loans(status, disbursed_at);
CREATE INDEX CONCURRENTLY idx_repay_loan         ON repayments(loan_id);
CREATE INDEX CONCURRENTLY idx_repay_paid_at      ON repayments(paid_at);
CREATE UNIQUE INDEX CONCURRENTLY idx_cust_email  ON customers(email);
ANALYZE;

-- Step 2: make the portfolio report cheap. Indexes alone do not fix it: the report aggregates about 1.5 million repayment rows.
-- Run each statement on its own, on the PRIMARY. A read replica receives the view automatically.
CREATE MATERIALIZED VIEW portfolio_summary AS
SELECT l.status, c.state, count(*) AS loans, sum(l.principal) AS principal, coalesce(sum(r.paid),0) AS repaid
  FROM loans l
  JOIN customers c ON c.id = l.customer_id
  LEFT JOIN (SELECT loan_id, sum(amount) AS paid FROM repayments WHERE status='SUCCESS' GROUP BY loan_id) r ON r.loan_id = l.id
 WHERE l.disbursed_at > now() - interval '365 days'
 GROUP BY l.status, c.state
WITH DATA;
CREATE UNIQUE INDEX idx_portfolio_summary ON portfolio_summary(status, state);
-- Then set PORTFOLIO_MATVIEW=true on the API. Refresh the view on the primary on a schedule, for example every 15 minutes:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY portfolio_summary;
-- Stretch ideas for your ADR: partition repayments by month, an application cache (for example ElastiCache),
-- pg_stat_statements to find the top queries, tuning shared_buffers / work_mem in the RDS parameter group.
