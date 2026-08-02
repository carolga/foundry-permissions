#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SourcePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string] $Message) {
    $script:failures.Add($Message)
}

function Invoke-BootstrapOffline {
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    foreach ($argument in @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        $ScriptPath
    ) + $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void] $process.Start()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode       = $process.ExitCode
        StandardOutput = $standardOutput
        StandardError  = $standardError
    }
}

try {
    $scriptPath = Join-Path $SourcePath 'scripts\bootstrap-entra-groups.ps1'
    $runbookPath = Join-Path $SourcePath 'docs\runbooks\identity-bootstrap.md'

    foreach ($path in @($scriptPath, $runbookPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required identity-bootstrap file not found: $path"
        }
    }

    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $runbookText = Get-Content -LiteralPath $runbookPath -Raw

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        Add-Failure "Identity bootstrap script has parser errors: $($parseErrors.Message -join '; ')"
    }

    if ($scriptText -match '\$[A-Za-z_][A-Za-z0-9_]*\?') {
        Add-Failure 'Identity bootstrap contains ambiguous variable interpolation immediately before a query string.'
    }

    $groupReadWriteChecks = [regex]::Matches(
        $scriptText,
        [regex]::Escape("`$permissions.Contains('Group.ReadWrite.All')")
    ).Count
    if ($groupReadWriteChecks -lt 1) {
        Add-Failure 'Identity bootstrap does not enforce delegated Group.ReadWrite.All.'
    }

    if ($scriptText -match [regex]::Escape("`$permissions.Contains('Group.Create')") -or
        $scriptText -match [regex]::Escape("`$permissions.Contains('Group.Read.All')")) {
        Add-Failure 'Identity bootstrap still accepts the insufficient app-only Group.Create/Group.Read.All permission path.'
    }

    if ($scriptText -match [regex]::Escape("`$permissions.Contains('Directory.Read.All')")) {
        Add-Failure 'Identity bootstrap unnecessarily requires delegated Directory.Read.All.'
    }

    if ($scriptText -notmatch '(?s)function Remove-NewlyCreatedGroupSafely.+?Invoke-GraphWrite -Method DELETE') {
        Add-Failure 'Identity bootstrap does not implement rollback deletion for a safely identified newly created group.'
    }
    if ($scriptText -match '(?s)function Remove-NewlyCreatedGroupSafely.+?catch\s*\{.+?Write-Warning.+?\}') {
        Add-Failure 'Identity bootstrap suppresses a rollback failure as a warning.'
    }
    if ($scriptText -notmatch 'automated rollback failed or was blocked' -or
        $scriptText -notmatch 'a newly created exact-name group may remain') {
        Add-Failure 'Identity bootstrap does not explicitly fail closed when rollback cannot be guaranteed.'
    }

    $ownerA = '11111111-1111-4111-8111-111111111111'
    $ownerB = '22222222-2222-4222-8222-222222222222'
    $whatIfResult = Invoke-BootstrapOffline -ScriptPath $scriptPath -Arguments @(
        '-HoaOwnerObjectId', $ownerA,
        '-ContractOwnerObjectId', $ownerB,
        '-WhatIf'
    )
    if ($whatIfResult.ExitCode -ne 0) {
        Add-Failure "-WhatIf offline validation failed: $($whatIfResult.StandardError.Trim())"
    }

    $functionNames = @(
        'ConvertTo-NormalizedObjectIds',
        'Test-Property',
        'Get-GroupById',
        'Remove-NewlyCreatedGroupSafely'
    )
    foreach ($functionName in $functionNames) {
        $definition = $scriptAst.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq $functionName
            },
            $true
        ) | Select-Object -First 1

        if ($null -eq $definition) {
            Add-Failure "Identity bootstrap function '$functionName' was not found for mocked URI testing."
            continue
        }

        . ([scriptblock]::Create($definition.Extent.Text))
    }

    if (@($functionNames | Where-Object { $null -eq (Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue) }).Count -eq 0) {
        $invalidOwnerRejected = $false
        try {
            [void] (ConvertTo-NormalizedObjectIds -ObjectIds @('not-a-guid') -GroupLabel 'mocked-group')
        }
        catch {
            $invalidOwnerRejected = $true
        }
        if (-not $invalidOwnerRejected) {
            Add-Failure 'Identity bootstrap accepted an invalid owner object ID during offline validation.'
        }

        $duplicateOwnerRejected = $false
        try {
            [void] (ConvertTo-NormalizedObjectIds -ObjectIds @($ownerA, $ownerA) -GroupLabel 'mocked-group')
        }
        catch {
            $duplicateOwnerRejected = $true
        }
        if (-not $duplicateOwnerRejected) {
            Add-Failure 'Identity bootstrap accepted duplicate owner object IDs during offline validation.'
        }

        $script:capturedGraphUris = [System.Collections.Generic.List[string]]::new()
        $script:capturedWriteUris = [System.Collections.Generic.List[string]]::new()
        $script:graphResponse = $null

        function Invoke-GraphJson {
            param(
                [string] $Method,
                [string] $Uri,
                [string] $FailureMessage
            )
            [void] $script:capturedGraphUris.Add($Uri)
            return $script:graphResponse
        }

        function Invoke-GraphWrite {
            param(
                [string] $Method,
                [string] $Uri,
                [string] $FailureMessage
            )
            [void] $script:capturedWriteUris.Add($Uri)
        }

        $groupId = '33333333-3333-4333-8333-333333333333'
        $groupLabel = 'mocked-group'
        $expectedReadBackUri = (
            'https://graph.microsoft.com/v1.0/groups/{0}?' +
            '$select=id%2CdisplayName%2CsecurityEnabled%2CmailEnabled%2CgroupTypes'
        ) -f $groupId
        $script:graphResponse = [pscustomobject]@{ id = $groupId }
        [void] (Get-GroupById -GroupId $groupId -GroupLabel $groupLabel)
        if ($script:capturedGraphUris.Count -ne 1 -or
            $script:capturedGraphUris[0] -cne $expectedReadBackUri) {
            Add-Failure "Post-create read-back URI did not retain the group ID before the query string."
        }

        $script:capturedGraphUris.Clear()
        $script:capturedWriteUris.Clear()
        $script:graphResponse = [pscustomobject]@{
            id          = $groupId
            displayName = $groupLabel
        }
        $script:BootstrapCmdlet = [pscustomobject]@{}
        $script:BootstrapCmdlet | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value {
            param($Target, $Action)
            return $true
        }

        Remove-NewlyCreatedGroupSafely -GroupId $groupId -GroupLabel $groupLabel 3>$null
        $expectedRollbackReadUri = (
            'https://graph.microsoft.com/v1.0/groups/{0}?' +
            '$select=id%2CdisplayName'
        ) -f $groupId
        if ($script:capturedGraphUris.Count -ne 1 -or
            $script:capturedGraphUris[0] -cne $expectedRollbackReadUri) {
            Add-Failure 'Rollback verification URI did not retain the group ID before the query string.'
        }
        if ($script:capturedWriteUris.Count -ne 1 -or
            $script:capturedWriteUris[0] -cne "https://graph.microsoft.com/v1.0/groups/$groupId") {
            Add-Failure 'Rollback did not delete only the mocked, safely verified group ID.'
        }

        $script:capturedWriteUris.Clear()
        $script:graphResponse = [pscustomobject]@{
            id          = '44444444-4444-4444-8444-444444444444'
            displayName = $groupLabel
        }
        $rollbackRejected = $false
        try {
            Remove-NewlyCreatedGroupSafely -GroupId $groupId -GroupLabel $groupLabel 3>$null
        }
        catch {
            $rollbackRejected = $true
        }
        if (-not $rollbackRejected -or $script:capturedWriteUris.Count -ne 0) {
            Add-Failure 'Rollback safety verification did not block deletion for a mismatched group ID.'
        }
    }

    foreach ($requiredRunbookText in @(
        'delegated `Group.ReadWrite.All` is required',
        'rejects application-only tokens',
        '`Directory.Read.All` scope',
        'Rollback is fail-closed, not best-effort',
        'It never deletes a preexisting group'
    )) {
        if ($runbookText -cnotmatch [regex]::Escape($requiredRunbookText)) {
            Add-Failure "Identity bootstrap runbook omits required contract: $requiredRunbookText"
        }
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Identity-bootstrap assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Identity-bootstrap assertions passed.'
exit 0
