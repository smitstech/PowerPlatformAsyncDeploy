<#
    Pipeline entry point: start an async deployment and wait for it to finish.

    Designed to be called from an Azure DevOps pipeline (YAML or classic). It imports the module,
    starts the deployment, polls until every operation reaches a terminal state, and throws if the
    result is anything other than Succeeded - so a failed deployment fails the pipeline.

    The client secret is read from the PP_CLIENT_SECRET environment variable (not a parameter) so it
    never appears in a task's argument list or logs. Map your secret pipeline variable to that env
    var in the task definition.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$EnvironmentUrl,
    [Parameter(Mandatory = $true)] [string]$TenantId,
    [Parameter(Mandatory = $true)] [string]$ClientId,
    [Parameter(Mandatory = $true)] [string]$PackagePath,
    [int]$PollSeconds    = 60,
    [int]$TimeoutMinutes = 120
)

$ErrorActionPreference = 'Stop'

$clientSecret = $env:PP_CLIENT_SECRET
if (-not $clientSecret) {
    throw "PP_CLIENT_SECRET environment variable is not set. Map your secret pipeline variable to it (see docs/azure-devops-pipeline.md)."
}

Import-Module (Join-Path $PSScriptRoot '..' 'PowerPlatformAsyncDeploy.psd1') -Force

$connectionString = "AuthType=ClientSecret;Url=$EnvironmentUrl;Tenant=$TenantId;ClientId=$ClientId;ClientSecret=$clientSecret"
$stateFile        = Join-Path $PWD 'pp-async-deployment-state.json'

Start-PpAsyncDeployment -PackagePath $PackagePath -ConnectionString $connectionString -StateFilePath $stateFile | Out-Null

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
do {
    Start-Sleep -Seconds $PollSeconds
    $status = Get-PpAsyncDeploymentStatus -StateFilePath $stateFile
    if ((Get-Date) -gt $deadline) {
        throw "Deployment timed out after $TimeoutMinutes minute(s); last status was '$($status.OverallStatus)'."
    }
} while ($status.OverallStatus -eq 'InProgress')

if ($status.OverallStatus -ne 'Succeeded') {
    throw "Deployment finished with status '$($status.OverallStatus)'. See the log above for the failing operation."
}

Write-Host "Deployment succeeded." -ForegroundColor Green
