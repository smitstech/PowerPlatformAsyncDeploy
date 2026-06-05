function Import-PpConfigXml {
    <#
    .SYNOPSIS
        Reads a package's ImportConfig.xml and returns the ordered list of artifacts to deploy.

    .DESCRIPTION
        A Power Platform deployment package contains a PackageAssets folder with an ImportConfig.xml
        manifest. This function parses that manifest and returns one entry per artifact, preserving the
        order in which they are listed:

            - Dataverse solutions  (<solutions><configsolutionfile/>)        -> Type = "main"
            - External packages    (<externalpackages><package type="…"/>)   -> Type = "external"

        Each external package keeps its declared type (e.g. "xpp" for Finance & Operations packages)
        so the caller can route it to the correct deployment path.

    .PARAMETER ConfigPath
        Full path to the ImportConfig.xml file.

    .PARAMETER PackageAssetsPath
        Full path to the PackageAssets folder that holds the solution/package files.

    .OUTPUTS
        Array of hashtables, each with:
            FileName     - artifact file name
            FullPath     - absolute path to the file
            Type         - "main" (Dataverse solution) or "external"
            PackageType  - external package type (e.g. "xpp"); present only for external entries
            Order        - 1-based position in the manifest
            SizeBytes    - file size in bytes
            SizeMB       - file size in MB (rounded)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$PackageAssetsPath
    )

    if (-not (Test-Path $ConfigPath))        { throw "ImportConfig.xml not found at: $ConfigPath" }
    if (-not (Test-Path $PackageAssetsPath)) { throw "PackageAssets folder not found at: $PackageAssetsPath" }

    Write-Verbose "Reading ImportConfig.xml from: $ConfigPath"

    # ImportConfig.xml is commonly written as UTF-16; read it as Unicode so [xml] parses cleanly.
    [xml]$config = Get-Content -Path $ConfigPath -Encoding Unicode

    $entries = @()
    $order   = 1

    # Dataverse solutions, in manifest order.
    if ($config.configdatastorage.solutions.configsolutionfile) {
        foreach ($solution in $config.configdatastorage.solutions.configsolutionfile) {
            $fileName = $solution.solutionpackagefilename
            $fullPath = Join-Path $PackageAssetsPath $fileName

            if (-not (Test-Path $fullPath)) {
                Write-Warning "Solution file listed in ImportConfig.xml not found: $fullPath"
                continue
            }

            $entries += @{
                FileName  = $fileName
                FullPath  = $fullPath
                Type      = 'main'
                Order     = $order
                SizeBytes = (Get-Item $fullPath).Length
                SizeMB    = [math]::Round((Get-Item $fullPath).Length / 1MB, 2)
            }
            $order++
        }
    }

    # External packages (e.g. Finance & Operations xpp packages), in manifest order.
    if ($config.configdatastorage.externalpackages.package) {
        foreach ($package in $config.configdatastorage.externalpackages.package) {
            $fileName = $package.filename
            $fullPath = Join-Path $PackageAssetsPath $fileName

            if (-not (Test-Path $fullPath)) {
                Write-Warning "External package listed in ImportConfig.xml not found: $fullPath"
                continue
            }

            $entries += @{
                FileName    = $fileName
                FullPath    = $fullPath
                Type        = 'external'
                PackageType = $package.type
                Order       = $order
                SizeBytes   = (Get-Item $fullPath).Length
                SizeMB      = [math]::Round((Get-Item $fullPath).Length / 1MB, 2)
            }
            $order++
        }
    }

    if ($entries.Count -eq 0) {
        throw "No deployable artifacts were found in ImportConfig.xml."
    }

    Write-Verbose "Found $($entries.Count) artifact(s) to deploy."
    return $entries
}
