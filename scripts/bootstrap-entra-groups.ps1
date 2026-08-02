#requires -Version 7.0

<#
.SYNOPSIS
Validates or creates the governed Entra groups required by the Foundry deployment.

.DESCRIPTION
Uses Azure CLI and Microsoft Graph to validate the active tenant, Graph token
permissions, approved owner object IDs, exact group names, immutable group
properties, and exact owner sets. Missing groups are created with owners in the
initial request and then verified. Existing drift is never repaired.

The active Microsoft Graph token must be delegated and include
Group.ReadWrite.All. Owner IDs are bound atomically in the group creation
request; the script does not require Directory.Read.All or pre-read owner
directory objects.

-WhatIf performs local input validation and makes no Azure CLI or Graph calls.

.PARAMETER HoaOwnerObjectId
The complete approved owner object ID set for hoa-group.

.PARAMETER ContractOwnerObjectId
The complete approved owner object ID set for One-to-Four-Residential-Contract.

.PARAMETER TenantId
Optional expected tenant ID. When supplied, it must match both the active Azure
CLI tenant and the Microsoft Graph access token tenant.

.EXAMPLE
.\scripts\bootstrap-entra-groups.ps1 `
  -HoaOwnerObjectId @('<approved-owner-guid>') `
  -ContractOwnerObjectId @('<approved-owner-guid>') `
  -TenantId '<tenant-guid>' `
  -WhatIf

