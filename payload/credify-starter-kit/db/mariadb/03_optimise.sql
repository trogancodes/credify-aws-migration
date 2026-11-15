USE credify_lms;
CREATE INDEX idx_ledger_loan ON ledger_entries(loan_id, created_at);
CREATE INDEX idx_ledger_created ON ledger_entries(created_at);
ANALYZE TABLE ledger_entries;
