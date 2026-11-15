param([switch]$SkipExisting)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $Root 'terraform'
$Kit = Join-Path $Root 'payload/credify-starter-kit'
$raw = & terraform "-chdir=$TfDir" output -json
if ($LASTEXITCODE -ne 0) { throw 'Run foundation apply first.' }
$o = ($raw -join "`n") | ConvertFrom-Json
$Region = $o.region.value
$Repos = $o.ecr_repositories.value
$Registry = ($Repos.api -split '/')[0]
& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop with Linux containers first.' }
# Image tag is read from your applied Terraform variable via a dedicated output.
$Tag = $o.image_tag.value
$Token = & aws ecr get-login-password --region $Region
if ($LASTEXITCODE -ne 0) { throw 'ECR login-token request failed. Check AWS_PROFILE.' }
$Token | & docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw 'Docker login failed.' }
Remove-Variable Token
foreach ($Service in @('api','lms','erp')) {
    $RepoUri = $Repos.$Service
    $RepoName = ($RepoUri -split '/',2)[1]
    $Found = & aws ecr describe-images --region $Region --repository-name $RepoName --image-ids "imageTag=$Tag" --query 'imageDetails[0].imageDigest' --output text 2>$null
    $Exists = $LASTEXITCODE -eq 0
    if ($Exists -and -not $SkipExisting) { throw "Immutable tag already exists for $Service. Use -SkipExisting to keep it, or choose a NEW tag before a new experiment." }
    if ($Exists) {
        Write-Host "Keeping $Service image $Found"
        if ($Service -eq 'erp') {
            & docker pull --platform linux/amd64 "${RepoUri}:$Tag"
            if ($LASTEXITCODE -ne 0) { throw 'Cannot pull existing ERP image.' }
        }
        continue
    }
    $BuildPath = if ($Service -eq 'erp') { Join-Path $Kit 'erp' } else { Join-Path $Kit "backend/$Service" }
    Invoke-WebRequest -UseBasicParsing -Uri 'https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem' -OutFile (Join-Path $BuildPath 'rds-ca.pem')
    & docker build --platform linux/amd64 -t "${RepoUri}:$Tag" $BuildPath
    if ($LASTEXITCODE -ne 0) { throw "$Service image build failed." }
    & docker push "${RepoUri}:$Tag"
    if ($LASTEXITCODE -ne 0) { throw "$Service image push failed." }
}
$Uid = & docker run --rm --entrypoint id "$($Repos.erp):$Tag" -u odoo
if ($LASTEXITCODE -ne 0) { throw 'Could not read Odoo UID.' }
$Gid = & docker run --rm --entrypoint id "$($Repos.erp):$Tag" -g odoo
if ($LASTEXITCODE -ne 0) { throw 'Could not read Odoo GID.' }
Write-Host "Set odoo_uid = $Uid and odoo_gid = $Gid in terraform.tfvars before baseline."
Write-Host 'All images are in ECR. Terraform resolves the immutable tag to each digest.'