.EXAMPLE
$groups = .\scripts\bootstrap-entra-groups.ps1 `
  -HoaOwnerObjectId @('<approved-owner-guid-1>', '<approved-owner-guid-2>') `
  -ContractOwnerObjectId @('<approved-owner-guid-3>', '<approved-owner-guid-4>') `
  -TenantId '<tenant-guid>'

$groups
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateCount(1, 64)]
    [string[]] $HoaOwnerObjectId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateCount(1, 64)]
    [string[]] $ContractOwnerObjectId,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string] $TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$script:BootstrapCmdlet = $PSCmdlet

function ConvertTo-NormalizedObjectIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ObjectIds,

        [Parameter(Mandatory)]
        [string] $GroupLabel
    )

    $normalized = [System.Collections.Generic.List[string]]::new()
    $unique = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($objectId in $ObjectIds) {
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            throw "Approved owner object IDs for '$GroupLabel' must not contain empty values."
        }

        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($objectId.Trim(), [ref] $parsed)) {
            throw "Approved owner object IDs for '$GroupLabel' must be GUIDs."
        }

        $canonical = $parsed.ToString('D')
        if (-not $unique.Add($canonical)) {
            throw "Approved owner object IDs for '$GroupLabel' must be unique."
        }

        $normalized.Add($canonical)
    }

    if ($normalized.Count -eq 0) {
        throw "At least one approved owner object ID is required for '$GroupLabel'."
    }

    return $normalized.ToArray()
}

function Invoke-AzText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    $raw = @(& az @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw $FailureMessage
    }

    return (($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
}

function Invoke-AzJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    $text = Invoke-AzText -Arguments $Arguments -FailureMessage $FailureMessage
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return $text | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "$FailureMessage Azure CLI returned an unreadable response."
    }
}

function Invoke-GraphJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    return Invoke-AzJson -Arguments @(
        'rest',
        '--method', $Method,
        '--uri', $Uri,
        '--output', 'json',
        '--only-show-errors'
    ) -FailureMessage $FailureMessage
}

function Invoke-GraphWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        'rest',
        '--method', $Method,
        '--uri', $Uri,
        '--output', 'none',
        '--only-show-errors'
    )) {
        $arguments.Add($argument)
    }

    [void] (Invoke-AzText -Arguments $arguments.ToArray() -FailureMessage $FailureMessage)
}

function Invoke-GraphCreate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Body,

        [Parameter(Mandatory)]
        [string] $FailureMessage
    )

    return Invoke-AzJson -Arguments @(
        'rest',
        '--method', 'POST',
        '--uri', 'https://graph.microsoft.com/v1.0/groups',
        '--headers', 'Content-Type=application/json',
        '--body', $Body,
        '--output', 'json',
        '--only-show-errors'
    ) -FailureMessage $FailureMessage
}

function ConvertFrom-Base64Url {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $base64 = $Value.Replace('-', '+').Replace('_', '/')
    switch ($base64.Length % 4) {
        0 { break }
        2 { $base64 += '==' }
        3 { $base64 += '=' }
        default { throw 'The Microsoft Graph access token has an invalid encoding.' }
    }

    try {
        return [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($base64)
        )
    }
    catch {
        throw 'The Microsoft Graph access token could not be inspected safely.'
    }
}

function Get-GraphTokenClaims {
    [CmdletBinding()]
    param()

    $accessToken = Invoke-AzText -Arguments @(
        'account',
        'get-access-token',
        '--resource-type', 'ms-graph',
        '--query', 'accessToken',
        '--output', 'tsv',
        '--only-show-errors'
    ) -FailureMessage 'Unable to obtain the active Microsoft Graph token from Azure CLI.'

    $segments = $accessToken.Split('.')
    if ($segments.Count -lt 2) {
        throw 'The active Microsoft Graph token could not be inspected safely.'
    }

    try {
        return (ConvertFrom-Base64Url -Value $segments[1]) | ConvertFrom-Json -Depth 20
    }
    catch {
        throw 'The active Microsoft Graph token claims could not be inspected safely.'
    }
    finally {
        $accessToken = $null
        $segments = $null
    }
}

function Test-Property {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    return $InputObject.PSObject.Properties.Name -contains $Name
}

function Assert-GraphAuthorizationClaims {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Claims,

        [Parameter(Mandatory)]
        [string] $ActiveTenantId
    )

    if (-not (Test-Property -InputObject $Claims -Name 'tid')) {
        throw 'The Microsoft Graph token does not identify a tenant.'
    }

    $tokenTenant = [guid]::Empty
    if (
        -not [guid]::TryParse([string] $Claims.tid, [ref] $tokenTenant) -or
        $tokenTenant.ToString('D') -ine $ActiveTenantId
    ) {
        throw 'The Microsoft Graph token tenant does not match the active Azure CLI tenant.'
    }

    $permissions = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if (-not (Test-Property -InputObject $Claims -Name 'scp')) {
        throw (
            'The Microsoft Graph token is not delegated. This bootstrap supports only ' +
            'the tested delegated Group.ReadWrite.All workflow.'
        )
    }

    foreach ($permission in ([string] $Claims.scp -split '\s+')) {
        if (-not [string]::IsNullOrWhiteSpace($permission)) {
            [void] $permissions.Add($permission)
        }
    }

    if (-not $permissions.Contains('Group.ReadWrite.All')) {
        throw 'The delegated Microsoft Graph token lacks Group.ReadWrite.All.'
    }
}

function Get-ExactGroupLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DisplayName
    )

    $odataName = $DisplayName.Replace("'", "''")
    $filter = [uri]::EscapeDataString("displayName eq '$odataName'")
    $uri = (
        "https://graph.microsoft.com/v1.0/groups?" +
        "`$filter=$filter&" +
        "`$select=id%2CdisplayName%2CsecurityEnabled%2CmailEnabled%2CgroupTypes&" +
        "`$top=2"
    )

    $response = Invoke-GraphJson -Method GET -Uri $uri `
        -FailureMessage "Microsoft Graph exact-name lookup failed for '$DisplayName'."

    if ($null -eq $response -or -not (Test-Property -InputObject $response -Name 'value')) {
        throw "Microsoft Graph exact-name lookup returned an invalid response for '$DisplayName'."
    }

    $matches = @($response.value)
    $hasMore = (
        (Test-Property -InputObject $response -Name '@odata.nextLink') -and
        -not [string]::IsNullOrWhiteSpace([string] $response.'@odata.nextLink')
    )

    if ($matches.Count -gt 1 -or $hasMore) {
        throw "Multiple Microsoft Graph groups match the exact-name lookup for '$DisplayName'."
    }

    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Get-GroupById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [string] $GroupLabel
    )

    $uri = (
        "https://graph.microsoft.com/v1.0/groups/${GroupId}?" +
        "`$select=id%2CdisplayName%2CsecurityEnabled%2CmailEnabled%2CgroupTypes"
    )

    return Invoke-GraphJson -Method GET -Uri $uri `
        -FailureMessage "Microsoft Graph read-back failed for '$GroupLabel'."
}

function Get-GroupOwnerIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [string] $GroupLabel
    )

    $ownerIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/owners?`$select=id&`$top=999"
    $pageCount = 0

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $pageCount++
        if ($pageCount -gt 20) {
            throw "Owner verification exceeded the safe page limit for '$GroupLabel'."
        }

        $response = Invoke-GraphJson -Method GET -Uri $uri `
            -FailureMessage "Microsoft Graph owner verification failed for '$GroupLabel'."

        if ($null -eq $response -or -not (Test-Property -InputObject $response -Name 'value')) {
            throw "Microsoft Graph owner verification returned an invalid response for '$GroupLabel'."
        }

        foreach ($owner in @($response.value)) {
            if ($null -eq $owner -or -not (Test-Property -InputObject $owner -Name 'id')) {
                throw "Microsoft Graph owner verification returned an invalid owner reference for '$GroupLabel'."
            }

            $parsed = [guid]::Empty
            if (-not [guid]::TryParse([string] $owner.id, [ref] $parsed)) {
                throw "Microsoft Graph owner verification returned an invalid owner reference for '$GroupLabel'."
            }

            [void] $ownerIds.Add($parsed.ToString('D'))
        }

        $nextLink = if (Test-Property -InputObject $response -Name '@odata.nextLink') {
            [string] $response.'@odata.nextLink'
        }
        else {
            ''
        }

        if (-not [string]::IsNullOrWhiteSpace($nextLink)) {
            if (-not $nextLink.StartsWith(
                'https://graph.microsoft.com/v1.0/',
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                throw "Microsoft Graph returned an unsafe owner verification continuation for '$GroupLabel'."
            }
        }

        $uri = $nextLink
    }

    return ,$ownerIds
}

