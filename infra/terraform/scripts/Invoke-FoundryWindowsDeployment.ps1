[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Workspace,
    [Parameter(Mandatory)]
    [string] $CredentialPath,
    [ValidateSet('plan', 'apply')]
    [string] $Action = 'plan',
    [string] $VarFile,
    [Parameter(Mandatory)]
    [string] $PlanFile
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows DPAPI is required to read the credential.' }
$credential = Import-Clixml -LiteralPath $CredentialPath
if ($credential -isnot [pscredential] -or $credential.UserName -ne 'foundryadmin') {
    throw 'Expected the privately stored foundryadmin credential.'
}
$previousPassword = $env:TF_VAR_windows_admin_password
try {
    $env:TF_VAR_windows_admin_password = $credential.GetNetworkCredential().Password
    & (Join-Path $PSScriptRoot 'Deploy-FoundryWithExistingStores.ps1') `
        -Workspace $Workspace -Action $Action -VarFile $VarFile -PlanFile $PlanFile
}
finally {
    if ($null -eq $previousPassword) { Remove-Item Env:\TF_VAR_windows_admin_password -ErrorAction SilentlyContinue }
    else { $env:TF_VAR_windows_admin_password = $previousPassword }
}
