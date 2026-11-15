USE credify_lms;
-- Newer MariaDB versions cap recursive queries (default 1000 iterations) and silently return a partial result. Lift the cap for this session.
SET SESSION max_recursive_iterations = 1000000;
-- 500k fictional ledger entries. If your engine version rejects INSERT ... WITH, wrap the CTE as a derived table.
INSERT INTO ledger_entries(loan_id,entry_type,amount,balance_after,created_at)
WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<500000)
SELECT 1+FLOOR(RAND()*300000),
       ELT(1+(n%3),'DISBURSEMENT','REPAYMENT','FEE'),
       ROUND(1000+RAND()*80000,2),
       ROUND(RAND()*500000,2),
       NOW() - INTERVAL FLOOR(RAND()*720) DAY
FROM s;
SELECT COUNT(*) AS ledger_rows FROM ledger_entries;
