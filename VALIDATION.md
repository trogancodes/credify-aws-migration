# Validation record

Prepared 1 November 2026. No real AWS plan or apply was executed. No credentials, real resource IDs, state files, saved plans or provider binaries are included in the ZIP.

## Passed locally

- Terraform 1.11.4 parsed and formatted all configuration/test files with `terraform fmt`; final recursive `fmt -check` passed.
- `terraform init -backend=false` downloaded the pinned official providers and generated the dependency lock file. Official checksums are included for Linux AMD64 and Windows AMD64.
- Real Terraform language evaluation of the task-definition expressions passed for baseline, replica and tuned settings. Checks covered all three task JSON definitions, the materialised-view flag, presence/absence of READ_DB_HOST, ERP-only EFS mounts and API/LMS health checks. This caught and corrected an incompatible conditional-object expression during authoring.
- Python source parsed successfully, Bash scripts passed `bash -n`, and JavaScript passed Node syntax checks.
- Byte comparison confirmed that the six supplied SQL files and original `tools/loadtest.js` are unchanged.
- Resource review checked student CIDR, private data routing, fixed lab-sized classes/storage, one NAT, task replacement limits, state-secret handling and explicit baseline/tuning gates.

## Blocked by this execution environment

`terraform validate` and `terraform test` could not load provider schemas. All three provider plugins reported a local UNIX-socket error: `socket: operation not permitted`. The test run stopped at provider startup (0 tests passed; later cases skipped). This is **not** a passing provider validation or a passing test suite. No sandbox restriction was bypassed.

Run these on your Windows machine after `terraform init`, before any apply:

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
terraform -chdir=terraform plan -out=foundation.tfplan
```

The seven included test cases use mocked AWS/random/archive providers and do not create AWS infrastructure. They check phase behavior, private lab-sized defaults and acknowledgement gates. The actual account plan still needs valid credentials and instructor approval of the settings.

## Not exercised here

- PowerShell execution on Windows, Docker image builds or container runtime startup.
- Real AWS region/class availability, permissions, service quotas and provisioning behavior.
- RDS seed execution, Odoo initialization, EFS mounting, private ALB reachability or CloudFront browser behavior.
- Performance/R1, backup restoration, full HA or regional DR.

Follow the staged checkpoints in README.md. If local provider validation or a real plan fails, stop at the error rather than applying or increasing resource sizes. Preserve your baseline and original state.
