#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [ValidateNotNullOrEmpty()]
    [string] $SourcePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string] $Message) {
    $script:failures.Add($Message)
}

function ConvertTo-CompactJson($Value) {
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
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
            Template = $TemplateRecord.Document
            Source   = $TemplateRecord.Source
        }
        $childResources = Get-PropertyValue $resource 'resources'
        if ($null -ne $childResources) {
            Get-ResourceRecords -TemplateRecord ([pscustomobject]@{
                Document = [pscustomobject]@{ resources = $childResources }
                Source   = "$($TemplateRecord.Source)::$(Get-PropertyValue $resource 'name')"
            })
        }
    }
}

function Get-ResourcesByType {
    param([object[]] $Records, [string] $Type)
    return @($Records | Where-Object {
        ([string](Get-PropertyValue $_.Resource 'type')).Equals($Type, [StringComparison]::OrdinalIgnoreCase) -and
        (Get-PropertyValue $_.Resource 'existing') -ne $true
    })
}

function Assert-SecureProperty {
    param(
        [object[]] $Records,
        [string] $PropertyName,
        [string] $InsecureLiteral,
        [string] $Label
    )

    foreach ($record in $Records) {
        $json = ConvertTo-CompactJson $record.Resource
        if ($json -notmatch "(?i)`"$([regex]::Escape($PropertyName))`"") {
            Add-Failure "$Label $(Get-PropertyValue $record.Resource 'name') does not declare $PropertyName."
        }
        if ($json -match "(?i)`"$([regex]::Escape($PropertyName))`"\s*:\s*$InsecureLiteral") {
            Add-Failure "$Label $(Get-PropertyValue $record.Resource 'name') has a policy-incompatible $PropertyName value."
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
    $sourceText = ($sourceFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

    $templates = [System.Collections.Generic.List[object]]::new()
    $rootDocuments = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $TemplatePath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Compiled template not found: $path"
        }
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        $rootDocuments.Add($document)
        foreach ($template in Get-Templates -Document $document -Source $path) {
            $templates.Add($template)
        }
    }

    $records = @($templates | ForEach-Object { Get-ResourceRecords -TemplateRecord $_ })
    $allJson = ConvertTo-CompactJson @($rootDocuments)
    $combinedText = $sourceText + "`n" + $allJson

    if ($combinedText -match '(?i)\bProvisionedManaged\b') {
        Add-Failure 'ProvisionedManaged is prohibited by effective policy.'
    }
    if ($combinedText -match '(?i)(?:"?publicNetworkAccess"?\s*[:=]\s*[''"]Enabled[''"]|"?publicNetworkAccess"?.{0,160}"(?:defaultValue|allowedValues)"\s*:\s*(?:\[\s*)?"Enabled")') {
        Add-Failure 'Public network access can be configured as Enabled.'
    }
    if ($combinedText -match '(?i)(?:"?disableLocalAuth"?\s*[:=]\s*false|"?disableLocalAuth"?.{0,160}"(?:defaultValue|allowedValues)"\s*:\s*(?:\[\s*)?false)') {
        Add-Failure 'Local authentication can be configured as enabled.'
    }
    if ($combinedText -match '(?i)(?:"?allowSharedKeyAccess"?\s*[:=]\s*true|"?allowSharedKeyAccess"?.{0,160}"(?:defaultValue|allowedValues)"\s*:\s*(?:\[\s*)?true)') {
        Add-Failure 'Storage shared-key authentication can be configured as enabled.'
    }

    $accounts = @(Get-ResourcesByType -Records $records -Type 'Microsoft.CognitiveServices/accounts')
    $storage = @(Get-ResourcesByType -Records $records -Type 'Microsoft.Storage/storageAccounts')
    $search = @(Get-ResourcesByType -Records $records -Type 'Microsoft.Search/searchServices')
    $cosmos = @(Get-ResourcesByType -Records $records -Type 'Microsoft.DocumentDB/databaseAccounts')

    Assert-SecureProperty @($accounts + $storage + $search + $cosmos) 'publicNetworkAccess' '"Enabled"' 'Resource'
    Assert-SecureProperty @($accounts + $search + $cosmos) 'disableLocalAuth' 'false' 'Resource'
    Assert-SecureProperty $storage 'allowSharedKeyAccess' 'true' 'Storage account'

    $diagnostics = @(Get-ResourcesByType -Records $records -Type 'Microsoft.Insights/diagnosticSettings')
    if (@($diagnostics).Count -ne 4) {
        Add-Failure "Diagnostic setting count was $(@($diagnostics).Count); expected four explicit account/project settings because Ignore tags suppress inherited deployment."
    }
    foreach ($diagnostic in $diagnostics) {
        if ($null -ne (Get-PropertyValue $diagnostic.Resource 'condition')) {
            Add-Failure "Diagnostic setting $(Get-PropertyValue $diagnostic.Resource 'name') is conditional despite suppressed inherited governance deployment."
        }
    }
    foreach ($tagName in @('SecurityControl', 'CostControl')) {
        if ($combinedText -notmatch "(?is)\b$tagName\b.{0,80}\bIgnore\b") {
            Add-Failure "Mandatory $tagName=Ignore is absent while testing explicit diagnostic mitigation."
        }
    }

    $locationParameters = @($templates | ForEach-Object {
        $parameters = Get-PropertyValue $_.Document 'parameters'
        $location = Get-PropertyValue $parameters 'location'
        if ($null -ne $location) {
            $location
        }
    })
    if ($locationParameters.Count -eq 0) {
        Add-Failure 'No location parameter is present in the compiled templates.'
    }
    foreach ($parameter in $locationParameters) {
        $defaultValue = Get-PropertyValue $parameter 'defaultValue'
        $allowedValues = Get-PropertyValue $parameter 'allowedValues'
        if ($null -ne $defaultValue -and
            [string]$defaultValue -ne '' -and
            [string]$defaultValue -ne 'northcentralus') {
            Add-Failure "A location parameter defaults to unapproved location '$defaultValue'."
        }
        if ($null -ne $allowedValues -and
            @($allowedValues) -notcontains 'northcentralus') {
            Add-Failure 'A location parameter allowedValues list excludes northcentralus.'
        }
    }

    foreach ($record in $records) {
        $resourceLocation = Get-PropertyValue $record.Resource 'location'
        if ($null -eq $resourceLocation) {
            continue
        }
        $location = [string]$resourceLocation
        if (-not $location.StartsWith('[') -and $location -notin @('global', 'northcentralus')) {
            Add-Failure "$(Get-PropertyValue $record.Resource 'type') $(Get-PropertyValue $record.Resource 'name') uses unapproved literal location '$location'."
        }
    }

    foreach ($parameterName in @('modelName', 'modelVersion', 'modelSkuName', 'modelCapacity')) {
        if ($allJson -notmatch "(?i)`"$parameterName`"") {
            Add-Failure "Required model parameter is absent: $parameterName."
        }
    }
    if ($combinedText -notmatch '(?i)\bGlobalStandard\b') {
        Add-Failure 'The model SKU contract is not demonstrably GlobalStandard-compatible.'
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Policy compatibility assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Policy compatibility assertions passed.'
exit 0
