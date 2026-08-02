#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SourcePath,

    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [ValidateNotNullOrEmpty()]
    [string[]] $TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

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

function Get-Templates {
    param($Document, [string] $Source)

    [pscustomobject]@{ Document = $Document; Source = $Source }
    foreach ($resource in @(Get-ResourceItems $Document)) {
        $properties = Get-PropertyValue $resource 'properties'
        $nestedTemplate = Get-PropertyValue $properties 'template'
        if ($null -ne $nestedTemplate) {
            Get-Templates -Document $nestedTemplate -Source "$Source::$(Get-PropertyValue $resource 'name')"
        }
    }
}

function Get-ResourceRecords {
    param($TemplateRecord)

    foreach ($resource in @(Get-ResourceItems $TemplateRecord.Document)) {
        [pscustomobject]@{
            Resource = $resource
            Source   = $TemplateRecord.Source
        }
        $children = Get-PropertyValue $resource 'resources'
        if ($null -ne $children) {
            Get-ResourceRecords -TemplateRecord ([pscustomobject]@{
                Document = [pscustomobject]@{ resources = $children }
                Source   = "$($TemplateRecord.Source)::$(Get-PropertyValue $resource 'name')"
            })
        }
    }
}

try {
    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $entryPoints = @(
        (Join-Path $resolvedSourcePath 'main.bicep'),
        (Join-Path $resolvedSourcePath 'bootstrap\main.bicep'),
        (Join-Path $resolvedSourcePath 'tests\subscription-validation-wrapper.bicep')
    )

    foreach ($entryPoint in $entryPoints) {
        $text = Get-Content -LiteralPath $entryPoint -Raw
        $requiredTags = [regex]::Match(
            $text,
            '(?s)var\s+requiredTags\s*=\s*union\(\s*tags\s*,\s*\{(?<body>.*?)\}\s*\)'
        )
        if (-not $requiredTags.Success) {
            Add-Failure "$entryPoint does not apply a final locked requiredTags object after caller tags."
            continue
        }

        $body = $requiredTags.Groups['body'].Value
        foreach ($tagName in @('SecurityControl', 'CostControl')) {
            if ($body -notmatch "(?m)^\s*$tagName\s*:\s*'Ignore'\s*$") {
                Add-Failure "$entryPoint does not lock $tagName to the exact value Ignore."
            }
        }

        if ($text -match '(?m)^\s+tags\s*:\s*tags\s*$') {
            Add-Failure "$entryPoint passes caller tags directly instead of the locked requiredTags object."
        }
    }

    $sourceFiles = Get-ChildItem -LiteralPath $resolvedSourcePath -Recurse -Filter '*.bicep' -File
    foreach ($sourceFile in $sourceFiles) {
        $text = Get-Content -LiteralPath $sourceFile.FullName -Raw
        foreach ($tagName in @('SecurityControl', 'CostControl')) {
            foreach ($match in [regex]::Matches($text, "(?m)\b$tagName\s*:\s*'(?<value>[^']*)'")) {
                if ($match.Groups['value'].Value -cne 'Ignore') {
                    Add-Failure "$($sourceFile.FullName) assigns $tagName='$($match.Groups['value'].Value)' instead of Ignore."
                }
            }
        }
    }

    $parameterExample = Join-Path $resolvedSourcePath 'environments\validation.bicepparam.example'
    $parameterText = Get-Content -LiteralPath $parameterExample -Raw
    foreach ($tagName in @('SecurityControl', 'CostControl')) {
        if ($parameterText -notmatch "(?m)^\s*$tagName\s*:\s*'Ignore'\s*$") {
            Add-Failure "The validation parameter example omits $tagName='Ignore'."
        }
    }

    $taggableTypes = @(
        'Microsoft.CognitiveServices/accounts',
        'Microsoft.CognitiveServices/accounts/deployments',
        'Microsoft.CognitiveServices/accounts/projects',
        'Microsoft.Compute/virtualMachines',
        'Microsoft.DocumentDB/databaseAccounts',
        'Microsoft.Insights/components',
        'Microsoft.Insights/privateLinkScopes',
        'Microsoft.Network/bastionHosts',
        'Microsoft.Network/networkInterfaces',
        'Microsoft.Network/networkSecurityGroups',
        'Microsoft.Network/privateDnsZones',
        'Microsoft.Network/privateDnsZones/virtualNetworkLinks',
        'Microsoft.Network/privateEndpoints',
        'Microsoft.Network/publicIPAddresses',
        'Microsoft.Network/virtualNetworks',
        'Microsoft.OperationalInsights/workspaces',
        'Microsoft.Resources/resourceGroups',
        'Microsoft.Search/searchServices',
        'Microsoft.Storage/storageAccounts'
    )
    $propertyTagTypes = @(
        'Microsoft.CognitiveServices/accounts/projects/capabilityHosts'
    )
    $nonTaggableTypes = @(
        'Microsoft.Authorization/roleAssignments',
        'Microsoft.CognitiveServices/accounts/projects/connections',
        'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments',
        'Microsoft.Insights/diagnosticSettings',
        'Microsoft.Insights/privateLinkScopes/scopedResources',
        'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
        'Microsoft.Resources/deployments',
        'Microsoft.Security/defenderForStorageSettings',
        'Microsoft.Storage/storageAccounts/blobServices'
    )

    $records = foreach ($path in $TemplatePath) {
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        foreach ($template in Get-Templates -Document $document -Source $path) {
            Get-ResourceRecords -TemplateRecord $template
        }
    }

    foreach ($record in @($records)) {
        $resource = $record.Resource
        if ((Get-PropertyValue $resource 'existing') -eq $true) {
            continue
        }
        $type = [string](Get-PropertyValue $resource 'type')
        $name = [string](Get-PropertyValue $resource 'name')

        if ($type -in $taggableTypes) {
            if ($null -eq (Get-PropertyValue $resource 'tags')) {
                Add-Failure "$type $name in $($record.Source) is taggable but has no top-level tags."
            }
            continue
        }

        if ($type -in $propertyTagTypes) {
            $properties = Get-PropertyValue $resource 'properties'
            if ($null -eq (Get-PropertyValue $properties 'tags')) {
                Add-Failure "$type $name in $($record.Source) is taggable but has no properties.tags object."
            }
            continue
        }

        if ($type -in $nonTaggableTypes) {
            if ($null -ne (Get-PropertyValue $resource 'tags')) {
                Add-Failure "$type $name in $($record.Source) is explicitly non-taggable but declares top-level tags."
            }
            continue
        }

        Add-Failure "Resource type $type is not classified as taggable or explicitly non-taggable."
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Required-tag assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Required-tag assertions passed.'
exit 0
