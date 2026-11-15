# Credify production lab with Terraform

**For Chiedozie Maduabuchi, Student 5, Group A.** This is a production-only lab build in Cape Town (`af-south-1`), inside `10.105.0.0/16`. It follows the supplied manual's lab ceilings, not the ADR's production sizes. Nothing in this package has been applied to your AWS account.

Use this README as the Terraform implementation guide. The earlier Word guide remains useful for concepts and screenshot requirements, but **do not create the same infrastructure manually as well**. Terraform owns the infrastructure in this package.

## 1 Before you start

**If you already have a Terraform deployment:** this package is a separate clean-build project, not an in-place update of unseen Terraform code. In your existing project run:

```powershell
terraform state list
terraform state list | Select-String -Pattern 'aws_vpc|aws_db_instance|aws_db_subnet_group|aws_ecs_service|aws_iam_role'
```

Do not run this new project's `apply` beside an existing Credify deployment. Resource names may collide and a second VPC/NAT/database estate would duplicate spend. To adapt an existing project, compare its `.tf` files, redacted variable values and the **resource address list**, then reconcile/import deliberately. Do not share `terraform.tfstate`, binary saved plans, passwords or access keys. Do not delete an existing state file to get past an error.

**If this is a clean build:** extract the ZIP into a new local folder, such as `C:\Labs\credify-terraform-prod`. Avoid shared or automatically synced folders for Terraform state. Open PowerShell in that folder.

The manual (section 8.1, page 12) says to confirm instance classes, Multi-AZ and NAT use with the instructor before starting. This kit uses **Single-AZ RDS and one NAT**. The `instructor_settings_confirmed` variable starts false and blocks the plan until that confirmation is recorded. It does not infer approval from the ADR or from a previous preference for Multi-AZ. No database sharing approval is assumed: ERP has its own small PostgreSQL instance.

## 2 What Terraform creates

| Component | Configuration |
|---|---|
| Network | One student VPC, seven subnets across two AZs, internet gateway, one NAT/EIP, S3 gateway endpoint |
| Data routes | Local VPC route only; no internet default route |
| Core PostgreSQL | `db.t4g.medium`, 50 GiB gp3, PostgreSQL 16, Single-AZ, private |
| ERP PostgreSQL | `db.t4g.small`, 20 GiB gp3, PostgreSQL 16, Single-AZ, private |
| LMS MariaDB | `db.t4g.small`, 20 GiB gp3, MariaDB 10.11, Single-AZ, private |
| Reporting replica | One `db.t4g.medium`, 50 GiB gp3, only after the baseline |
| ECS Fargate | API 0.5 vCPU/1 GiB; LMS 0.5 vCPU/1 GiB; Odoo 1 vCPU/2 GiB |
| Task counts | One per service; API/LMS replacement surge capped at two; Odoo stop/start at one |
| Test/admin instance | One private AL2023 `t3.small`, encrypted 16 GiB root volume, SSM, no SSH |
| Storage | One private versioned S3 bucket with separate prefixes; encrypted small Odoo EFS filestore |
| Edge | ALB and CloudFront default HTTPS address; no domain required |
| Security | Separate SGs and roles, Secrets Manager, verified DB TLS, optional budget-approved WAF |
| Operations | CloudWatch logs, dashboard, three required alarms, one regional management-events CloudTrail trail |

There is no dev, staging, DR VPC, cross-region replica, Redis, extra ERP/MariaDB replica, RDS Proxy, production storage performance, Reserved Instance or Savings Plan. Storage autoscaling is disabled. EFS automatic backups are explicitly disabled in this basic lab; document that limitation and add only an instructor-approved backup policy if required. RDS has one-day automated backups and S3 versioning.

Two-AZ subnets are not a claim of full HA. One task per service, Single-AZ databases and a single NAT cannot demonstrate the production R2 target. This lab does not prove regional RTO/RPO. WAF is off by default under the manual's budget exception. Its enable flag creates only a CloudFront-scope ACL in `us-east-1`, not a DR environment.

## 3 How Terraform works