function Assert-GroupState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Group,

        [Parameter(Mandatory)]
        [string] $GroupLabel,

        [Parameter(Mandatory)]
        [string[]] $ApprovedOwnerIds
    )

    foreach ($propertyName in @(
        'id',
        'displayName',
        'securityEnabled',
        'mailEnabled',
        'groupTypes'
    )) {
        if (-not (Test-Property -InputObject $Group -Name $propertyName)) {
            throw "Microsoft Graph omitted a required safe property for '$GroupLabel'."
        }
    }

    $parsedGroupId = [guid]::Empty
    if (-not [guid]::TryParse([string] $Group.id, [ref] $parsedGroupId)) {
        throw "Microsoft Graph returned an invalid group object ID for '$GroupLabel'."
    }

    if ([string] $Group.displayName -cne $GroupLabel) {
        throw "The located group does not preserve the required exact name '$GroupLabel'."
    }

    if ($Group.securityEnabled -isnot [bool] -or $Group.securityEnabled -ne $true) {
        throw "The existing group '$GroupLabel' is not security-enabled."
    }

    if ($Group.mailEnabled -isnot [bool] -or $Group.mailEnabled -ne $false) {
        throw "The existing group '$GroupLabel' is mail-enabled."
    }

    if (@($Group.groupTypes).Count -ne 0) {
        throw "The existing group '$GroupLabel' is not an assigned security group."
    }

    $actualOwnerIds = Get-GroupOwnerIds -GroupId $parsedGroupId.ToString('D') `
        -GroupLabel $GroupLabel

    if (-not $actualOwnerIds.SetEquals([string[]] $ApprovedOwnerIds)) {
        throw "The approved owner set does not exactly match the existing owners for '$GroupLabel'."
    }

    return $parsedGroupId.ToString('D')
}

function Remove-NewlyCreatedGroupSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [string] $GroupLabel
    )

    $uri = (
        "https://graph.microsoft.com/v1.0/groups/${GroupId}?" +
        "`$select=id%2CdisplayName"
    )
    $group = Invoke-GraphJson -Method GET -Uri $uri `
        -FailureMessage "Rollback safety verification failed for '$GroupLabel'."

    if (
        $null -eq $group -or
        -not (Test-Property -InputObject $group -Name 'id') -or
        -not (Test-Property -InputObject $group -Name 'displayName') -or
        [string] $group.id -ine $GroupId -or
        [string] $group.displayName -cne $GroupLabel
    ) {
        throw "Rollback stopped because the newly created '$GroupLabel' group could not be identified safely."
    }

    if (-not $script:BootstrapCmdlet.ShouldProcess(
        $GroupLabel,
        'Delete newly created group after failed same-invocation verification'
    )) {
        throw "Rollback deletion was not authorized for the newly created '$GroupLabel' group."
    }

    Invoke-GraphWrite -Method DELETE `
        -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId" `
        -FailureMessage "Rollback deletion failed for '$GroupLabel'."
    Write-Warning "The newly created group '$GroupLabel' was deleted after verification failed."
}

