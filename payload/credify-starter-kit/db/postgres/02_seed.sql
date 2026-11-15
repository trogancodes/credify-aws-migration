-- Fictional data. 100k customers, 300k loans, 1.5M repayments (about 250 MB).
-- Run: psql -h <host> -U credify -d credify_core -f 02_seed.sql   (takes a few minutes on a small instance)
INSERT INTO customers(full_name,email,phone,bvn_hash,state,risk_score,created_at)
SELECT 'Customer '||g,
       'customer'||g||'@example.test',
       '23480'||lpad(((random()*99999999)::int)::text,8,'0'),
       md5(g::text),
       (ARRAY['Lagos','Abuja','Kano','Rivers','Oyo','Kaduna','Enugu','Delta','Anambra','Ogun'])[1+(g%10)],
       300+(random()*550)::int,
       now()-make_interval(days => (random()*900)::int)
FROM generate_series(1,100000) g;

INSERT INTO loans(customer_id,product,principal,interest_rate,tenor_months,status,disbursed_at,due_date)
SELECT 1+(random()*99999)::bigint,
       (ARRAY['PERSONAL','SME','SALARY_ADVANCE'])[1+(g%3)],
       round((10000+random()*990000)::numeric,2),
       (ARRAY[5,7.5,10,15])[1+(g%4)],
       (ARRAY[1,3,6,12])[1+(g%4)],
       (ARRAY['ACTIVE','ACTIVE','PAID','OVERDUE','DEFAULTED'])[1+(g%5)],
       now()-make_interval(days => (random()*720)::int),
       current_date + ((random()*365)::int - 180)
FROM generate_series(1,300000) g;

INSERT INTO repayments(loan_id,amount,paid_at,channel,status)
SELECT 1+(random()*299999)::bigint,
       round((1000+random()*80000)::numeric,2),
       now()-make_interval(days => (random()*720)::int),
       (ARRAY['CARD','BANK_TRANSFER','USSD','WALLET'])[1+(g%4)],
       (ARRAY['SUCCESS','SUCCESS','SUCCESS','FAILED'])[1+(g%4)]
FROM generate_series(1,1500000) g;

ANALYZE;
SELECT 'customers' t, count(*) FROM customers UNION ALL
SELECT 'loans', count(*) FROM loans UNION ALL
SELECT 'repayments', count(*) FROM repayments;