Terraform reads the `.tf` files and your variable values, builds a dependency graph, and compares the desired infrastructure with its **state**. `plan` shows the proposed changes; `apply` executes them. A later apply updates the same managed resources when you use the same directory/backend/state. Do not create a fresh state for each phase.

Terraform provisions AWS infrastructure. The supplied scripts load SQL, initialise application database logins, build container images and run benchmarks. They are explicit steps rather than hidden Terraform `local-exec` provisioners, so an ordinary infrastructure update cannot unexpectedly reseed a database or invalidate your baseline.

| Phase | What changes | Prerequisite |
|---|---|---|
| `foundation` | Creates network, RDS primaries, secrets, ECR, management host, EFS, edge and monitoring. No ECS services yet. | Instructor confirmation and correct account |
| `baseline` | Starts API, LMS and ERP using ECR image digests. No read replica; materialised view disabled. | Databases seeded and images pushed |
| `replica` | Adds the core read replica. API remains on primary with the heavy report. | Baseline saved and acknowledged |
| `tuned` | Routes API reads to replica and enables the precomputed portfolio view. | SQL tuning completed and replica query verified |

Do not move backward from `tuned` to `foundation`: Terraform would plan to remove services and the replica. A flag is an acknowledgement, not proof that a task happened; keep the actual evidence.

## 4 Tools and credential check on Windows

Use **PowerShell locally**, not Bash. Start Docker Desktop in Linux-container mode. You need Terraform 1.11 or newer (below 2.0), AWS CLI v2 and Docker. The kit pins the AWS provider to 6.20.0 and includes a provider lock file. Do not upgrade providers midway through the lab.

If Terraform is missing, this installs it using the winget community source:

```powershell
winget install --id Hashicorp.Terraform -e --source winget
```

Reopen PowerShell after installation. Configure your instructor-approved AWS credentials or IAM Identity Center profile. Do not use root-user access keys.

```powershell
terraform version
aws --version
docker version
aws configure list-profiles
$env:AWS_PROFILE = "default"
$env:AWS_REGION = "af-south-1"
$env:AWS_DEFAULT_REGION = "af-south-1"
aws sts get-caller-identity
```

Use your actual existing profile instead of `default` if different. This code does not hardcode `credify-lab`. For an SSO profile, use `aws sso login --profile <your-profile>` first. Check that the account ID is the instructor's lab account and Cape Town is enabled.

## 5 Configure and review foundation

From the extracted project root:

```powershell
Copy-Item .\terraform\terraform.tfvars.example .\terraform\terraform.tfvars
notepad .\terraform\terraform.tfvars
```

Replace `aws_account_id` and `owner`. Keep `phase = "foundation"`. Only after the instructor confirms the proposed settings, set `instructor_settings_confirmed = true`. Leave other phase acknowledgement flags false. Leave `allow_lab_data_deletion = false`.

Run the read-only regional availability check, then initialise and review:

```powershell
.\scripts\Test-Prerequisites.ps1
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
terraform -chdir=terraform plan -out=foundation.tfplan
```

`terraform test` uses mocked providers and does not create AWS resources. The real `plan` uses your credentials and checks account/region access. Check the plan against the resource table above: three small primary databases, no read replica, no ECS service, one NAT, no Multi-AZ and no unexpected replacement of an existing estate. A plan's total resource count includes IAM rules, routes and other small objects; it is not the number of billable servers.

Apply the reviewed plan:

```powershell
terraform -chdir=terraform apply foundation.tfplan
terraform -chdir=terraform output
```

Provisioning RDS and CloudFront can take time. Do not launch a second apply in another terminal. If a supported class/version is unavailable or IAM is denied, stop at that resource and resolve the account restriction with the instructor. Do not choose a larger replacement.

### State and passwords

This implementation generates passwords with Terraform and writes ordinary Secrets Manager secrets. Those generated values are also present in Terraform state and saved plan files. `sensitive` display masking is not encryption. Keep the working directory on protected local storage, restrict access, back it up securely, and never commit or upload `.tfstate`, `.tfplan` or real `.tfvars` files.

Core uses ordinary Secrets Manager storage, not RDS-managed master credentials, because the latter blocks creation of its read replica. Application tasks receive only their own application login secrets; the RDS master passwords are used only by the management scripts.

