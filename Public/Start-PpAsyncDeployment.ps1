function Start-PpAsyncDeployment {
    <#
    .SYNOPSIS
        Starts an asynchronous deployment of a Power Platform package and returns immediately.

    .DESCRIPTION
        Deploys the artifacts inside an unzipped Power Platform deployment package without blocking
        the caller. The function reads the package's ImportConfig.xml, then submits each artifact to
        the Dataverse Web API using the appropriate asynchronous path:

            - Dataverse solutions are submitted with ExecuteAsync(ImportSolutionRequest); each one
              returns its own async operation id.
            - Finance & Operations (xpp) packages are uploaded one at a time and then deployed
              together in a single call that returns one async operation id for the whole batch.

        Every submission happens server-side and continues after this function returns. All the
        identifiers needed to follow the work are written to a JSON state file, so you can close your
        session and check progress later with Get-PpAsyncDeploymentStatus.

        All F&O packages in one package must share the same BuildType and PackageType; the function
        reads them from the first package's manifest and verifies the rest match.

    .PARAMETER PackagePath
        Path to the unzipped package folder. It must contain a PackageAssets sub-folder with an
        ImportConfig.xml manifest and the referenced solution/package files.

    .PARAMETER ConnectionString
        Dataverse connection string used to authenticate. Format:
            "AuthType=ClientSecret;Url=https://org.crm.dynamics.com;Tenant=<tenant-id>;ClientId=<app-id>;ClientSecret=<secret>"

    .PARAMETER DeploymentId
        Optional friendly identifier for this run. Defaults to deploy-<timestamp>.

    .PARAMETER StateFilePath
        Where to write the deployment state JSON. Defaults to ./pp-async-deployment-state.json.
        This file records the connection string and async operation ids; treat it as a secret.

    .PARAMETER OverwriteUnmanagedCustomizations
        Passed through to each solution import. Default $false.

    .PARAMETER PublishWorkflows
        Passed through to each solution import. Default $true.

    .EXAMPLE
        $conn = "AuthType=ClientSecret;Url=https://contoso.crm.dynamics.com;Tenant=$tenant;ClientId=$appId;ClientSecret=$secret"
        Start-PpAsyncDeployment -PackagePath 'C:\MyPackage' -ConnectionString $conn

        Reads C:\MyPackage\PackageAssets\ImportConfig.xml, submits every solution and F&O package,
        and writes ./pp-async-deployment-state.json.

    .EXAMPLE
        Start-PpAsyncDeployment -PackagePath 'C:\MyPackage' -ConnectionString $conn `
            -DeploymentId 'release-2024-11' -StateFilePath 'C:\deploys\release-2024-11.json'

        Same, but with a named deployment and a custom state-file location.

    .OUTPUTS
        Hashtable with: DeploymentId, StateFilePath, Solution (solution results), Fno (F&O batch result).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$ConnectionString,

        [Parameter(Mandatory = $false)]
        [string]$DeploymentId,

        [Parameter(Mandatory = $false)]
        [string]$StateFilePath = './pp-async-deployment-state.json',

        [Parameter(Mandatory = $false)]
        [bool]$OverwriteUnmanagedCustomizations = $false,

        [Parameter(Mandatory = $false)]
        [bool]$PublishWorkflows = $true
    )

    # --- Validate inputs ------------------------------------------------------------------------
    if (-not (Test-Path $PackagePath)) { throw "Package path not found: $PackagePath" }
    $packageAssets = Join-Path $PackagePath 'PackageAssets'
    if (-not (Test-Path $packageAssets)) { throw "PackageAssets folder not found: $packageAssets" }
    $configXml = Join-Path $packageAssets 'ImportConfig.xml'
    if (-not (Test-Path $configXml)) { throw "ImportConfig.xml not found: $configXml" }

    if (-not $DeploymentId) { $DeploymentId = "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }

    Write-Host "`nStart-PpAsyncDeployment" -ForegroundColor Cyan
    Write-Host "Deployment: $DeploymentId" -ForegroundColor Green
    Write-Host "Package:    $PackagePath"

    # --- Read the manifest and sort artifacts ---------------------------------------------------
    $entries      = Import-PpConfigXml -ConfigPath $configXml -PackageAssetsPath $packageAssets
    $solutions    = @($entries | Where-Object { $_.Type -eq 'main' })
    $xppPackages  = @($entries | Where-Object { $_.Type -eq 'external' -and $_.PackageType -eq 'xpp' })
    $otherEntries = @($entries | Where-Object { $_.Type -eq 'external' -and $_.PackageType -ne 'xpp' })

    Write-Host "Found: $($solutions.Count) Dataverse solution(s), $($xppPackages.Count) F&O package(s), $($otherEntries.Count) other external entry(s)" -ForegroundColor Gray
    if ($otherEntries.Count -gt 0) {
        Write-Warning "External entries with a type other than 'xpp' are not handled and will be skipped: $($otherEntries.FileName -join ', ')"
    }

    # --- Authenticate once and reuse the context ------------------------------------------------
    $context = Get-PpApiContext -ConnectionString $ConnectionString

    $state = @{
        DeploymentId     = $DeploymentId
        StartTime        = (Get-Date).ToString('o')
        PackagePath      = $PackagePath
        ConnectionString = $ConnectionString
        Status           = 'InProgress'
        Solution         = $null
        Fno              = $null
    }

    # --- Dataverse solutions: one async import each ---------------------------------------------
    if ($solutions.Count -gt 0) {
        Write-Host "`nSubmitting $($solutions.Count) Dataverse solution(s)..." -ForegroundColor Cyan
        $solutionResults = @()
        foreach ($solution in $solutions) {
            $r = Invoke-PpSolutionImport `
                -SolutionFilePath $solution.FullPath `
                -Context $context `
                -OverwriteUnmanagedCustomizations $OverwriteUnmanagedCustomizations `
                -PublishWorkflows $PublishWorkflows
            $solutionResults += @{
                FileName         = $solution.FileName
                AsyncOperationId = $r.AsyncOperationId
                StartTime        = $r.StartTime.ToString('o')
            }
        }
        $state.Solution = $solutionResults
    }

    # --- F&O packages: upload each, then deploy the batch in one call ---------------------------
    if ($xppPackages.Count -gt 0) {
        Write-Host "`nUploading $($xppPackages.Count) F&O package(s)..." -ForegroundColor Cyan
        $uploaded      = @()
        $sharedBuild   = $null
        $sharedPackage = $null
        foreach ($pkg in $xppPackages) {
            $u = Invoke-PpFnoPackageUpload -PackageFilePath $pkg.FullPath -Context $context
            $uploaded += $u
            if (-not $sharedBuild)   { $sharedBuild = $u.BuildType }
            if (-not $sharedPackage) { $sharedPackage = $u.PackageType }
            if ($u.BuildType -ne $sharedBuild)     { throw "Mismatched BuildType in batch: $($u.FileName) reports $($u.BuildType) but an earlier package was $sharedBuild." }
            if ($u.PackageType -ne $sharedPackage) { throw "Mismatched PackageType in batch: $($u.FileName) reports $($u.PackageType) but an earlier package was $sharedPackage." }
        }

        $state.Fno = @{
            Packages         = $uploaded | ForEach-Object { @{ FileName = $_.FileName; FnoPackageId = $_.FnoPackageId; ModuleName = $_.ModuleName } }
            BuildType        = $sharedBuild
            PackageType      = $sharedPackage
            AsyncOperationId = $null
        }

        $deploy = Invoke-PpFnoDeploy `
            -FnoPackageIds @($uploaded | ForEach-Object { $_.FnoPackageId }) `
            -BuildType $sharedBuild `
            -PackageType $sharedPackage `
            -Context $context
        $state.Fno.AsyncOperationId = $deploy.AsyncOperationId
    }

    # --- Persist state for later status checks --------------------------------------------------
    $state | ConvertTo-Json -Depth 10 | Set-Content $StateFilePath

    Write-Host "`nDeployment dispatched. State file: $StateFilePath" -ForegroundColor Green
    Write-Host "Check status with:" -ForegroundColor Yellow
    Write-Host "  Get-PpAsyncDeploymentStatus -StateFilePath '$StateFilePath'" -ForegroundColor White

    return @{
        DeploymentId  = $DeploymentId
        StateFilePath = $StateFilePath
        Solution      = $state.Solution
        Fno           = $state.Fno
    }
}
