[CmdletBinding()]
param(
    [string] $TerraformDirectory = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$raw = & terraform "-chdir=$TerraformDirectory" output -json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Terraform outputs.' }
$outputs = ($raw -join "`n") | ConvertFrom-Json
$projectId = $outputs.project_id.value
$subscription = ($projectId -split '/')[2]
$accountId = $outputs.account_id.value
$projectHostId = $outputs.project_host_id.value

function Get-ArmJson([string] $ResourceId, [string] $ApiVersion) {
    $result = & az rest --method get --url "https://management.azure.com${ResourceId}?api-version=$ApiVersion" -o json
    if ($LASTEXITCODE -ne 0) { throw "ARM GET failed: $ResourceId" }
    return ($result -join "`n") | ConvertFrom-Json
}

$accountHosts = Get-ArmJson "$accountId/capabilityHosts" '2025-06-01'
if ($accountHosts.value.Count -ne 1 -or $accountHosts.value[0].properties.provisioningState -ne 'Succeeded') {
    throw 'Expected one successful account capability host.'
}
$hostResource = Get-ArmJson $projectHostId '2025-06-01'
if ($hostResource.properties.provisioningState -ne 'Succeeded') { throw 'Project host is not Succeeded.' }
$expectedHostConnections = @{
    storageConnections = 'storage'
    threadStorageConnections = 'cosmos'
    vectorStoreConnections = 'search'
}
foreach ($property in $expectedHostConnections.Keys) {
    $key = $expectedHostConnections[$property]
    $expected = $outputs.connection_names.value.$key
    $actual = @($hostResource.properties.$property)
    if ($actual.Count -ne 1 -or $actual[0] -ne $expected) { throw "Incorrect host binding: $property" }
    $connection = Get-ArmJson "$projectId/connections/$expected" '2025-06-01'
    if ($connection.properties.metadata.ResourceId -ne $outputs.backing_resources.value.$key) {
        throw "Incorrect ResourceId on connection $expected"
    }
    if ($connection.properties.authType -ne 'AAD' -or $connection.properties.target -notlike 'https://*') {
        throw "Incorrect auth/endpoint on connection $expected"
    }
}

$resources = @(
    @{ id = $accountId; api = '2025-06-01' },
    @{ id = $outputs.backing_resources.value.storage; api = '2025-01-01' },
    @{ id = $outputs.backing_resources.value.search; api = '2025-05-01' },
    @{ id = $outputs.backing_resources.value.cosmos; api = '2025-04-15' }
)
foreach ($resource in $resources) {
    $live = Get-ArmJson $resource.id $resource.api
    if ($live.properties.publicNetworkAccess -ine 'Disabled') { throw "Public access enabled: $($resource.id)" }
}
foreach ($endpoint in $outputs.private_endpoint_ids.value.PSObject.Properties) {
    $live = Get-ArmJson $endpoint.Value '2024-05-01'
    $connections = @($live.properties.privateLinkServiceConnections)
    if ($connections.Count -ne 1 -or $connections[0].properties.privateLinkServiceConnectionState.status -ne 'Approved') {
        throw "Private endpoint is not approved: $($endpoint.Name)"
    }
}
Write-Output 'Management-plane checks passed: host bindings, private endpoints, and public access.'

if (-not $outputs.validation_vm_name -or -not $outputs.model_deployment_name) {
    throw 'Runtime validation needs both the optional validation VM and model. Management checks passed; runtime was not tested.'
}
$endpoint = $outputs.project_endpoint.value
$model = $outputs.model_deployment_name.value
$storage = ($outputs.backing_resources.value.storage -split '/')[-1]
$search = ($outputs.backing_resources.value.search -split '/')[-1]
$cosmos = ($outputs.backing_resources.value.cosmos -split '/')[-1]
$python = Get-Content (Join-Path $PSScriptRoot 'smoke_test.py') -Raw
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($python))
$arguments = @(
    'foundry-terraform-smoke.py', '--endpoint', $endpoint, '--model', $model,
    '--storage', $storage, '--search', $search, '--cosmos', $cosmos
) | ConvertTo-Json -Compress
$encodedArguments = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($arguments))
$script = @"
set -eu
printf '%s' '$encoded' | base64 -d > /tmp/foundry-terraform-smoke.py
python3 -c "import base64,json,runpy,sys; sys.argv=json.loads(base64.b64decode('$encodedArguments')); runpy.run_path('/tmp/foundry-terraform-smoke.py',run_name='__main__')"
"@
$scriptFile = New-TemporaryFile
try {
    [IO.File]::WriteAllText($scriptFile.FullName, $script, [Text.UTF8Encoding]::new($false))
    $result = & az vm run-command invoke --subscription $subscription `
        --resource-group $outputs.resource_group_name.value `
        --name $outputs.validation_vm_name.value --command-id RunShellScript `
        --scripts "@$($scriptFile.FullName)" -o json
    if ($LASTEXITCODE -ne 0) { throw 'VM Run Command submission failed.' }
}
finally {
    Remove-Item -LiteralPath $scriptFile.FullName
}
$run = ($result -join "`n") | ConvertFrom-Json
$messages = @($run.value | ForEach-Object { $_.message }) -join "`n"
Write-Output $messages
if ($messages -notmatch '"agent_file_search_conversation": "passed"') {
    throw 'VM runtime smoke did not report success. Inspect stdout/stderr above; Run Command HTTP success alone is not sufficient.'
}