The default local backend is for one person's lab. If your instructor supplies an existing encrypted/versioned state bucket, use `docs/backend-existing-s3.tf.example` as explained in that file, with native S3 locking. Do not store state inside the application bucket managed by the same state, and do not create an unapproved second bucket just to follow an example.

## 6 Connect to management and load the starter data

Terraform output `management_instance_id` identifies the EC2 instance. Open AWS EC2 → Instances → select it → Connect → Session Manager. No public IP and no SSH port are needed.

The following commands run in **Bash inside Session Manager**, not PowerShell:

```bash
bash
sudo cloud-init status --wait
sudo test -f /opt/credify/bootstrap-complete && echo 'Management tools ready'
node --version
```

If the ready marker is missing, inspect `sudo tail -n 80 /var/log/cloud-init-output.log`. Fix package/network errors before proceeding; do not assume a ready SSM agent means user data completed successfully.

In your **local PowerShell**, print the download instructions:

```powershell
terraform -chdir=terraform output -raw download_payload_commands
```

Copy those commands into the management Bash shell. They download the kit and a configuration file containing endpoints and secret ARNs, **not secret values**. Then:

```bash
cd ~/credify-work
mkdir -p evidence/setup
set -o pipefail
/opt/credify-venv/bin/python lab-tools/configure-db.py | tee evidence/setup/database-load.txt
```

The script loads the original untuned schema/data, creates separate restricted API/LMS users, gives the ERP user temporary database-creation privilege, and checks TLS. It gets passwords from Secrets Manager through the EC2 role without printing them.

Expected initial counts: **100,000 customers; 300,000 loans; 1,500,000 repayments; 500,000 ledger entries.** Save the output and screenshots. The script will stop at unexpected counts rather than silently append more data. Do not run `03_optimise.sql` yet. Do not rerun setup after the baseline has added loans.

## 7 Build the container images locally

Return to **local PowerShell** at the project root:

```powershell
.\scripts\Build-Images.ps1
```

If Windows blocks scripts under your approved workstation policy, review the script and use an allowed per-process policy rather than changing the machine policy permanently. The script downloads the current RDS CA bundle, builds Linux/x86_64 images on your computer, and pushes all three images to the ECR repositories Terraform created. It does not host applications on EC2.

It prints the actual Odoo UID and GID. Put those numbers in `terraform.tfvars` before starting ECS. The example uses 101/101 only as initial values; the built image is authoritative. EFS uses this identity for the Odoo filestore. No mount occurs before the ERP service starts.

ECR tags are immutable. If an interrupted run already pushed some images, rerun `Build-Images.ps1 -SkipExisting` to retain those successful images. Do not rebuild different application code between baseline and retest. If you deliberately need a new image for a separate experiment, use a new tag and record the change.

## 8 Start the three applications

Edit `terraform.tfvars`: set `phase = "baseline"`, keep `baseline_recorded = false` and `tuning_completed = false`. Set the observed Odoo UID/GID.

```powershell
terraform -chdir=terraform plan -out=baseline.tfplan
terraform -chdir=terraform apply baseline.tfplan
terraform -chdir=terraform output -raw cloudfront_url
```

Terraform resolves each immutable ECR tag to a digest. ECS tasks run privately on Fargate; the ALB registers task IPs. LMS uses private DNS `lms.credify-5-prod.internal`. One old API/LMS task plus one replacement fits the limit of two tasks; Odoo uses stop/start to avoid two concurrent Odoo processes during updates. Autoscaling is intentionally absent during measurement.

Wait for ECS services to stabilise. If apply reports a service failure, inspect its Events and CloudWatch log group; fix the dependency and rerun a reviewed plan. Do not keep launching manual extra tasks.

### Why there is CloudFront and HTTP on the ALB

Manual 8.3 allows the default CloudFront HTTPS address when you do not own a domain. The ALB origin listens on HTTP 80; its SG permits CloudFront origin addresses and the test-instance SG only. Browser API requests use the same HTTPS origin to avoid mixed content. This is the lab exception, not full production TLS on every hop. The CloudFront prefix list identifies CloudFront generally, not only your distribution.

In the management Bash shell:

