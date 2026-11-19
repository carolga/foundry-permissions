[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CredentialPath
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows DPAPI is required to protect the credential.' }
$CredentialPath = [IO.Path]::GetFullPath($CredentialPath)
if (Test-Path -LiteralPath $CredentialPath) { throw "Credential already exists: $CredentialPath" }
$parent = Split-Path -Parent $CredentialPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$random = -join (1..36 | ForEach-Object {
    $alphabet[[Security.Cryptography.RandomNumberGenerator]::GetInt32($alphabet.Length)]
})
$password = ConvertTo-SecureString "Aa1!$random" -AsPlainText -Force
$credential = [pscredential]::new('foundryadmin', $password)
$file = [IO.File]::Open($CredentialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$file.Dispose()
try {
    $credential | Export-Clixml -LiteralPath $CredentialPath
}
catch {
    Remove-Item -LiteralPath $CredentialPath
    throw
}
Write-Host "Created a Windows-user-protected credential at $CredentialPath."
