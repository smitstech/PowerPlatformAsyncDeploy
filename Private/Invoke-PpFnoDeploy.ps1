function Invoke-PpFnoDeploy {
    <#
    .SYNOPSIS
        Starts asynchronous deployment of one or more already-uploaded F&O packages.

    .DESCRIPTION
        Calls the msprov_deploypackagetofinopsasync custom action over the Dataverse Web API. This is
        the server-side entry point that takes msprov_fnopackage records (created by
        Invoke-PpFnoPackageUpload) and begins the Finance & Operations deployment. The call returns a
        single async operation id that covers the whole batch; poll the asyncoperations entity to
        track completion.

        All packages submitted in one call must share the same BuildType and PackageType.

    .PARAMETER FnoPackageIds
        One or more msprov_fnopackage record GUIDs to deploy together.

    .PARAMETER BuildType
        Full | Incremental | Delete - must match the uploaded packages' BuildType.

    .PARAMETER PackageType
        Dev | Release - must match the uploaded packages' PackageType.

    .PARAMETER Context
        Authenticated API context from Get-PpApiContext.

    .OUTPUTS
        Hashtable with: AsyncOperationId, PackageCount, BuildType, PackageType, StartTime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$FnoPackageIds,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Incremental', 'Delete')]
        [string]$BuildType,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Dev', 'Release')]
        [string]$PackageType,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    if ($FnoPackageIds.Count -eq 0) { throw "FnoPackageIds is empty - there is nothing to deploy." }

    $buildTypeMap   = @{ Full = 0; Incremental = 1; Delete = 2 }
    $packageTypeMap = @{ Dev = 0; Release = 1 }

    # The action's finopspackages parameter is an entity collection of msprov_fnopackage references.
    $finopsPackages = @($FnoPackageIds | ForEach-Object {
        @{
            '@odata.type'       = 'Microsoft.Dynamics.CRM.msprov_fnopackage'
            msprov_fnopackageid = $_
        }
    })

    $body = @{
        finopspackages = $finopsPackages
        packagetype    = @{ Value = $packageTypeMap[$PackageType] }
        buildtype      = @{ Value = $buildTypeMap[$BuildType] }
    } | ConvertTo-Json -Depth 10

    $startTime = Get-Date
    Write-Host "  Dispatching F&O deployment for $($FnoPackageIds.Count) package(s) [$BuildType/$PackageType]" -ForegroundColor Gray

    $response = Invoke-RestMethod -Uri "$($Context.ApiUrl)/msprov_deploypackagetofinopsasync" -Method Post -Headers $Context.JsonHeaders -Body $body

    # The response shape is { "asyncoperationid": { ... "asyncoperationid": "<guid>" } } or a bare guid.
    $asyncOpRef = $response.asyncoperationid
    $asyncOpId  = if ($asyncOpRef -is [string]) { $asyncOpRef } elseif ($asyncOpRef.asyncoperationid) { $asyncOpRef.asyncoperationid } else { $asyncOpRef.Id }
    if (-not $asyncOpId) { throw "msprov_deploypackagetofinopsasync did not return an async operation id." }

    Write-Host "    Async operation started: $asyncOpId" -ForegroundColor Green

    return @{
        AsyncOperationId = $asyncOpId
        PackageCount     = $FnoPackageIds.Count
        BuildType        = $BuildType
        PackageType      = $PackageType
        StartTime        = $startTime
    }
}