```bash
cd ~/credify-work
/opt/credify-venv/bin/python lab-tools/private-alb.py
ALB_DNS=$(jq -r .alb_dns lab-config.json)
curl -fsS "http://$ALB_DNS/health"
curl -fsS "http://$ALB_DNS/api/stats"
curl -fsS http://lms.credify-5-prod.internal:4000/health
```

`private-alb.py` resolves the ALB's current private ENI address locally on the test host. This avoids sending the test through NAT, where a source-SG rule would no longer match. It preserves the manual's `http://<alb-dns>` test URL and does not open ingress to everyone. ALB node addresses can change: rerun it before both tests. This is a documented short-lab workaround, not production DNS design.

Open the CloudFront URL in your browser. Click **Check API**, **Row counts** and **Load loans**. The page does not automatically fetch data. API health should show `readReplica: false`. Save your own screenshots.

## 9 Initialise Odoo and disable database management

```powershell
terraform -chdir=terraform output -raw odoo_setup_url
terraform -chdir=terraform output -raw odoo_master_secret_arn
```

In the Secrets Manager console, privately retrieve the `password` key of that Odoo master secret. Do not screenshot its value. Open the setup URL, create database **credify_erp**, choose your own web administrator email/password and disable demo data. The Odoo master password, the SQL database password and the web user's password are three different credentials.

After successful login, in management Bash:

```bash
/opt/credify-venv/bin/python ~/credify-work/lab-tools/configure-db.py --lock-erp
```

Then locally set `odoo_initialized = true` in `terraform.tfvars` and run a new reviewed plan/apply while staying in `baseline`. This hides Odoo's database manager. Expect a brief ERP restart. Verify `/web/login` still works and data survives; EFS preserves `/var/lib/odoo` while RDS preserves relational data.

The original Compose file is retained as a reference but is **not deployed**: its bundled PostgreSQL container and sample passwords are not used. The kit does not implement real API-to-Odoo integration or a document-upload API. The API posts best-effort notifications directly to LMS. The S3 example document is provisioned independently.

## 10 Save the baseline before tuning

On management Bash, ensure no deployment or other test is running:

```bash
cd ~/credify-work
/opt/credify-venv/bin/python lab-tools/private-alb.py
/opt/credify-venv/bin/python lab-tools/benchmark.py baseline
```

The wrapper checks that there are no secondary indexes/materialised view, captures a pre-tuning query plan, then runs the **unchanged** starter command: `node tools/loadtest.js http://<alb-dns> 20 60`. It saves a timestamped evidence folder with the JSON, console output and context. The URL and workload are identical in the after-test.

Keep full output, errors and sample counts. The script may finish later than 60 seconds because its in-flight requests have no explicit timeout; throughput still divides by the nominal 60. The workload inserts loans, so row counts change. Do not reseed to force them back. Zero samples or fast error responses do not demonstrate a passing endpoint.

## 11 Create the replica, then tune the primary

Locally set `phase = "replica"` and `baseline_recorded = true`. Keep `tuning_completed = false`. Review/apply:

```powershell
terraform -chdir=terraform plan -out=replica.tfplan
terraform -chdir=terraform apply replica.tfplan
terraform -chdir=terraform output -raw core_replica_endpoint
```

The API still uses the primary and the heavy query. Only one same-region core reporting replica is added. It is not a Multi-AZ standby or a DR replica.

On management Bash, choose the exact baseline JSON path printed by the benchmark (replace the placeholder):

```bash
cd ~/credify-work
set -o pipefail
/opt/credify-venv/bin/python lab-tools/tune.py --baseline-json evidence/baseline/<timestamp>/<loadtest-file>.json | tee evidence/tuning-console.txt
/opt/credify-venv/bin/python lab-tools/verify-replica.py '<replica-endpoint-from-terraform>'
```

`tune.py` uses the supplied optimisation SQL, one statement at a time; PostgreSQL autocommit permits `CREATE INDEX CONCURRENTLY`. It creates indexes, the portfolio materialised view and its unique index, grants the API access, and applies MariaDB indexes. It saves the post-tuning query plan. Do not blindly rerun after a partial failure: inspect which statements succeeded first.

