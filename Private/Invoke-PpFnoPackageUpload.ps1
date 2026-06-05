function Invoke-PpFnoPackageUpload {
    <#
    .SYNOPSIS
        Uploads one Finance & Operations (xpp) package into Dataverse, ready to be deployed.

    .DESCRIPTION
        Prepares a single F&O package zip for deployment by:

          1. Reading fnomoduledefinition.json from the zip to discover its BuildType, PackageType,
             database-sync option and module name.
          2. Creating an msprov_fnopackage record that describes the package.
          3. Streaming the zip bytes into the record's msprov_packagepayload file column using the
             Web API chunked upload protocol (x-ms-transfer-mode: chunked, 4 MiB Content-Range PATCHes).
          4. Upserting an msprov_fnomodule record keyed on the module name.

        This only uploads the package; it does not start the F&O deployment. Trigger the deployment
        separately with Invoke-PpFnoDeploy, passing the FnoPackageId(s) returned here.

    .PARAMETER PackageFilePath
        Full path to one xpp .zip from a package's PackageAssets folder.

    .PARAMETER Context
        Authenticated API context from Get-PpApiContext.

    .OUTPUTS
        Hashtable with: FileName, FnoPackageId, ModuleName, BuildType, PackageType, DBSyncKind, SizeMB.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageFilePath,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context
    )

    if (-not (Test-Path $PackageFilePath)) { throw "Package file not found: $PackageFilePath" }

    # Option-set values expected by the msprov_fnopackage entity.
    $buildTypeMap   = @{ Full = 0; Incremental = 1; Delete = 2 }
    $packageTypeMap = @{ Dev = 0; Release = 1 }
    $dbSyncMap      = @{ None = 0; Full = 1; Module = 2; Incremental = 3 }

    $fileName = [IO.Path]::GetFileName($PackageFilePath)
    $sizeMB   = [math]::Round((Get-Item $PackageFilePath).Length / 1MB, 2)
    Write-Host "  Uploading F&O package: $fileName ($sizeMB MB)" -ForegroundColor Gray

    # --- Step 1: read the package manifest (fnomoduledefinition.json) from the zip --------------
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($PackageFilePath)
    try {
        $manifestEntry = $zip.Entries | Where-Object { $_.FullName -ieq 'fnomoduledefinition.json' } | Select-Object -First 1
        if (-not $manifestEntry) { throw "fnomoduledefinition.json not found at the root of $fileName." }

        $reader = [IO.StreamReader]::new($manifestEntry.Open())
        try { $manifestJson = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }

    $manifest = $manifestJson | ConvertFrom-Json
    if (-not $manifest.BuildType)   { throw "BuildType is missing from the manifest in $fileName." }
    if (-not $manifest.PackageType) { throw "PackageType is missing from the manifest in $fileName." }

    $buildTypeName   = $manifest.BuildType
    $packageTypeName = $manifest.PackageType
    $dbSyncName      = if ($manifest.DBSync -and $manifest.DBSync.SyncKind) { $manifest.DBSync.SyncKind } else { 'None' }
    $moduleName      = $manifest.Module.Name

    if (-not $buildTypeMap.ContainsKey($buildTypeName))     { throw "Unknown BuildType '$buildTypeName' in $fileName." }
    if (-not $packageTypeMap.ContainsKey($packageTypeName)) { throw "Unknown PackageType '$packageTypeName' in $fileName." }
    if (-not $dbSyncMap.ContainsKey($dbSyncName))           { $dbSyncName = 'None' }

    # The database-sync value carried alongside the option depends on the sync kind.
    $dbSyncValue = switch ($dbSyncName) {
        'Module'      { $moduleName }
        'Incremental' { $manifest.DBSync.Arguments }
        default       { '' }
    }

    # --- Step 2: create the msprov_fnopackage record --------------------------------------------
    $createBody = @{
        msprov_name          = $fileName
        msprov_buildtype     = $buildTypeMap[$buildTypeName]
        msprov_packagetype   = $packageTypeMap[$packageTypeName]
        msprov_dbsyncoptions = $dbSyncMap[$dbSyncName]
        msprov_dbsyncvalue   = $dbSyncValue
    } | ConvertTo-Json -Depth 5

    $createResponse  = Invoke-WebRequest -Uri "$($Context.ApiUrl)/msprov_fnopackages" -Method Post -Headers $Context.JsonHeaders -Body $createBody
    $createdEntityId = ($createResponse.Headers['OData-EntityId'] -replace '.*\(([0-9a-fA-F-]+)\).*', '$1')
    if (-not $createdEntityId) { throw "Could not read the new msprov_fnopackage id from the OData-EntityId header." }
    Write-Host "    Created package record: $createdEntityId" -ForegroundColor Green

    # --- Step 3: chunked upload of the zip into msprov_packagepayload ---------------------------
    # Web API chunked upload protocol:
    #   1) PATCH the file column with x-ms-transfer-mode:chunked -> returns a Location (upload session URL).
    #   2) PATCH the session URL with Content-Range: bytes <start>-<end>/<total> for each 4 MiB chunk.
    $initHeaders = @{
        Authorization        = "Bearer $($Context.AccessToken)"
        'x-ms-transfer-mode' = 'chunked'
        'x-ms-file-name'     = $fileName
    }
    $initUrl      = "$($Context.ApiUrl)/msprov_fnopackages($createdEntityId)/msprov_packagepayload"
    $initResponse = Invoke-WebRequest -Uri $initUrl -Method Patch -Headers $initHeaders
    $sessionUrl   = $initResponse.Headers['Location']
    if ($sessionUrl -is [array]) { $sessionUrl = $sessionUrl[0] }
    if (-not $sessionUrl) { throw "The chunked upload did not return a Location (session) header for $fileName." }

    $chunkSize  = 4194304    # 4 MiB
    $fileBytes  = [IO.File]::ReadAllBytes($PackageFilePath)
    $totalSize  = $fileBytes.Length
    $offset     = 0
    $chunkIndex = 0
    while ($offset -lt $totalSize) {
        $end   = [Math]::Min($offset + $chunkSize, $totalSize) - 1
        $chunk = $fileBytes[$offset..$end]
        $chunkHeaders = @{
            Authorization   = "Bearer $($Context.AccessToken)"
            'Content-Range' = "bytes $offset-$end/$totalSize"
            'Content-Type'  = 'application/octet-stream'
        }
        Invoke-WebRequest -Uri $sessionUrl -Method Patch -Headers $chunkHeaders -Body $chunk | Out-Null
        $chunkIndex++
        $offset = $end + 1
        Write-Host "    Uploaded chunk $chunkIndex ($([Math]::Round(($offset / $totalSize) * 100, 1))%)" -ForegroundColor DarkGray
    }
    Write-Host "    Upload complete: $chunkIndex chunk(s), $totalSize bytes" -ForegroundColor Green

    # --- Step 4: upsert the msprov_fnomodule record keyed on the module name --------------------
    if ($moduleName) {
        $upsertUrl  = "$($Context.ApiUrl)/msprov_fnomodules(msprov_name='$moduleName')"
        $upsertBody = @{ msprov_name = $moduleName } | ConvertTo-Json
        Invoke-WebRequest -Uri $upsertUrl -Method Patch -Headers $Context.JsonHeaders -Body $upsertBody | Out-Null
        Write-Host "    Registered module: $moduleName" -ForegroundColor Green
    }

    return @{
        FileName     = $fileName
        FnoPackageId = $createdEntityId
        ModuleName   = $moduleName
        BuildType    = $buildTypeName
        PackageType  = $packageTypeName
        DBSyncKind   = $dbSyncName
        SizeMB       = $sizeMB
    }
}
