<#
    Example: start an asynchronous deployment and poll until it finishes.

    Fill in your own environment URL, app-registration details, and package path.
    Run from the repo root so the relative module path resolves, or adjust the Import-Module path.
#>

Import-Module "$PSScriptRoot/../PowerPlatformAsyncDeploy.psd1" -Force

# --- Configure -------------------------------------------------------------------------------
$environmentUrl = 'https://your-org.crm.dynamics.com'
$tenantId       = '00000000-0000-0000-0000-000000000000'
$clientId       = '00000000-0000-0000-0000-000000000000'
$clientSecret   = $env:PP_CLIENT_SECRET   # keep secrets out of source; set this env var first
$packagePath    = 'C:\path\to\unzipped\package'   # folder containing PackageAssets\ImportConfig.xml
$stateFile      = './pp-async-deployment-state.json'

$connectionString = "AuthType=ClientSecret;Url=$environmentUrl;Tenant=$tenantId;ClientId=$clientId;ClientSecret=$clientSecret"

# --- Start the deployment (returns immediately) ----------------------------------------------
Start-PpAsyncDeployment `
    -PackagePath $packagePath `
    -ConnectionString $connectionString `
    -StateFilePath $stateFile

# --- Poll until everything reaches a terminal state ------------------------------------------
do {
    Start-Sleep -Seconds 60
    $status = Get-PpAsyncDeploymentStatus -StateFilePath $stateFile
} while ($status.OverallStatus -eq 'InProgress')

Write-Host "`nFinal status: $($status.OverallStatus)" -ForegroundColor Cyan
