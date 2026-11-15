-- CREDIFY core database (PostgreSQL) - LEGACY SCHEMA
-- Deliberately has primary keys only: no secondary indexes, no foreign keys.
-- This reproduces the customer's I/O problem. Do NOT fix it until you have run the baseline load test.
CREATE TABLE customers (
  id          BIGSERIAL PRIMARY KEY,
  full_name   TEXT NOT NULL,
  email       TEXT NOT NULL,
  phone       TEXT,
  bvn_hash    TEXT,
  state       TEXT,
  risk_score  INT,
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE loans (
  id            BIGSERIAL PRIMARY KEY,
  customer_id   BIGINT NOT NULL,
  product       TEXT NOT NULL,
  principal     NUMERIC(14,2) NOT NULL,
  interest_rate NUMERIC(5,2) NOT NULL,
  tenor_months  INT NOT NULL,
  status        TEXT NOT NULL,
  disbursed_at  TIMESTAMPTZ,
  due_date      DATE
);
CREATE TABLE repayments (
  id        BIGSERIAL PRIMARY KEY,
  loan_id   BIGINT NOT NULL,
  amount    NUMERIC(14,2) NOT NULL,
  paid_at   TIMESTAMPTZ,
  channel   TEXT,
  status    TEXT
);