try {
    $hoaOwners = @(ConvertTo-NormalizedObjectIds `
        -ObjectIds $HoaOwnerObjectId `
        -GroupLabel 'hoa-group')
    $contractOwners = @(ConvertTo-NormalizedObjectIds `
        -ObjectIds $ContractOwnerObjectId `
        -GroupLabel 'One-to-Four-Residential-Contract')

    if ($WhatIfPreference) {
        [void] $PSCmdlet.ShouldProcess(
            'Microsoft Graph',
            'Validate the active tenant and governed Entra groups; create only missing groups'
        )
        return
    }

    if ($null -eq (Get-Command az -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI is required and was not found.'
    }

    $activeTenantText = Invoke-AzText -Arguments @(
        'account',
        'show',
        '--query', 'tenantId',
        '--output', 'tsv',
        '--only-show-errors'
    ) -FailureMessage 'Unable to validate the active Azure CLI tenant.'

    $activeTenant = [guid]::Empty
    if (-not [guid]::TryParse($activeTenantText, [ref] $activeTenant)) {
        throw 'Azure CLI returned an invalid active tenant.'
    }
    $activeTenantId = $activeTenant.ToString('D')

    if (
        -not [string]::IsNullOrWhiteSpace($TenantId) -and
        ([guid] $TenantId).ToString('D') -ine $activeTenantId
    ) {
        throw 'The active Azure CLI tenant does not match the requested tenant.'
    }

    $claims = Get-GraphTokenClaims
    Assert-GraphAuthorizationClaims -Claims $claims -ActiveTenantId $activeTenantId
    $claims = $null

    $groupSpecs = @(
        [pscustomobject]@{
            GroupLabel  = 'hoa-group'
            MailNickname = 'hoa-group'
            OwnerIds    = $hoaOwners
        },
        [pscustomobject]@{
            GroupLabel  = 'One-to-Four-Residential-Contract'
            MailNickname = 'One-to-Four-Residential-Contract'
            OwnerIds    = $contractOwners
        }
    )

    $preflight = [System.Collections.Generic.List[object]]::new()
    foreach ($spec in $groupSpecs) {
        $group = Get-ExactGroupLookup -DisplayName $spec.GroupLabel
        if ($null -eq $group) {
            $preflight.Add([pscustomobject]@{
                Spec     = $spec
                Existing = $false
                ObjectId = $null
            })
            continue
        }

        $objectId = Assert-GroupState `
            -Group $group `
            -GroupLabel $spec.GroupLabel `
            -ApprovedOwnerIds $spec.OwnerIds

        $preflight.Add([pscustomobject]@{
            Spec     = $spec
            Existing = $true
            ObjectId = $objectId
        })
    }

    foreach ($item in $preflight) {
        if ($item.Existing) {
            [pscustomobject]@{
                GroupLabel = $item.Spec.GroupLabel
                ObjectId   = $item.ObjectId
                Status     = 'Existing'
            }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess(
            $item.Spec.GroupLabel,
            'Create assigned Entra security group with approved owners'
        )) {
            continue
        }

        $ownerBindings = @(
            $item.Spec.OwnerIds | ForEach-Object {
                "https://graph.microsoft.com/v1.0/directoryObjects/$_"
            }
        )
        $payload = [ordered]@{
            displayName         = $item.Spec.GroupLabel
            mailEnabled         = $false
            mailNickname        = $item.Spec.MailNickname
            securityEnabled     = $true
            groupTypes          = @()
            'owners@odata.bind' = $ownerBindings
        } | ConvertTo-Json -Depth 5 -Compress

        $createdId = $null
        try {
            $creationResponse = Invoke-GraphCreate `
                -Body $payload `
                -FailureMessage "Microsoft Graph creation failed for '$($item.Spec.GroupLabel)'."
            $payload = $null
            $ownerBindings = $null

            $createdGuid = [guid]::Empty
            if (
                $null -eq $creationResponse -or
                -not (Test-Property -InputObject $creationResponse -Name 'id') -or
                -not [guid]::TryParse(
                    [string] $creationResponse.id,
                    [ref] $createdGuid
                )
            ) {
                throw "Microsoft Graph did not return a safe object ID for newly created group '$($item.Spec.GroupLabel)'."
            }
            $createdId = $createdGuid.ToString('D')
            $creationResponse = $null

            $verifiedId = $null
            $lastVerificationError = $null
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                try {
                    $createdGroup = Get-GroupById `
                        -GroupId $createdId `
                        -GroupLabel $item.Spec.GroupLabel
                    $nameMatch = Get-ExactGroupLookup `
                        -DisplayName $item.Spec.GroupLabel

                    if (
                        $null -eq $nameMatch -or
                        -not (Test-Property -InputObject $nameMatch -Name 'id') -or
                        [string] $nameMatch.id -ine $createdId
                    ) {
                        throw "Post-create exact-name verification failed for '$($item.Spec.GroupLabel)'."
                    }

                    $verifiedId = Assert-GroupState `
                        -Group $createdGroup `
                        -GroupLabel $item.Spec.GroupLabel `
                        -ApprovedOwnerIds $item.Spec.OwnerIds
                    $lastVerificationError = $null
                    break
                }
                catch {
                    $lastVerificationError = $_
                    if ($attempt -lt 6) {
                        Start-Sleep -Seconds 2
                    }
                }
            }

            if ($null -ne $lastVerificationError -or [string]::IsNullOrWhiteSpace($verifiedId)) {
                throw "Post-create property or owner verification failed for '$($item.Spec.GroupLabel)'."
            }

            [pscustomobject]@{
                GroupLabel = $item.Spec.GroupLabel
                ObjectId   = $verifiedId
                Status     = 'Created'
            }
        }
        catch {
            $operationFailure = $_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace([string] $createdId)) {
                try {
                    Remove-NewlyCreatedGroupSafely `
                        -GroupId $createdId `
                        -GroupLabel $item.Spec.GroupLabel
                }
                catch {
                    throw (
                        "The new group '$($item.Spec.GroupLabel)' failed safe verification, " +
                        'and automated rollback failed or was blocked. A newly created group ' +
                        "with ID '$createdId' may remain. Manually inspect and remediate that " +
                        'exact object before rerunning; the system is not known to be clean. ' +
                        "Original failure: $operationFailure. " +
                        "Rollback detail: $($_.Exception.Message)"
                    )
                }

                throw (
                    "The new group '$($item.Spec.GroupLabel)' failed safe verification and " +
                    "was deleted by rollback. Original failure: $operationFailure"
                )
            }

            throw (
                "Creation or verification failed for '$($item.Spec.GroupLabel)', and Microsoft " +
                'Graph did not return a verifiable new object ID. Automated rollback was ' +
                'impossible; a newly created exact-name group may remain. Stop and resolve ' +
                "that group before rerunning. Original failure: $operationFailure"
            )
        }
    }
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