`verify-replica.py` uses the API database login to confirm it is a standby and that the materialised view contains rows. Wait for replication if it is not ready. A materialised view avoids re-aggregating 1.5 million repayments per request; the replica separates reads from writes. Indexes improve lookups. These solve different parts of the problem.

## 12 Enable tuned routing and retest

Locally set `phase = "tuned"` and `tuning_completed = true`, leaving `baseline_recorded = true`. Review/apply:

```powershell
terraform -chdir=terraform plan -out=tuned.tfplan
terraform -chdir=terraform apply tuned.tfplan
```

This sets `READ_DB_HOST` to the replica and `PORTFOLIO_MATVIEW=true`; `DB_HOST` remains the primary. The starter API routes **all reads**, not just the report, to the replica. Writes remain on primary. Replica lag can briefly produce stale reads.

On management Bash:

```bash
cd ~/credify-work
/opt/credify-venv/bin/python lab-tools/private-alb.py
/opt/credify-venv/bin/python lab-tools/refresh-view.py
# Wait for low replica lag; then verify again before the timed run.
/opt/credify-venv/bin/python lab-tools/verify-replica.py '<replica-endpoint>'
/opt/credify-venv/bin/python lab-tools/benchmark.py after
/opt/credify-venv/bin/python lab-tools/compare.py evidence/baseline/<timestamp>/<file>.json evidence/after/<timestamp>/<file>.json
```

R1 requires portfolio p95 **below 800 ms** and customer-loans p95 **below 150 ms**. Record p50/p95 for all four endpoints, sample counts and errors. The compare script does not call a test successful if the measured endpoint returned errors. No AWS resource sizing or test concurrency is changed to force a pass.

For scheduled report freshness, add a same-user cron entry after the tests, using `crontab -e`:

```text
*/15 * * * * /usr/bin/flock -n /tmp/credify-5-refresh.lock /opt/credify-venv/bin/python $HOME/credify-work/lab-tools/refresh-view.py >> $HOME/credify-work/evidence/refresh.log 2>&1
```

The script fetches credentials at runtime. It requires the management instance to remain running. Report freshness is roughly 15 minutes plus lag. Pause cron during any later timed comparisons, refresh once beforehand and document the test procedure.

## 13 Evidence, monitoring and submission

Terraform creates the dashboard `credify-5-prod` and three alarms: core CPU >80% for three minutes; core free storage <5 GiB for three minutes; API target 5xx >=1 in a minute. Alarm thresholds are selected lab values, not values mandated by the manual. The alarms are visible in CloudWatch; **no email notification subscription is created**. Add your own approved notification action if required.

Collect evidence under the manual's headings: **Network; Security; Databases; Back ends; Load balancer; Front end; ERP; Baseline; Tuning; Retest; Monitoring.** Include all three primaries and the replica once present. Show real statuses and results, names with student 5, the eight lab tags, no public DB access and the Session Manager connection. Do not paste secret values.

The CloudTrail trail records management actions into `audit/` in the same bucket; it does not log S3 object data events. RDS retention is one day; show successful backups/latest restorable time. S3 document lifecycle covers only `documents/`, not frontend or evidence. Small objects may not transition due to S3's default minimum-size rule. No DR recovery test or EFS backup success is claimed.

Save your evidence off the instance before teardown. In management Bash:

```bash
cd ~/credify-work
LAB_BUCKET=$(jq -r .bucket lab-config.json)
aws s3 cp evidence/ "s3://$LAB_BUCKET/evidence/" --recursive --region af-south-1
```

Locally:

```powershell
.\scripts\Download-Evidence.ps1
```

End `5_Deployment.docx` or `5_Deployment.pdf` with a final overview showing the live dashboard, healthy ALB targets, database statuses, Odoo login and before/after results. Describe lab reductions from the ADR honestly. The supplied schedule says build/baseline 2 November, submission 4 November, teardown 5 November 2026, Lagos time; newer instructor instructions take precedence.

## 14 Teardown only when instructed

Export and open your evidence first. Remove the view-refresh cron job. The code defaults to RDS deletion protection, non-empty S3/ECR deletion prevention and a seven-day Secrets Manager recovery window.

