#requires -Version 7.0
[CmdletBinding()]
param(
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
    param($Document)

    $Document
    foreach ($resource in @(Get-ResourceItems $Document)) {
        $properties = Get-PropertyValue $resource 'properties'
        $nestedTemplate = Get-PropertyValue $properties 'template'
        if ($null -ne $nestedTemplate) {
            Get-Templates -Document $nestedTemplate
        }
    }
}

function Get-Resources {
    param($Document)

    foreach ($resource in @(Get-ResourceItems $Document)) {
        $resource
        $children = Get-PropertyValue $resource 'resources'
        if ($null -ne $children) {
            Get-Resources -Document ([pscustomobject]@{ resources = $children })
        }
    }
}

try {
    $settings = foreach ($path in $TemplatePath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Compiled template not found: $path"
        }
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        foreach ($template in Get-Templates -Document $document) {
            Get-Resources -Document $template | Where-Object {
                ([string](Get-PropertyValue $_ 'type')).Equals(
                    'Microsoft.Security/defenderForStorageSettings',
                    [StringComparison]::OrdinalIgnoreCase
                ) -and
                (Get-PropertyValue $_ 'existing') -ne $true
            }
        }
    }

    $settings = @($settings)
    if ($settings.Count -ne 2) {
        Add-Failure "Defender for Storage setting count was $($settings.Count); expected one for each of the two project storage accounts."
    }

    foreach ($setting in $settings) {
        $name = [string](Get-PropertyValue $setting 'name')
        if ($name -notmatch "(?i)(^|/)current(')?\)?\]?$") {
            Add-Failure "Defender for Storage setting has unexpected name '$name'; expected current."
        }

        $scope = [string](Get-PropertyValue $setting 'scope')
        if ($scope -notmatch '(?i)Microsoft\.Storage/storageAccounts|storageAccountName') {
            Add-Failure "Defender for Storage setting '$name' is not scoped to a project storage account."
        }

        if ($null -ne (Get-PropertyValue $setting 'tags')) {
            Add-Failure "Defender for Storage setting '$name' declares tags even though this extension resource is non-taggable."
        }

        $properties = Get-PropertyValue $setting 'properties'
        if ((Get-PropertyValue $properties 'isEnabled') -ne $true) {
            Add-Failure "Defender for Storage setting '$name' disables the entire plan instead of retaining the narrower threat-detection control."
        }
        if ((Get-PropertyValue $properties 'overrideSubscriptionLevelSettings') -ne $true) {
            Add-Failure "Defender for Storage setting '$name' does not override subscription-level scanning settings."
        }

        $malwareScanning = Get-PropertyValue $properties 'malwareScanning'
        $onUpload = Get-PropertyValue $malwareScanning 'onUpload'
        if ((Get-PropertyValue $onUpload 'isEnabled') -ne $false) {
            Add-Failure "Defender for Storage setting '$name' does not explicitly disable on-upload malware scanning."
        }
        if ($null -ne (Get-PropertyValue $malwareScanning 'scanResultsEventGridTopicResourceId')) {
            Add-Failure "Defender for Storage setting '$name' configures an Event Grid scan-results destination while scanning is opted out."
        }

        $sensitiveDataDiscovery = Get-PropertyValue $properties 'sensitiveDataDiscovery'
        if ((Get-PropertyValue $sensitiveDataDiscovery 'isEnabled') -ne $true) {
            Add-Failure "Defender for Storage setting '$name' does not explicitly preserve sensitive-data threat detection."
        }
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Defender for Storage opt-out assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Defender for Storage opt-out assertions passed.'
exit 0
