[CmdletBinding()]
param(
    [ValidateSet('plan', 'apply')]
    [string] $Action = 'plan',
    [string] $Workspace = 'default',
    [string] $VarFile,
    [string] $PlanFile
)

$ErrorActionPreference = 'Stop'
$directory = (Resolve-Path (Join-Path $PSScriptRoot '..\backing-stores')).Path
if (-not $PlanFile) { $PlanFile = Join-Path $directory 'backing-stores.tfplan' }
if (-not [IO.Path]::IsPathRooted($PlanFile)) { $PlanFile = Join-Path (Get-Location).Path $PlanFile }
$PlanFile = [IO.Path]::GetFullPath($PlanFile)

& terraform "-chdir=$directory" init -input=false
if ($LASTEXITCODE -ne 0) { throw 'Backing-service Terraform initialization failed.' }
& terraform "-chdir=$directory" workspace select $Workspace
if ($LASTEXITCODE -ne 0) { throw "Backing-service workspace not found: $Workspace" }

if ($Action -eq 'plan') {
    if (-not $VarFile) { throw 'Supply -VarFile when planning the backing-service stack.' }
    $VarFile = (Resolve-Path -LiteralPath $VarFile).Path
    & terraform "-chdir=$directory" plan -input=false "-var-file=$VarFile" "-out=$PlanFile"
    if ($LASTEXITCODE -ne 0) { throw 'Backing-service Terraform plan failed.' }
}
else {
    if (-not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) { throw "Plan not found: $PlanFile" }
    & terraform "-chdir=$directory" apply -input=false $PlanFile
    if ($LASTEXITCODE -ne 0) { throw 'Backing-service Terraform apply failed.' }
}
