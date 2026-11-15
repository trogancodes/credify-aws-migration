param([string]$Destination = '.\evidence-download')
$ErrorActionPreference = 'Stop'
$TfDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform'
$Bucket = & terraform "-chdir=$TfDir" output -raw bucket_name
if ($LASTEXITCODE -ne 0) { throw 'Cannot read bucket output.' }
& aws s3 cp "s3://$Bucket/evidence/" $Destination --recursive --region af-south-1
if ($LASTEXITCODE -ne 0) { throw 'Evidence download failed.' }
