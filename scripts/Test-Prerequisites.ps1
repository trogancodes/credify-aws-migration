$ErrorActionPreference = 'Stop'
& terraform version
if ($LASTEXITCODE -ne 0) { throw 'Install Terraform first.' }
& aws sts get-caller-identity
if ($LASTEXITCODE -ne 0) { throw 'Sign in to the approved AWS lab profile first.' }
$Checks = @(
    @{ Engine = 'postgres'; Class = 'db.t4g.medium'; Prefix = '16.' },
    @{ Engine = 'postgres'; Class = 'db.t4g.small'; Prefix = '16.' },
    @{ Engine = 'mariadb'; Class = 'db.t4g.small'; Prefix = '10.11.' }
)
foreach ($Check in $Checks) {
    $Query = "OrderableDBInstanceOptions[?starts_with(EngineVersion, '$($Check.Prefix)')].EngineVersion"
    $Versions = & aws rds describe-orderable-db-instance-options --region af-south-1 --engine $Check.Engine --db-instance-class $Check.Class --query $Query --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot query RDS availability; check region access and permissions.' }
    $Values = ($Versions -join "`n") | ConvertFrom-Json
    if (@($Values).Count -eq 0) { throw "No reviewed engine/class available: $($Check.Engine) $($Check.Class). Confirm an allowed alternative; do not upsize." }
    Write-Host "$($Check.Engine) $($Check.Class): available $((@($Values) | Select-Object -Unique) -join ', ')"
}
Write-Host 'Read-only availability check complete. This does not verify all create permissions or approve spending.'
