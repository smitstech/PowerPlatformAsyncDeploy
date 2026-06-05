@{
    RootModule        = 'PowerPlatformAsyncDeploy.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b9f7e3a2-4c81-4d6e-9a2f-1c7d5e8b3f04'
    Author            = 'SmitsTech'
    Description       = 'Start and monitor asynchronous Power Platform package deployments (Dataverse solutions and Finance & Operations packages) against the Dataverse Web API.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Start-PpAsyncDeployment',
        'Get-PpAsyncDeploymentStatus'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('PowerPlatform', 'Dataverse', 'Dynamics365', 'Deployment', 'Async', 'FinanceAndOperations')
            ProjectUri   = 'https://github.com/your-org/PowerPlatformAsyncDeploy'
            LicenseUri   = 'https://github.com/your-org/PowerPlatformAsyncDeploy/blob/main/LICENSE'
            ReleaseNotes = 'Initial release: Start-PpAsyncDeployment and Get-PpAsyncDeploymentStatus.'
        }
    }
}
