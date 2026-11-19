[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Workspace,
    [ValidateSet('plan', 'apply')]
    [string] $Action = 'plan',
    [string] $VarFile,
    [string] $PlanFile,
    [string] $BackingStoreDirectory = (Join-Path $PSScriptRoot '..\backing-stores'),
    [string] $BackingStoreWorkspace = 'default'
)

$ErrorActionPreference = 'Stop'
$directory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $PlanFile) { $PlanFile = Join-Path $directory 'foundry-existing.tfplan' }
if (-not [IO.Path]::IsPathRooted($PlanFile)) { $PlanFile = Join-Path (Get-Location).Path $PlanFile }
$PlanFile = [IO.Path]::GetFullPath($PlanFile)

& terraform "-chdir=$directory" init -input=false
if ($LASTEXITCODE -ne 0) { throw 'Foundry Terraform initialization failed.' }
& terraform "-chdir=$directory" workspace select $Workspace
if ($LASTEXITCODE -ne 0) { throw "Foundry workspace not found: $Workspace" }

if ($Action -eq 'plan') {
    if (-not $VarFile) { throw 'Supply -VarFile when planning Foundry.' }
    $VarFile = (Resolve-Path -LiteralPath $VarFile).Path
    $BackingStoreDirectory = (Resolve-Path -LiteralPath $BackingStoreDirectory).Path
    & terraform "-chdir=$BackingStoreDirectory" workspace select $BackingStoreWorkspace
    if ($LASTEXITCODE -ne 0) { throw "Backing-service workspace not found: $BackingStoreWorkspace" }
    $raw = & terraform "-chdir=$BackingStoreDirectory" output -json backing_resources
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read backing-service Terraform outputs.' }
    $stores = ($raw -join "`n") | ConvertFrom-Json
    foreach ($key in @('storage', 'cosmos', 'search')) {
        if ($stores.$key -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/') {
            throw "Backing-service output '$key' is not a full resource ID."
        }
    }
    & terraform "-chdir=$directory" plan -input=false "-var-file=$VarFile" `
        "-var=existing_storage_account_id=$($stores.storage)" `
        "-var=existing_cosmos_account_id=$($stores.cosmos)" `
        "-var=existing_search_service_id=$($stores.search)" "-out=$PlanFile"
    if ($LASTEXITCODE -ne 0) { throw 'Foundry Terraform plan failed.' }
}
else {
    if (-not (Test-Path -LiteralPath $PlanFile -PathType Leaf)) { throw "Plan not found: $PlanFile" }
    & terraform "-chdir=$directory" apply -input=false $PlanFile
    if ($LASTEXITCODE -ne 0) { throw 'Foundry Terraform apply failed.' }
}
