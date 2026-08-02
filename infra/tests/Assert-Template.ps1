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
$roleGuid = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
$hoaProject = 'hoa-project'
$contractProject = 'one-to-four-residential-contract-project'

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

    $records = [System.Collections.Generic.List[object]]::new()
    $records.Add([pscustomobject]@{ Document = $Document; Source = $Source })

    foreach ($resource in @(Get-ResourceItems $Document)) {
        $properties = Get-PropertyValue $resource 'properties'
        $nestedTemplate = Get-PropertyValue $properties 'template'
        if ($null -ne $nestedTemplate) {
            foreach ($nested in Get-Templates -Document $nestedTemplate -Source "$Source::$(Get-PropertyValue $resource 'name')") {
                $records.Add($nested)
            }
        }
    }

    return $records
}

function Get-ResourceRecords {
    param($TemplateRecord)

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in @(Get-ResourceItems $TemplateRecord.Document)) {
        $records.Add([pscustomobject]@{
            Resource = $resource
            Template = $TemplateRecord.Document
            Source   = $TemplateRecord.Source
        })

        $childResources = Get-PropertyValue $resource 'resources'
        if ($null -ne $childResources) {
            $nestedTemplate = [pscustomobject]@{ resources = $childResources }
            foreach ($nested in Get-ResourceRecords -TemplateRecord ([pscustomobject]@{
                Document = $nestedTemplate
                Source   = "$($TemplateRecord.Source)::$(Get-PropertyValue $resource 'name')"
            })) {
                $records.Add($nested)
            }
        }
    }
    return $records
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

function Assert-MinimumCount {
    param([object[]] $Items, [int] $Minimum, [string] $Label)
    $actual = @($Items).Count
    if ($actual -lt $Minimum) {
        Add-Failure "$Label count was $actual; expected at least $Minimum."
    }
}

function Assert-SecurityRuleContract {
    param(
        [object[]] $Rules,
        [hashtable] $Expected
    )

    $matches = @($Rules | Where-Object {
        [string](Get-PropertyValue $_ 'name') -ceq $Expected.Name
    })
    if ($matches.Count -ne 1) {
        Add-Failure "Security rule '$($Expected.Name)' count was $($matches.Count); expected one."
        return
    }

    $properties = Get-PropertyValue $matches[0] 'properties'
    $expectedAccess = if ($Expected.ContainsKey('Access')) {
        $Expected.Access
    }
    else {
        'Allow'
    }
    foreach ($field in @(
        @{ Name = 'priority'; Value = $Expected.Priority },
        @{ Name = 'direction'; Value = $Expected.Direction },
        @{ Name = 'access'; Value = $expectedAccess },
        @{ Name = 'protocol'; Value = $Expected.Protocol },
        @{ Name = 'sourcePortRange'; Value = '*' },
        @{ Name = 'sourceAddressPrefix'; Value = $Expected.Source },
        @{ Name = 'destinationAddressPrefix'; Value = $Expected.Destination }
    )) {
        $actual = Get-PropertyValue $properties $field.Name
        if ([string]$actual -cne [string]$field.Value) {
            Add-Failure "Security rule '$($Expected.Name)' has $($field.Name) '$actual'; expected '$($field.Value)'."
        }
    }

    $actualPorts = Get-PropertyValue $properties 'destinationPortRanges'
    if ($null -eq $actualPorts) {
        $actualPorts = Get-PropertyValue $properties 'destinationPortRange'
    }
    $actualPorts = @($actualPorts | ForEach-Object { [string]$_ } | Sort-Object)
    $expectedPorts = @($Expected.Ports | ForEach-Object { [string]$_ } | Sort-Object)
    if (@(Compare-Object -ReferenceObject $expectedPorts -DifferenceObject $actualPorts).Count -ne 0) {
        Add-Failure "Security rule '$($Expected.Name)' has ports '$($actualPorts -join ',')'; expected '$($expectedPorts -join ',')'."
    }
}