At the instructed teardown time, keep your last phase values, set `allow_lab_data_deletion = true`, and review/apply that change. It removes RDS deletion protection and allows Terraform to empty **this lab's** versioned S3 bucket and ECR repositories. RDS is configured to skip final snapshots and delete automated backups on destroy; if the instructor requires retention, take the approved snapshots first and track their ongoing charges.

```powershell
terraform -chdir=terraform plan -out=allow-cleanup.tfplan
terraform -chdir=terraform apply allow-cleanup.tfplan
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

Review the destroy plan: it must contain only this project's resources. Terraform removes services, load balancer, databases, EFS, NAT/EIP, network and other resources according to dependencies. CloudFront deletion and database deletion can take time. If deletion is blocked, resolve the exact dependency; do not delete the state or unrelated shared resources.

Check residual snapshots, backup vaults, scheduled secrets and billing after reporting catches up. The local state/backend itself is not automatically deleted. Secrets in the recovery window prevent recreating the same names immediately; restore them or wait according to the account policy instead of force-deleting them casually.

## 15 Troubleshooting

| Problem | First check |
|---|---|
| `grep` or `sls -E` errors | In PowerShell use `Select-String -Pattern '...'`; there is no `-E` needed. |
| Profile `credify-lab` missing | Use an existing authorized profile via `$env:AWS_PROFILE`; provider does not hardcode one. |
| Instructor guardrail fails | Confirm the documented settings; only then set the acknowledgement true. |
| Wrong account blocked | Check `aws sts get-caller-identity` and `aws_account_id`. |
| RDS class/engine not offered | Confirm orderable options in Cape Town with the instructor; do not upsize. |
| RDS read replica cannot be created | Source uses ordinary self-managed credentials, backup retention >0 and source Available. |
| ECR image not found | Finish foundation, push all images, then change phase to baseline. |
| Immutable tag already exists | Keep existing experiment images with `Build-Images.ps1 -SkipExisting`. |
| Task cannot start | ECS Events; ECR digest/architecture; execution role; secret ARN; NAT routes. |
| Odoo permissions | Actual UID/GID must match EFS access point; NFS SG and task EFS policy. |
| Odoo cannot create DB | Complete configure-db first; do not lock ERP before browser initialization. |
| Management tools missing | Inspect cloud-init log and ready marker; SSM connectivity alone is insufficient. |
| ALB test timeout | Refresh private-alb mapping; verify SG-to-SG port 80; never open 0.0.0.0/0. |
| Health says replica true but reads fail | That health endpoint queries only primary; verify replica with its dedicated script. |
| Plan wants replacements unexpectedly | Stop; inspect changed variables/provider/state and AMI/storage settings before applying. |
| Database tuning partially fails | Preserve logs, inspect existing/invalid indexes and view, resume deliberately. |

## 16 Validation and sources

Read `VALIDATION.md` for the exact local checks run and the limits of that verification. A mocked Terraform plan proves configuration behavior against provider schemas; it does **not** prove account permissions, regional availability, container startup or R1 performance in your account.

Source of deployment limits: supplied **Credify Capstone Student Manual**, sections 7, 8 and 10. Pattern: supplied **GroupA_ADR_Chiedozie_Maduabuchi.pptx**. SQL, endpoint behavior and benchmark: supplied starter ZIP. The kit preserves the original schema, seed, optimisation SQL and load-test file; changes are limited to Node 22, verified DB TLS, same-origin frontend configuration, and Odoo startup against RDS/EFS with Secrets Manager credentials.

Official references:

- [Terraform AWS DB instance](https://registry.terraform.io/providers/hashicorp/aws/6.20.0/docs/resources/db_instance)
- [Terraform AWS ECS service](https://registry.terraform.io/providers/hashicorp/aws/6.20.0/docs/resources/ecs_service)
- [RDS managed-secret limitations](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [ECS secret injection](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html)
- [EFS task volumes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specify-efs-config.html)
- [Terraform state and sensitive values](https://developer.hashicorp.com/terraform/language/state/sensitive-data)
- [S3 backend and native locking](https://developer.hashicorp.com/terraform/language/backend/s3)
