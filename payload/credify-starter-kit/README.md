# CREDIFY Starter Kit (fictional data, lab use only)

## Contents
- backend/api   Node.js customer API (PostgreSQL), port 3000
- backend/lms   Node.js ledger service (MariaDB), port 4000
- frontend      Static dashboard (index.html + config.js)
- db/postgres   01_schema.sql, 02_seed.sql, 03_optimise.sql
- db/mariadb    01_schema.sql, 02_seed.sql, 03_optimise.sql
- erp           Odoo docker-compose
- tools         loadtest.js
- ip-plan.csv, ip-subnets.csv   Address plan (manual section 7)

## 1. Databases (run from an instance inside your VPC, e.g. via SSM Session Manager)
    sudo dnf install -y postgresql15 mariadb105          # Amazon Linux 2023
    psql -h <core-db-endpoint> -U credify -d postgres -c "CREATE DATABASE credify_core;"
    psql -h <core-db-endpoint> -U credify -d credify_core -f db/postgres/01_schema.sql
    psql -h <core-db-endpoint> -U credify -d credify_core -f db/postgres/02_seed.sql
    mysql -h <mariadb-endpoint> -u credify -p < db/mariadb/01_schema.sql
    mysql -h <mariadb-endpoint> -u credify -p < db/mariadb/02_seed.sql
Record the row counts for your as-built document.

## 2. Back end (Node.js 20)
    cd backend/api && cp .env.example .env && npm install
    set -a; . ./.env; set +a; node server.js            # or build the Dockerfile
    cd ../lms && cp .env.example .env && npm install && set -a; . ./.env; set +a; node server.js
Test:  curl http://localhost:3000/health   and   curl http://localhost:3000/api/stats
In your final build, read passwords from Secrets Manager at start-up instead of keeping them in .env files.

## 3. Front end
Edit frontend/config.js so CREDIFY_API points to your CloudFront or load balancer URL, then serve the folder from S3
(static website behind CloudFront) or any web server. Set CORS_ORIGIN on the API to your site URL.

## 4. ERP (Odoo)
    cd erp && docker compose up -d      # browse to port 8069 through your load balancer

## 5. Baseline, tune, retest
Deploy the API behind your load balancer first: the load test needs a running API.
    node tools/loadtest.js http://<alb-dns> 20 60       # BASELINE - keep the output
    run db/postgres/03_optimise.sql (statement by statement), add a read replica (READ_DB_HOST), create the portfolio_summary
    materialised view and set PORTFOLIO_MATVIEW=true, then cache and storage tuning if your ADR justifies them
    node tools/loadtest.js http://<alb-dns> 20 60       # AFTER - compare p50/p95
Indexes alone will not bring the portfolio report under its target: it aggregates about 1.5 million repayment rows.
With PORTFOLIO_MATVIEW=true the report reads the portfolio_summary view instead. Refresh it on the primary on a schedule
(REFRESH MATERIALIZED VIEW CONCURRENTLY portfolio_summary;).
The report endpoint uses READ_DB_HOST when set, so a read replica takes that load off the primary.

## Rules
Do not store real data. Do not commit passwords. Tag every resource. Tear down when told.

## Sizes
Keep to the size ceiling in the capstone manual (Section 8.2): EC2 up to t3.medium, RDS PostgreSQL up to db.t4g.medium
(Multi-AZ only if your instructor allows it), RDS MariaDB up to db.t4g.small. Run the load test with the SAME command before and after tuning:
    node tools/loadtest.js http://<alb-dns> 20 60
Run it from an instance inside your VPC (use Session Manager, never open SSH to the internet).
