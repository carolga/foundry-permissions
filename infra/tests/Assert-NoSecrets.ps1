#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SourcePath,

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $TemplatePath = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$allowedRoleGuid = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

function Add-Failure([string] $Message) {
    $script:failures.Add($Message)
}

function Get-PropertyValue {
    param($Object, [string] $Name)
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-ObjectProperties {
    param($Object)
    if ($null -eq $Object) {
        return
    }
    return $Object.PSObject.Properties
}

function Get-ResourceItems {
    param($Document)
    $resources = Get-PropertyValue $Document 'resources'
    if ($null -eq $resources) {
        return
    }
    if ($resources -is [array]) {
        return $resources
    }
    if ($null -ne (Get-PropertyValue $resources 'type')) {
        return ,$resources
    }
    return @($resources.PSObject.Properties | ForEach-Object Value)
}

function Test-SecretValue {
    param([string] $Value, [string] $Location)

    $patterns = [ordered]@{
        'private key material' = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
        'committed SSH key' = '(?m)^\s*(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp\d+)\s+[A-Za-z0-9+/=]{40,}'
        'JWT token' = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'
        'provider token' = '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,})\b'
        'SAS signature' = '(?i)(?:\?|&)(?:sv|se|sp)=[^''"\s&]+.*(?:&|&amp;)sig=[^''"\s&]+'
        'connection string' = '(?i)(?:AccountKey|SharedAccessKey|Password|Pwd)\s*=\s*[^;''"\s][^;''"]*;'
        'Azure storage key' = '(?i)\bAccountKey\s*=\s*[A-Za-z0-9+/]{40,}={0,2}'
    }

    foreach ($pattern in $patterns.GetEnumerator()) {
        if ($Value -match $pattern.Value) {
            Add-Failure "$Location contains $($pattern.Key)."
        }
    }
}

function Test-SourceFile {
    param([IO.FileInfo] $File)

    $text = Get-Content -LiteralPath $File.FullName -Raw
    Test-SecretValue -Value $text -Location $File.FullName

    if ($text -match '(?i)\b(listKeys|listSecrets)\s*\(') {
        Add-Failure "$($File.FullName) calls a secret-returning ARM function."
    }
    if ($text -match '(?im)^\s*output\s+\w*(password|privateKey|secret|token|connectionString|accountKey|sas)\w*\s') {
        Add-Failure "$($File.FullName) declares a secret-bearing output."
    }
    if ($text -match "(?im)\b(hoaGroupObjectId|contractGroupObjectId|operatorObjectId|tenantId|subscriptionId|principalId|clientId)\b\s*(?:=|:)\s*['`"](?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})['`"]") {
        if ($Matches.id -ne $allowedRoleGuid -and $Matches.id -ne '00000000-0000-0000-0000-000000000000') {
            Add-Failure "$($File.FullName) commits a tenant-specific object identifier."
        }
    }
    if ($text -match "(?im)\b(password|privateKey|clientSecret|connectionString|accountKey|sasToken)\b\s*(?:=|:)\s*['`"][^'`"]+['`"]") {
        Add-Failure "$($File.FullName) assigns a secret-bearing value."
    }
}

function Test-TemplateObject {
    param($Document, [string] $Location)

    $parameters = Get-PropertyValue $Document 'parameters'
    foreach ($parameter in @(Get-ObjectProperties $parameters)) {
        $name = $parameter.Name
        $definition = $parameter.Value
        $sensitiveName = $name -match '(?i)(password|privateKey|clientSecret|connectionString|accountKey|sasToken|accessToken|bearerToken)'
        if ($sensitiveName) {
            if ([string](Get-PropertyValue $definition 'type') -ine 'secureString') {
                Add-Failure "$Location parameter '$name' is secret-bearing but is not secureString."
            }
            if ($null -ne (Get-PropertyValue $definition 'defaultValue')) {
                Add-Failure "$Location parameter '$name' is secret-bearing but has a default value."
            }
        }

        if ($name -match '(?i)^(hoaGroupObjectId|contractGroupObjectId|operatorObjectId|tenantId|subscriptionId|principalId|clientId)$' -and
            $null -ne (Get-PropertyValue $definition 'defaultValue') -and
            [string](Get-PropertyValue $definition 'defaultValue') -match '^[0-9a-fA-F-]{36}$' -and
            [string](Get-PropertyValue $definition 'defaultValue') -ne '00000000-0000-0000-0000-000000000000') {
            Add-Failure "$Location gives '$name' a committed tenant-specific default."
        }
    }

    $outputs = Get-PropertyValue $Document 'outputs'
    foreach ($output in @(Get-ObjectProperties $outputs)) {
        $outputJson = $output.Value | ConvertTo-Json -Depth 100 -Compress
        if ($output.Name -match '(?i)(password|privateKey|publicKey|secret|token|connectionString|accountKey|sas|credential)' -or
            $outputJson -match '(?i)(listKeys|listSecrets)\s*\(') {
            Add-Failure "$Location contains unsafe output '$($output.Name)'."
        }
    }

    $json = $Document | ConvertTo-Json -Depth 100 -Compress
    Test-SecretValue -Value $json -Location $Location
    if ($json -match '(?i)(listKeys|listSecrets)\s*\(') {
        Add-Failure "$Location calls a secret-returning ARM function."
    }

    foreach ($resource in @(Get-ResourceItems $Document)) {
        $properties = Get-PropertyValue $resource 'properties'
        $nestedTemplate = Get-PropertyValue $properties 'template'
        if ($null -ne $nestedTemplate) {
            Test-TemplateObject -Document $nestedTemplate -Location "$Location::$(Get-PropertyValue $resource 'name')"
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Source directory not found: $SourcePath"
    }

    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $testsPath = Join-Path $resolvedSourcePath 'tests'
    $sourceFiles = Get-ChildItem -LiteralPath $resolvedSourcePath -Recurse -File |
        Where-Object {
            $_.Extension -in @('.bicep', '.bicepparam', '.json', '.ps1', '.psm1') -and
            -not $_.FullName.StartsWith("$testsPath$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)
        }
    foreach ($file in $sourceFiles) {
        Test-SourceFile -File $file
    }

    foreach ($path in $TemplatePath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Compiled template not found: $path"
        }
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        Test-TemplateObject -Document $document -Location $path
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Secret-safety assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Secret-safety assertions passed.'
exit 0
