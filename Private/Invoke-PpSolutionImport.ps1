function Invoke-PpSolutionImport {
    <#
    .SYNOPSIS
        Submits a Dataverse solution for asynchronous import and returns its async operation id.

    .DESCRIPTION
        Reads a solution .zip, base64-encodes it, and submits it to the Dataverse Web API using the
        ExecuteAsync wrapper around an ImportSolutionRequest. The call returns immediately with an
        async operation id; the server continues the import in the background. Poll the
        asyncoperations entity (see Get-PpAsyncDeploymentStatus) to track completion.

    .PARAMETER SolutionFilePath
        Full path to the solution .zip file.

    .PARAMETER Context
        Authenticated API context from Get-PpApiContext.

    .PARAMETER OverwriteUnmanagedCustomizations
        Passed through to ImportSolutionRequest. Default $false.

    .PARAMETER PublishWorkflows
        Passed through to ImportSolutionRequest. Default $true.

    .PARAMETER SkipProductUpdateDependencies
        Passed through to ImportSolutionRequest. Default $false.

    .OUTPUTS
        Hashtable with: AsyncOperationId, SolutionFileName, StartTime, SizeMB.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SolutionFilePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $false)]
        [bool]$OverwriteUnmanagedCustomizations = $false,

        [Parameter(Mandatory = $false)]
        [bool]$PublishWorkflows = $true,

        [Parameter(Mandatory = $false)]
        [bool]$SkipProductUpdateDependencies = $false
    )

    if (-not (Test-Path $SolutionFilePath)) { throw "Solution file not found: $SolutionFilePath" }

    $solutionBytes  = [System.IO.File]::ReadAllBytes($SolutionFilePath)
    $solutionBase64 = [Convert]::ToBase64String($solutionBytes)
    $fileName       = [System.IO.Path]::GetFileName($SolutionFilePath)
    $sizeMB         = [math]::Round($solutionBytes.Length / 1MB, 2)

    Write-Host "  Submitting solution: $fileName ($sizeMB MB)" -ForegroundColor Gray

    # ExecuteAsync wraps a single message request; here an ImportSolutionRequest.
    $body = @{
        Request = @{
            '@odata.type'                    = 'Microsoft.Dynamics.CRM.ImportSolutionRequest'
            CustomizationFile                = $solutionBase64
            OverwriteUnmanagedCustomizations = $OverwriteUnmanagedCustomizations
            PublishWorkflows                 = $PublishWorkflows
            SkipProductUpdateDependencies    = $SkipProductUpdateDependencies
        }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri "$($Context.ApiUrl)/ExecuteAsync" -Method Post -Headers $Context.JsonHeaders -Body $body
    }
    catch {
        $detail = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($detail) { throw "Failed to start async import for $fileName : $($detail.error.message)" }
        throw "Failed to start async import for $fileName : $_"
    }

    $asyncOperationId = $response.AsyncOperationId
    if (-not $asyncOperationId) { throw "ExecuteAsync did not return an AsyncOperationId for $fileName." }

    Write-Host "    Async operation started: $asyncOperationId" -ForegroundColor Green

    return @{
        AsyncOperationId = $asyncOperationId
        SolutionFileName = $fileName
        StartTime        = Get-Date
        SizeMB           = $sizeMB
    }
}
