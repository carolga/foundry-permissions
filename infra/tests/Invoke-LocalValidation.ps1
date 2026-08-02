#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$infraRoot = Join-Path $repoRoot 'infra'
$entryPoints = [ordered]@{
    'bootstrap-main' = Join-Path $infraRoot 'bootstrap\main.bicep'
    'main'           = Join-Path $infraRoot 'main.bicep'
    'access'         = Join-Path $infraRoot 'access.bicep'
}

function Find-BicepCompiler {
    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        & $az.Source bicep version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Kind = 'az'; Path = $az.Source }
        }
    }

    $bicep = Get-Command bicep -ErrorAction SilentlyContinue
    if ($null -ne $bicep) {
        & $bicep.Source --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Kind = 'bicep'; Path = $bicep.Source }
        }
    }

    throw 'Neither "az bicep" nor the standalone "bicep" CLI is available.'
}

function Invoke-Assertion {
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [string] $SourcePath,

        [string[]] $TemplatePath = @()
    )

    $pwsh = (Get-Process -Id $PID).Path
    $quote = {
        param([string] $Value)
        return "'$($Value.Replace("'", "''"))'"
    }
    $command = "& $(& $quote $Script)"
    if ($SourcePath) {
        $command += " -SourcePath $(& $quote $SourcePath)"
    }
    if ($TemplatePath.Count -gt 0) {
        $templateLiterals = @($TemplatePath | ForEach-Object { & $quote $_ })
        $command += " -TemplatePath @($($templateLiterals -join ','))"
    }

    & $pwsh -NoLogo -NoProfile -NonInteractive -Command $command |
        ForEach-Object { Write-Host $_ }
    $exitCode = $LASTEXITCODE
    return $exitCode
}

$failures = [System.Collections.Generic.List[string]]::new()
$builtTemplates = [System.Collections.Generic.List[string]]::new()
$tempBase = Join-Path $repoRoot '.validation-work'
$workDir = Join-Path $tempBase ("foundry-permissions-validation-{0}" -f [guid]::NewGuid().ToString('N'))
$createdWorkDir = $false

try {
    $compiler = Find-BicepCompiler
    Write-Host "Bicep compiler: $($compiler.Kind)"

    New-Item -ItemType Directory -Path $tempBase -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $workDir -ErrorAction Stop | Out-Null
    $createdWorkDir = $true

    foreach ($entry in $entryPoints.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            $failures.Add("Missing entry point: $($entry.Value)")
            continue
        }

        $outputPath = Join-Path $workDir "$($entry.Key).json"
        Write-Host "Building $($entry.Value)"

        if ($compiler.Kind -eq 'az') {
            & $compiler.Path bicep build --file $entry.Value --outfile $outputPath
        }
        else {
            & $compiler.Path build $entry.Value --outfile $outputPath
        }

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
            $failures.Add("Bicep build failed: $($entry.Value)")
            continue
        }

        $builtTemplates.Add($outputPath)
    }

    $compiledPaths = @($builtTemplates | ForEach-Object { $_ })
    if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-NoSecrets.ps1') -SourcePath $infraRoot -TemplatePath $compiledPaths) -ne 0) {
        $failures.Add('Secret-safety assertions failed.')
    }

    if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-IdentityBootstrap.ps1') -SourcePath $repoRoot) -ne 0) {
        $failures.Add('Identity-bootstrap assertions failed.')
    }

    if ($builtTemplates.Count -eq $entryPoints.Count) {
        if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-RequiredTags.ps1') -SourcePath $infraRoot -TemplatePath $compiledPaths) -ne 0) {
            $failures.Add('Required-tag assertions failed.')
        }

        if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-Template.ps1') -TemplatePath $compiledPaths) -ne 0) {
            $failures.Add('Template structure assertions failed.')
        }

        if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-DefenderStorageOptOut.ps1') -TemplatePath $compiledPaths) -ne 0) {
            $failures.Add('Defender for Storage opt-out assertions failed.')
        }

        if ((Invoke-Assertion -Script (Join-Path $PSScriptRoot 'Assert-PolicyCompatibility.ps1') -SourcePath $infraRoot -TemplatePath $compiledPaths) -ne 0) {
            $failures.Add('Policy compatibility assertions failed.')
        }
    }
    else {
        $failures.Add('Template and policy assertions skipped because not all entry points built.')
    }
}
catch {
    $failures.Add($_.Exception.Message)
}
finally {
    if ($createdWorkDir -and (Test-Path -LiteralPath $workDir)) {
        $resolvedWorkDir = [IO.Path]::GetFullPath($workDir)
        $expectedPrefix = Join-Path $tempBase 'foundry-permissions-validation-'
        if ($resolvedWorkDir.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedWorkDir -Recurse -Force
            if ((Test-Path -LiteralPath $tempBase) -and
                @(Get-ChildItem -LiteralPath $tempBase -Force).Count -eq 0) {
                Remove-Item -LiteralPath $tempBase -Force
            }
        }
        else {
            $failures.Add("Refused to clean unexpected path: $resolvedWorkDir")
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Local infrastructure validation failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Local infrastructure validation passed.'
exit 0
