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
$vmAdministratorLoginRoleGuid = '1c0163c0-47e6-4577-8991-ea5c82e286e4'

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
        $children = Get-PropertyValue $resource 'resources'
        if ($null -ne $children) {
            Get-ResourceRecords -TemplateRecord ([pscustomobject]@{
                Document = [pscustomobject]@{ resources = $children }
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

function Assert-Count {
    param([object[]] $Items, [int] $Expected, [string] $Label)
    $actual = @($Items).Count
    if ($actual -ne $Expected) {
        Add-Failure "$Label count was $actual; expected $Expected."
    }
}

function Get-ParameterDefinitions {
    param([object[]] $Templates, [string] $Name)
    return @($Templates | ForEach-Object {
        $definition = Get-PropertyValue (Get-PropertyValue $_.Document 'parameters') $Name
        if ($null -ne $definition) {
            $definition
        }
    })
}

try {
    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $templateRecords = [System.Collections.Generic.List[object]]::new()
    $rootDocuments = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $TemplatePath) {
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        $rootDocuments.Add($document)
        foreach ($record in Get-Templates -Document $document -Source $path) {
            $templateRecords.Add($record)
        }
    }

    $records = @($templateRecords | ForEach-Object { Get-ResourceRecords -TemplateRecord $_ })
    $allJson = ConvertTo-CompactJson @($rootDocuments)

    $virtualMachines = Get-ResourcesByType -Records $records -Type 'Microsoft.Compute/virtualMachines'
    $networkInterfaces = Get-ResourcesByType -Records $records -Type 'Microsoft.Network/networkInterfaces'
    $extensions = Get-ResourcesByType -Records $records -Type 'Microsoft.Compute/virtualMachines/extensions'
    $schedules = Get-ResourcesByType -Records $records -Type 'Microsoft.DevTestLab/schedules'
    $diskTagResources = Get-ResourcesByType -Records $records -Type 'Microsoft.Resources/tags'
    $userRoleAssignments = @(Get-ResourcesByType -Records $records -Type 'Microsoft.Authorization/roleAssignments' |
        Where-Object {
            (ConvertTo-CompactJson $_.Resource) -match '(?i)"principalType"\s*:\s*"User"'
        })

    Assert-Count $virtualMachines 1 'Windows validation VM'
    Assert-Count $networkInterfaces 1 'Windows validation NIC'
    Assert-Count $extensions 1 'AADLoginForWindows extension'
    Assert-Count $schedules 1 'VM shutdown schedule'
    Assert-Count $diskTagResources 1 'Validation OS disk tag application'
    Assert-Count $userRoleAssignments 1 'VM operator login role assignment'

    if ($virtualMachines.Count -eq 1) {
        $vm = $virtualMachines[0].Resource
        $vmJson = ConvertTo-CompactJson $vm
        $properties = Get-PropertyValue $vm 'properties'
        $identity = Get-PropertyValue $vm 'identity'
        $osProfile = Get-PropertyValue $properties 'osProfile'
        $storageProfile = Get-PropertyValue $properties 'storageProfile'
        $imageReference = Get-PropertyValue $storageProfile 'imageReference'
        $osDisk = Get-PropertyValue $storageProfile 'osDisk'
        $securityProfile = Get-PropertyValue $properties 'securityProfile'
        $uefiSettings = Get-PropertyValue $securityProfile 'uefiSettings'
        $bootDiagnostics = Get-PropertyValue (Get-PropertyValue $properties 'diagnosticsProfile') 'bootDiagnostics'

        if ($null -ne (Get-PropertyValue $vm 'condition')) {
            Add-Failure 'The approved validation VM is conditional; deployment must require its secure parameters.'
        }
        if ([string](Get-PropertyValue $identity 'type') -cne 'SystemAssigned') {
            Add-Failure 'The validation VM does not use a system-assigned managed identity.'
        }
        if ([string](Get-PropertyValue $imageReference 'publisher') -cne 'MicrosoftWindowsServer' -or
            [string](Get-PropertyValue $imageReference 'offer') -cne 'WindowsServer' -or
            [string](Get-PropertyValue $imageReference 'sku') -cne '2022-datacenter-azure-edition' -or
            [string](Get-PropertyValue $imageReference 'version') -cne 'latest') {
            Add-Failure 'The validation VM image is not the approved Windows Server 2022 Azure Edition image.'
        }
        if ($null -eq (Get-PropertyValue $osProfile 'windowsConfiguration') -or
            $null -ne (Get-PropertyValue $osProfile 'linuxConfiguration')) {
            Add-Failure 'The validation VM OS profile is not Windows-only.'
        }
        if ([string](Get-PropertyValue $osProfile 'adminPassword') -notmatch "parameters\('validationAdminPassword'\)") {
            Add-Failure 'The validation VM local administrator password is not supplied from the secure parameter.'
        }
        if ([string](Get-PropertyValue $osDisk 'osType') -cne 'Windows' -or
            [string](Get-PropertyValue (Get-PropertyValue $osDisk 'managedDisk') 'storageAccountType') -cne 'StandardSSD_LRS') {
            Add-Failure 'The validation VM OS disk is not a Windows Standard SSD managed disk.'
        }
        if (@(Get-PropertyValue $storageProfile 'dataDisks').Count -ne 0) {
            Add-Failure 'The validation VM declares one or more data disks.'
        }
        if ([string](Get-PropertyValue $securityProfile 'securityType') -cne 'TrustedLaunch' -or
            (Get-PropertyValue $uefiSettings 'secureBootEnabled') -ne $true -or
            (Get-PropertyValue $uefiSettings 'vTpmEnabled') -ne $true) {
            Add-Failure 'The validation VM does not enforce Trusted Launch, Secure Boot, and vTPM.'
        }
        if ((Get-PropertyValue $bootDiagnostics 'enabled') -ne $true -or
            $null -ne (Get-PropertyValue $bootDiagnostics 'storageUri')) {
            Add-Failure 'The validation VM must use managed boot diagnostics without a storage URI or storage key.'
        }
        if ($vmJson -match '(?i)ubuntu|canonical|linuxConfiguration|ssh') {
            Add-Failure 'The validation VM compiled resource retains a Linux or SSH implementation remnant.'
        }
    }

    if ($networkInterfaces.Count -eq 1) {
        $nicJson = ConvertTo-CompactJson $networkInterfaces[0].Resource
        if ($nicJson -match '(?i)publicIPAddress') {
            Add-Failure 'The validation NIC attaches a public IP.'
        }
        if ($nicJson -notmatch "(?i)parameters\('validationSubnetId'\)") {
            Add-Failure 'The validation NIC is not attached to the validation subnet parameter.'
        }
    }

    if ($extensions.Count -eq 1) {
        $extension = $extensions[0].Resource
        $properties = Get-PropertyValue $extension 'properties'
        if ([string](Get-PropertyValue $properties 'publisher') -cne 'Microsoft.Azure.ActiveDirectory' -or
            [string](Get-PropertyValue $properties 'type') -cne 'AADLoginForWindows' -or
            [string](Get-PropertyValue $properties 'typeHandlerVersion') -cne '2.2' -or
            (Get-PropertyValue $properties 'autoUpgradeMinorVersion') -ne $true -or
        $null -ne (Get-PropertyValue $properties 'enableAutomaticUpgrade')) {
            Add-Failure 'The AADLoginForWindows extension contract is incomplete.'
        }
    }

    if ($diskTagResources.Count -eq 1) {
        $diskTags = $diskTagResources[0].Resource
        if ([string](Get-PropertyValue $diskTags 'scope') -notmatch "(?i)resourceId\('Microsoft.Compute/disks'" -or
            $null -eq (Get-PropertyValue (Get-PropertyValue $diskTags 'properties') 'tags')) {
            Add-Failure 'The VM-created managed OS disk does not receive the mandatory tag object.'
        }
    }

    if ($userRoleAssignments.Count -eq 1) {
        $assignment = $userRoleAssignments[0].Resource
        $assignmentJson = ConvertTo-CompactJson $assignment
        $contextJson = ConvertTo-CompactJson $userRoleAssignments[0].Template
        $scope = [string](Get-PropertyValue $assignment 'scope')
        $properties = Get-PropertyValue $assignment 'properties'
        if ([string](Get-PropertyValue $properties 'principalId') -notmatch "parameters\('operatorObjectId'\)" -or
            [string](Get-PropertyValue $properties 'principalType') -cne 'User') {
            Add-Failure 'The VM login assignment does not target the required ephemeral operator user parameter.'
        }
        if (($assignmentJson + $contextJson) -notmatch [regex]::Escape($vmAdministratorLoginRoleGuid)) {
            Add-Failure 'The VM login assignment does not use the Virtual Machine Administrator Login role GUID.'
        }
        if ($scope -notmatch "(?i)resourceId\('Microsoft.Compute/virtualMachines'" -or
            $scope -match '(?i)resourceGroups|subscriptions') {
            Add-Failure 'The operator login assignment is broader than the exact VM scope.'
        }
    }

    if ($schedules.Count -eq 1) {
        $properties = Get-PropertyValue $schedules[0].Resource 'properties'
        $notifications = Get-PropertyValue $properties 'notificationSettings'
        if ([string](Get-PropertyValue $properties 'status') -cne 'Enabled' -or
            [string](Get-PropertyValue $properties 'taskType') -cne 'ComputeVmShutdownTask' -or
            [string](Get-PropertyValue $properties 'targetResourceId') -notmatch "resourceId\('Microsoft.Compute/virtualMachines'" -or
            [string](Get-PropertyValue (Get-PropertyValue $properties 'dailyRecurrence') 'time') -notmatch "parameters\('validationVmShutdownTime'\)" -or
            [string](Get-PropertyValue $properties 'timeZoneId') -notmatch "parameters\('validationVmShutdownTimeZone'\)") {
            Add-Failure 'The validation VM daily auto-shutdown schedule is incomplete.'
        }
        if ([string](Get-PropertyValue $notifications 'status') -cne 'Disabled' -or
            -not [string]::IsNullOrEmpty([string](Get-PropertyValue $notifications 'emailRecipient')) -or
            -not [string]::IsNullOrEmpty([string](Get-PropertyValue $notifications 'webhookUrl'))) {
            Add-Failure 'The validation VM shutdown schedule enables or addresses notifications without approval.'
        }
    }

    foreach ($definition in Get-ParameterDefinitions -Templates $templateRecords -Name 'validationAdminPassword') {
        if ([string](Get-PropertyValue $definition 'type') -ine 'secureString' -or
            $null -ne (Get-PropertyValue $definition 'defaultValue')) {
            Add-Failure 'validationAdminPassword must be a required secureString at every entry point and module boundary.'
        }
    }
    foreach ($definition in Get-ParameterDefinitions -Templates $templateRecords -Name 'operatorObjectId') {
        if ($null -ne (Get-PropertyValue $definition 'defaultValue') -or
            [int](Get-PropertyValue $definition 'minLength') -ne 36 -or
            [int](Get-PropertyValue $definition 'maxLength') -ne 36) {
            Add-Failure 'operatorObjectId must be required, ephemeral, and GUID-length constrained.'
        }
    }

    $vmSizeDefinitions = Get-ParameterDefinitions -Templates $templateRecords -Name 'validationVmSize'
    foreach ($definition in $vmSizeDefinitions) {
        $allowedValues = @(Get-PropertyValue $definition 'allowedValues')
        if ($allowedValues.Count -ne 1 -or [string]$allowedValues[0] -cne 'Standard_B2s') {
            Add-Failure 'validationVmSize is not constrained to Standard_B2s.'
        }
    }

    $shutdownTimeDefinitions = Get-ParameterDefinitions -Templates $templateRecords -Name 'validationVmShutdownTime'
    if (-not ($shutdownTimeDefinitions | Where-Object {
        [string](Get-PropertyValue $_ 'defaultValue') -ceq '1900'
    })) {
        Add-Failure 'The entry point does not default daily shutdown to 19:00 local time.'
    }
    $shutdownZoneDefinitions = Get-ParameterDefinitions -Templates $templateRecords -Name 'validationVmShutdownTimeZone'
    if (-not ($shutdownZoneDefinitions | Where-Object {
        [string](Get-PropertyValue $_ 'defaultValue') -ceq 'Central Standard Time'
    })) {
        Add-Failure 'The entry point does not default shutdown to Central Standard Time.'
    }

    $outputsJson = ConvertTo-CompactJson @($templateRecords | ForEach-Object {
        Get-PropertyValue $_.Document 'outputs'
    })
    if ($outputsJson -match '(?i)validationAdminPassword|operatorObjectId') {
        Add-Failure 'A validation VM credential or operator object ID is exposed through outputs.'
    }

    $sourceFiles = Get-ChildItem -LiteralPath $resolvedSourcePath -Recurse -Filter '*.bicep' -File |
        Where-Object { $_.FullName -notlike '*\tests\*' }
    $sourceText = ($sourceFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    foreach ($obsoleteToken in @(
        'validationSshPublicKey',
        'AllowSshFromBastion',
        'linuxConfiguration',
        '0001-com-ubuntu-server-jammy',
        '22_04-lts-gen2'
    )) {
        if ($sourceText -match [regex]::Escape($obsoleteToken)) {
            Add-Failure "Obsolete Linux/SSH validation-host token remains in Bicep: $obsoleteToken."
        }
    }
    if ($allJson -notmatch 'vm-validation-' -or
        $allJson -notmatch 'nic-validation-' -or
        $allJson -notmatch 'shutdown-computevm-') {
        Add-Failure 'The deterministic validation VM, NIC, or schedule naming contract is absent.'
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Windows validation VM assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Windows validation VM assertions passed.'
exit 0
