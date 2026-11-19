[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CredentialPath
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows DPAPI is required to read the credential.' }
$credential = Import-Clixml -LiteralPath $CredentialPath
if ($credential -isnot [pscredential] -or $credential.UserName -ne 'foundryadmin') {
    throw 'Expected the privately stored foundryadmin credential.'
}
$credential.GetNetworkCredential().Password | Set-Clipboard
Write-Host 'Password copied. Paste it into Bastion for foundryadmin and clear the clipboard after signing in.'