try {
    $templateRecords = [System.Collections.Generic.List[object]]::new()
    $rootDocuments = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $TemplatePath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Compiled template not found: $path"
        }
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        $rootDocuments.Add($document)
        foreach ($record in Get-Templates -Document $document -Source $path) {
            $templateRecords.Add($record)
        }
    }

    $resourceRecords = @($templateRecords | ForEach-Object { Get-ResourceRecords -TemplateRecord $_ })
    $allJson = ConvertTo-CompactJson @($rootDocuments)

    $accounts = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.CognitiveServices/accounts')
    $projects = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.CognitiveServices/accounts/projects')
    $storage = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Storage/storageAccounts')
    $search = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Search/searchServices')
    $cosmos = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.DocumentDB/databaseAccounts')
    $connections = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.CognitiveServices/accounts/projects/connections')
    $accountConnections = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.CognitiveServices/accounts/connections')
    $capabilityHosts = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts')
    $appInsights = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Insights/components')
    $workspaces = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.OperationalInsights/workspaces')
    $privateEndpoints = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/privateEndpoints')
    $dnsZones = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/privateDnsZones')
    $dnsLinks = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/privateDnsZones/virtualNetworkLinks')
    $bastions = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/bastionHosts')
    $virtualMachines = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Compute/virtualMachines')
    $networkInterfaces = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/networkInterfaces')
    $networkSecurityGroups = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/networkSecurityGroups')
    $privateDnsZoneGroups = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups')
    $diagnosticSettings = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Insights/diagnosticSettings')
    $roleAssignments = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Authorization/roleAssignments')
    $deployments = @(Get-ResourcesByType -Records $resourceRecords -Type 'Microsoft.Resources/deployments')

    Assert-Count $accounts 1 'Foundry account'
    Assert-Count $projects 2 'Foundry project'
    Assert-Count $storage 2 'Storage account'
    Assert-Count $search 2 'Azure AI Search service'
    Assert-Count $cosmos 2 'Cosmos DB account'
    Assert-MinimumCount $connections 6 'Project connection'
    Assert-Count $accountConnections 0 'Account-level connection'
    Assert-Count $capabilityHosts 2 'Project capability host'
    Assert-Count $appInsights 2 'Application Insights component'
    Assert-Count $workspaces 2 'Log Analytics workspace'
    Assert-Count $diagnosticSettings 4 'Explicit Foundry diagnostic setting'

    $diagnosticContracts = @(
        @{
            Name = 'account-to-hoa-workspace'
            ScopeToken = 'foundryAccountName'
            WorkspaceToken = 'hoaLogAnalyticsName'
        },
        @{
            Name = 'account-to-contract-workspace'
            ScopeToken = 'foundryAccountName'
            WorkspaceToken = 'contractLogAnalyticsName'
        },
        @{
            Name = 'hoa-project-to-hoa-workspace'
            ScopeToken = 'hoaProjectName'
            WorkspaceToken = 'hoaLogAnalyticsName'
        },
        @{
            Name = 'contract-project-to-contract-workspace'
            ScopeToken = 'contractProjectName'
            WorkspaceToken = 'contractLogAnalyticsName'
        }
    )
    foreach ($contract in $diagnosticContracts) {
        $matches = @($diagnosticSettings | Where-Object {
            [string](Get-PropertyValue $_.Resource 'name') -ceq $contract.Name
        })
        Assert-Count $matches 1 "Diagnostic setting $($contract.Name)"
        if ($matches.Count -ne 1) {
            continue
        }

        $resource = $matches[0].Resource
        if ($null -ne (Get-PropertyValue $resource 'condition')) {
            Add-Failure "Diagnostic setting $($contract.Name) is conditional; it must be emitted despite Ignore tags."
        }
        if ([string](Get-PropertyValue $resource 'scope') -notmatch [regex]::Escape($contract.ScopeToken)) {
            Add-Failure "Diagnostic setting $($contract.Name) does not target the expected account/project scope."
        }

        $properties = Get-PropertyValue $resource 'properties'
        if ([string](Get-PropertyValue $properties 'workspaceId') -notmatch [regex]::Escape($contract.WorkspaceToken)) {
            Add-Failure "Diagnostic setting $($contract.Name) does not target the expected isolated workspace."
        }

        $logs = @(Get-PropertyValue $properties 'logs')
        if ($logs.Count -ne 1 -or
            [string](Get-PropertyValue $logs[0] 'categoryGroup') -cne 'allLogs' -or
            (Get-PropertyValue $logs[0] 'enabled') -ne $true) {
            Add-Failure "Diagnostic setting $($contract.Name) must enable the allLogs category group."
        }

        $metrics = @(Get-PropertyValue $properties 'metrics')
        if ($metrics.Count -ne 1 -or
            [string](Get-PropertyValue $metrics[0] 'category') -cne 'AllMetrics' -or
            (Get-PropertyValue $metrics[0] 'enabled') -ne $true) {
            Add-Failure "Diagnostic setting $($contract.Name) must enable AllMetrics."
        }
    }

    foreach ($requiredName in @($hoaProject, $contractProject)) {
        if ($allJson -notmatch [regex]::Escape($requiredName)) {
            Add-Failure "Required project name is absent: $requiredName."
        }
    }

    foreach ($projectToken in @('hoa', 'contract')) {
        foreach ($resourceSet in @{
            Storage = $storage
            Search = $search
            Cosmos = $cosmos
            Connection = $connections
            CapabilityHost = $capabilityHosts
            Monitoring = @($appInsights + $workspaces)
        }.GetEnumerator()) {
            if (-not ($resourceSet.Value | Where-Object {
                (ConvertTo-CompactJson $_.Resource) -match $projectToken -or
                (ConvertTo-CompactJson $_.Template) -match $projectToken -or
                $_.Source -match $projectToken
            })) {
                Add-Failure "No $($resourceSet.Key) resource can be associated with the $projectToken project."
            }
        }
    }

    $networkInjectionCount = [regex]::Matches($allJson, '(?i)"networkInjections"\s*:').Count
    if ($networkInjectionCount -ne 1) {
        Add-Failure "networkInjections was declared $networkInjectionCount times; expected exactly one account-level declaration."
    }

    $subnetContract = [ordered]@{
        'agent-subnet'             = '192.168.0.0/24'
        'private-endpoint-subnet'  = '192.168.1.0/24'
        'AzureBastionSubnet'       = '192.168.2.0/26'
        'validation-subnet'        = '192.168.3.0/27'
    }
    foreach ($subnet in $subnetContract.GetEnumerator()) {
        if ($allJson -notmatch [regex]::Escape($subnet.Key)) {
            Add-Failure "Required subnet name is absent: $($subnet.Key)."
        }
        if ($allJson -notmatch [regex]::Escape($subnet.Value)) {
            Add-Failure "Required subnet prefix is absent: $($subnet.Value)."
        }
    }
    $approvedCidrs = @('192.168.0.0/16') + @($subnetContract.Values)
    $declaredCidrs = @([regex]::Matches($allJson, '\b(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}\b') |
        ForEach-Object Value | Sort-Object -Unique)
    foreach ($cidr in $declaredCidrs) {
        if ($cidr -notin $approvedCidrs) {
            Add-Failure "Unapproved fixed network prefix is present: $cidr."
        }
    }

    $bastionNsg = @($networkSecurityGroups | Where-Object {
        (ConvertTo-CompactJson $_.Resource) -match '"AllowHttpsInbound"'
    })
    Assert-Count $bastionNsg 1 'Azure Bastion network security group'
    if ($bastionNsg.Count -eq 1) {
        $bastionRules = @(
            Get-PropertyValue (Get-PropertyValue $bastionNsg[0].Resource 'properties') 'securityRules'
        )
        Assert-Count $bastionRules 8 'Azure Bastion required security rule'

        $bastionRuleContract = @(
            @{
                Name = 'AllowHttpsInbound'; Priority = 120; Direction = 'Inbound'
                Protocol = 'Tcp'; Source = 'Internet'; Destination = '*'; Ports = @('443')
            },
            @{
                Name = 'AllowGatewayManagerInbound'; Priority = 130; Direction = 'Inbound'
                Protocol = 'Tcp'; Source = 'GatewayManager'; Destination = '*'; Ports = @('443')
            },
            @{
                Name = 'AllowAzureLoadBalancerInbound'; Priority = 140; Direction = 'Inbound'
                Protocol = 'Tcp'; Source = 'AzureLoadBalancer'; Destination = '*'; Ports = @('443')
            },
            @{
                Name = 'AllowBastionHostCommunication'; Priority = 150; Direction = 'Inbound'
                Protocol = '*'; Source = 'VirtualNetwork'; Destination = 'VirtualNetwork'; Ports = @('8080', '5701')
            },
            @{
                Name = 'AllowSshRdpOutbound'; Priority = 100; Direction = 'Outbound'
                Protocol = '*'; Source = '*'; Destination = 'VirtualNetwork'; Ports = @('22', '3389')
            },
            @{
                Name = 'AllowAzureCloudOutbound'; Priority = 110; Direction = 'Outbound'
                Protocol = 'Tcp'; Source = '*'; Destination = 'AzureCloud'; Ports = @('443')
            },
            @{
                Name = 'AllowBastionCommunication'; Priority = 120; Direction = 'Outbound'
                Protocol = '*'; Source = 'VirtualNetwork'; Destination = 'VirtualNetwork'; Ports = @('8080', '5701')
            },
            @{
                Name = 'AllowHttpOutbound'; Priority = 130; Direction = 'Outbound'
                Protocol = '*'; Source = '*'; Destination = 'Internet'; Ports = @('80')
            }
        )
        foreach ($expectedRule in $bastionRuleContract) {
            Assert-SecurityRuleContract -Rules $bastionRules -Expected $expectedRule
        }
    }

    $validationNsg = @($networkSecurityGroups | Where-Object {
        (ConvertTo-CompactJson $_.Resource) -match '"AllowSshFromBastion"'
    })
    Assert-Count $validationNsg 1 'Validation-host network security group'
    if ($validationNsg.Count -eq 1) {
        $validationRules = @(
            Get-PropertyValue (Get-PropertyValue $validationNsg[0].Resource 'properties') 'securityRules'
        )
        Assert-Count $validationRules 2 'Validation-host security rule'
        Assert-SecurityRuleContract -Rules $validationRules -Expected @{
            Name = 'AllowSshFromBastion'; Priority = 100; Direction = 'Inbound'
            Protocol = 'Tcp'
            Source = "[parameters('bastionSubnetPrefix')]"
            Destination = "[parameters('validationSubnetPrefix')]"
            Ports = @('22')
        }
        Assert-SecurityRuleContract -Rules $validationRules -Expected @{
            Name = 'DenyAllOtherInbound'; Priority = 110; Direction = 'Inbound'
            Access = 'Deny'; Protocol = '*'
            Source = '*'
            Destination = "[parameters('validationSubnetPrefix')]"
            Ports = @('*')
        }

        $allowSshRule = @($validationRules | Where-Object {
            [string](Get-PropertyValue $_ 'name') -ceq 'AllowSshFromBastion'
        })
        $denyOtherRule = @($validationRules | Where-Object {
            [string](Get-PropertyValue $_ 'name') -ceq 'DenyAllOtherInbound'
        })
        if ($allowSshRule.Count -eq 1 -and $denyOtherRule.Count -eq 1) {
            $allowPriority = [int](Get-PropertyValue (Get-PropertyValue $allowSshRule[0] 'properties') 'priority')
            $denyPriority = [int](Get-PropertyValue (Get-PropertyValue $denyOtherRule[0] 'properties') 'priority')
            if ($allowPriority -ge $denyPriority) {
                Add-Failure 'Validation-host Bastion SSH allow must be evaluated before the catch-all inbound deny.'
            }
            if ($denyPriority -ge 65000) {
                Add-Failure 'Validation-host catch-all inbound deny must override the default priority-65000 AllowVNetInBound rule.'
            }
        }
    }

    $logicalPrivateEndpointCount = [regex]::Matches(
        $allJson,
        '(?i)"groupIds?"\s*:\s*(?:\[\s*)?"(?:account|blob|searchService|Sql|azuremonitor)"'
    ).Count
    if ($logicalPrivateEndpointCount -lt 8) {
        Add-Failure "Private endpoint logical count was $logicalPrivateEndpointCount; expected at least 8."
    }
    foreach ($groupId in @('account', 'blob', 'searchService', 'Sql', 'azuremonitor')) {
        if ($allJson -notmatch "(?i)`"groupIds?`"\s*:\s*(?:\[\s*)?`"$([regex]::Escape($groupId))`"") {
            Add-Failure "Private endpoint group ID is absent: $groupId."
        }
    }

    $requiredDnsZones = @(
        'privatelink.cognitiveservices.azure.com',
        'privatelink.openai.azure.com',
        'privatelink.services.ai.azure.com',
        'privatelink.search.windows.net',
        'privatelink.documents.azure.com',
        'privatelink.blob.core.windows.net',
        'privatelink.monitor.azure.com',
        'privatelink.oms.opinsights.azure.com',
        'privatelink.ods.opinsights.azure.com',
        'privatelink.agentsvc.azure-automation.net'
    )
    Assert-Count $dnsZones 10 'Private DNS zone'
    Assert-Count $dnsLinks 10 'Private DNS virtual network link'
    foreach ($zone in $requiredDnsZones) {
        if ($allJson -notmatch [regex]::Escape($zone)) {
            Add-Failure "Required private DNS zone is absent: $zone."
        }
    }

    $monitorDnsParameters = @($templateRecords | ForEach-Object {
        $definition = Get-PropertyValue (Get-PropertyValue $_.Document 'parameters') 'monitorDnsZoneIds'
        if ($null -ne $definition) {
            $definition
        }
    })
    Assert-Count $monitorDnsParameters 1 'Azure Monitor DNS-zone parameter'
    if ($monitorDnsParameters.Count -eq 1) {
        if ([int](Get-PropertyValue $monitorDnsParameters[0] 'minLength') -ne 5 -or
            [int](Get-PropertyValue $monitorDnsParameters[0] 'maxLength') -ne 5) {
            Add-Failure 'Azure Monitor DNS-zone parameter must require exactly five zone IDs.'
        }
    }

    $monitorDnsOutputs = @($templateRecords | ForEach-Object {
        $definition = Get-PropertyValue (Get-PropertyValue $_.Document 'outputs') 'monitorDnsZoneIds'
        if ($null -ne $definition) {
            $definition
        }
    })
    Assert-Count $monitorDnsOutputs 1 'Azure Monitor DNS-zone output'
    if ($monitorDnsOutputs.Count -eq 1) {
        $monitorDnsOutputJson = ConvertTo-CompactJson $monitorDnsOutputs[0]
        foreach ($zone in @(
            'privatelink.monitor.azure.com',
            'privatelink.oms.opinsights.azure.com',
            'privatelink.ods.opinsights.azure.com',
            'privatelink.agentsvc.azure-automation.net',
            'privatelink.blob.core.windows.net'
        )) {
            if ($monitorDnsOutputJson -notmatch [regex]::Escape($zone)) {
                Add-Failure "Azure Monitor DNS-zone output omits required zone: $zone."
            }
        }
    }

    $monitorDnsZoneGroups = @($privateDnsZoneGroups | Where-Object {
        $_.Source -match '(?i)monitoring' -and
        (ConvertTo-CompactJson $_.Resource) -match '(?i)monitorDnsZoneIds'
    })
    Assert-Count $monitorDnsZoneGroups 1 'Azure Monitor private endpoint DNS-zone group'
    if ($monitorDnsZoneGroups.Count -eq 1) {
        $monitorDnsZoneGroupJson = ConvertTo-CompactJson $monitorDnsZoneGroups[0].Resource
        if ($monitorDnsZoneGroupJson -notmatch "(?i)length\(parameters\('monitorDnsZoneIds'\)\)") {
            Add-Failure 'Azure Monitor private endpoint DNS-zone group does not associate every supplied monitoring zone.'
        }
    }

    $monitoringBindings = @($deployments | Where-Object {
        $json = ConvertTo-CompactJson $_.Resource
        $json -match '(?i)monitoring' -and
        $json -match '(?i)monitorDnsZoneIds' -and
        $json -match '(?i)privateDns'
    })
    Assert-Count $monitoringBindings 1 'Azure Monitor DNS module binding'

    Assert-Count $bastions 1 'Azure Bastion host'
    Assert-Count $virtualMachines 1 'Validation virtual machine'
    Assert-MinimumCount $networkInterfaces 1 'Validation network interface'
    if ($allJson -notmatch 'AzureBastionSubnet' -or $allJson -notmatch 'validation-subnet') {
        Add-Failure 'Bastion and validation VM subnet relationships are incomplete.'
    }
    foreach ($nic in $networkInterfaces) {
        $nicJson = ConvertTo-CompactJson $nic.Resource
        if ($nicJson -match '(?i)publicIPAddress') {
            Add-Failure "Network interface $(Get-PropertyValue $nic.Resource 'name') attaches a public IP; the validation VM must be private-only."
        }
    }

    foreach ($record in @($accounts + $storage + $search + $cosmos)) {
        $json = ConvertTo-CompactJson $record.Resource
        if ($json -notmatch '(?i)"publicNetworkAccess"') {
            Add-Failure "$(Get-PropertyValue $record.Resource 'type') $(Get-PropertyValue $record.Resource 'name') does not declare publicNetworkAccess."
        }
        if ($json -match '(?i)"publicNetworkAccess"\s*:\s*"Enabled"') {
            Add-Failure "$(Get-PropertyValue $record.Resource 'type') $(Get-PropertyValue $record.Resource 'name') enables public network access."
        }
    }

    foreach ($record in @($accounts + $search + $cosmos)) {
        $json = ConvertTo-CompactJson $record.Resource
        if ($json -notmatch '(?i)"disableLocalAuth"') {
            Add-Failure "$(Get-PropertyValue $record.Resource 'type') $(Get-PropertyValue $record.Resource 'name') does not declare disableLocalAuth."
        }
        if ($json -match '(?i)"disableLocalAuth"\s*:\s*false') {
            Add-Failure "$(Get-PropertyValue $record.Resource 'type') $(Get-PropertyValue $record.Resource 'name') enables local authentication."
        }
    }
    foreach ($record in $storage) {
        $json = ConvertTo-CompactJson $record.Resource
        if ($json -notmatch '(?i)"allowSharedKeyAccess"') {
            Add-Failure "Storage account $(Get-PropertyValue $record.Resource 'name') does not declare allowSharedKeyAccess."
        }
        if ($json -match '(?i)"allowSharedKeyAccess"\s*:\s*true') {
            Add-Failure "Storage account $(Get-PropertyValue $record.Resource 'name') enables shared-key authentication."
        }
    }

    $groupAssignments = @($roleAssignments | Where-Object {
        $resourceJson = ConvertTo-CompactJson $_.Resource
        $templateJson = ConvertTo-CompactJson $_.Template
        $resourceJson -match '(?i)"principalType"\s*:\s*"Group"' -and
        $resourceJson -match '(?i)projects' -and
        (($resourceJson + $templateJson) -match [regex]::Escape($roleGuid) -or
            ($resourceJson + $templateJson) -match '(?i)foundryUserRoleDefinitionId' -or
            $_.Source -match '(?i)(hoa|contract)')
    })
    Assert-Count $groupAssignments 2 'Developer group role assignment'

    foreach ($assignment in $groupAssignments) {
        $resourceJson = ConvertTo-CompactJson $assignment.Resource
        $contextJson = ConvertTo-CompactJson $assignment.Template
        if (($resourceJson + $contextJson) -notmatch [regex]::Escape($roleGuid) -and
            -not (($resourceJson + $contextJson) -match '(?i)foundryUserRoleDefinitionId' -and
                $allJson -match [regex]::Escape($roleGuid))) {
            Add-Failure "Developer assignment $(Get-PropertyValue $assignment.Resource 'name') does not use the pinned Foundry User role GUID."
        }
        if ($resourceJson -notmatch '(?i)projects') {
            Add-Failure "Developer assignment $(Get-PropertyValue $assignment.Resource 'name') is not scoped to a project."
        }
        if ($resourceJson -notmatch '(?i)"principalType"\s*:\s*"Group"') {
            Add-Failure "Developer assignment $(Get-PropertyValue $assignment.Resource 'name') does not set principalType to Group."
        }
    }

    $hoaAssignment = @($groupAssignments | Where-Object {
        (ConvertTo-CompactJson $_.Resource) -match '(?i)hoaGroupObjectId' -or $_.Source -match '(?i)hoa'
    })
    $contractAssignment = @($groupAssignments | Where-Object {
        (ConvertTo-CompactJson $_.Resource) -match '(?i)contractGroupObjectId' -or $_.Source -match '(?i)contract'
    })
    Assert-Count $hoaAssignment 1 'HOA developer assignment'
    Assert-Count $contractAssignment 1 'Contract developer assignment'

    if (@($hoaAssignment).Count -eq 1 -and
        ((ConvertTo-CompactJson $hoaAssignment[0].Resource) + $hoaAssignment[0].Source) -notmatch '(?i)(hoaProjectName|hoa-project|hoa)') {
        Add-Failure 'The HOA group assignment is not tied to the HOA project scope.'
    }
    if (@($contractAssignment).Count -eq 1 -and
        ((ConvertTo-CompactJson $contractAssignment[0].Resource) + $contractAssignment[0].Source) -notmatch '(?i)(contractProjectName|one-to-four-residential-contract-project|contract)') {
        Add-Failure 'The contract group assignment is not tied to the contract project scope.'
    }

    foreach ($binding in @(
        @{ Group = 'hoaGroupObjectId'; Project = '(hoaProjectName|hoa-project)' },
        @{ Group = 'contractGroupObjectId'; Project = '(contractProjectName|one-to-four-residential-contract-project)' }
    )) {
        if (-not ($deployments | Where-Object {
            $json = ConvertTo-CompactJson $_.Resource
            $json -match "(?i)$($binding.Group)" -and $json -match "(?i)$($binding.Project)"
        }) -and
            $allJson -notmatch "(?is)$($binding.Group).{0,800}$($binding.Project)|$($binding.Project).{0,800}$($binding.Group)") {
            Add-Failure "No compiled module binding ties $($binding.Group) to its matching project."
        }
    }

    foreach ($parameterName in @('hoaGroupObjectId', 'contractGroupObjectId')) {
        $definitions = @($templateRecords | ForEach-Object {
            $parameters = Get-PropertyValue $_.Document 'parameters'
            $definition = Get-PropertyValue $parameters $parameterName
            if ($null -ne $definition) {
                $definition
            }
        })
        if ($definitions.Count -eq 0) {
            Add-Failure "Required access parameter is absent: $parameterName."
        }
        foreach ($definition in $definitions) {
            $defaultValue = Get-PropertyValue $definition 'defaultValue'
            if ($null -ne $defaultValue -and [string]$defaultValue -ne '') {
                Add-Failure "$parameterName must not have a committed default object ID."
            }
        }
    }
}
catch {
    Add-Failure $_.Exception.Message
}

if ($failures.Count -gt 0) {
    Write-Error ("Template assertions failed:`n - " + ($failures -join "`n - "))
    exit 1
}

Write-Host 'Template structure assertions passed.'
exit 0
