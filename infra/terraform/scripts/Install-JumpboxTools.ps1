[CmdletBinding()]
param(
    [string] $TerraformDirectory = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$raw = & terraform "-chdir=$TerraformDirectory" output -json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Terraform outputs.' }
$outputs = ($raw -join "`n") | ConvertFrom-Json
if (-not $outputs.validation_vm_name.value) { throw 'This workspace has no validation VM.' }
$subscription = ($outputs.project_id.value -split '/')[2]

function Encode-Text([string] $Text) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

$smoke = Encode-Text (Get-Content (Join-Path $PSScriptRoot 'smoke_test.py') -Raw)
$chat = Encode-Text (Get-Content (Join-Path $PSScriptRoot 'chat_agent.py') -Raw)
$config = Encode-Text (@{ project_endpoint = $outputs.project_endpoint.value } | ConvertTo-Json -Compress)
$script = @"
set -eu
install -d -o azureuser -g azureuser -m 0755 /home/azureuser/foundry-jumpbox
printf '%s' '$smoke' | base64 -d > /home/azureuser/foundry-jumpbox/smoke_test.py
printf '%s' '$chat' | base64 -d > /home/azureuser/foundry-jumpbox/chat_agent.py
printf '%s' '$config' | base64 -d > /home/azureuser/foundry-jumpbox/jumpbox-config.json
chown azureuser:azureuser /home/azureuser/foundry-jumpbox/smoke_test.py /home/azureuser/foundry-jumpbox/chat_agent.py /home/azureuser/foundry-jumpbox/jumpbox-config.json
chmod 0644 /home/azureuser/foundry-jumpbox/smoke_test.py /home/azureuser/foundry-jumpbox/chat_agent.py /home/azureuser/foundry-jumpbox/jumpbox-config.json
printf 'FOUNDRY_JUMPBOX_TOOLS_READY\n'
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
if ($messages -notmatch 'FOUNDRY_JUMPBOX_TOOLS_READY') {
    throw "Jumpbox tools were not installed. Run Command output: $messages"
}
Write-Output 'Jumpbox tools installed under /home/azureuser/foundry-jumpbox.'
