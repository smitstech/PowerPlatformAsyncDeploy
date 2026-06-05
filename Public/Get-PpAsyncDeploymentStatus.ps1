function Get-PpAsyncDeploymentStatus {
    <#
    .SYNOPSIS
        Reports the live status of a deployment started by Start-PpAsyncDeployment.

    .DESCRIPTION
        Reads the JSON state file written by Start-PpAsyncDeployment and queries the Dataverse
        asyncoperations entity for every tracked operation:

            - one per Dataverse solution import, and
            - one for the Finance & Operations package batch (if the package contained F&O packages).

        It prints a per-operation summary and returns a structured result that includes a derived
        OverallStatus of InProgress, Succeeded, or Failed. Because the operations run server-side,
        you can call this from any session - even after closing the one that started the deployment -
        as long as you point it at the same state file.

        Async operation status codes:
            0  Waiting For Resources      21 Pausing        30 Succeeded
            10 Waiting                    22 Canceling      31 Failed
            20 In Progress                                  32 Canceled

    .PARAMETER StateFilePath
        Path to the JSON state file written by Start-PpAsyncDeployment.
        Defaults to ./pp-async-deployment-state.json.

    .EXAMPLE
        Get-PpAsyncDeploymentStatus -StateFilePath './pp-async-deployment-state.json'

        Prints the status of every solution import and the F&O batch, then returns the result object.

    .EXAMPLE
        do {
            $status = Get-PpAsyncDeploymentStatus
            Start-Sleep -Seconds 60
        } while ($status.OverallStatus -eq 'InProgress')

        Polls once a minute until the deployment finishes.

    .OUTPUTS
        Hashtable with: DeploymentId, Solution (array of per-solution status), Fno (batch status),
        and OverallStatus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StateFilePath = './pp-async-deployment-state.json'
    )

    if (-not (Test-Path $StateFilePath)) { throw "State file not found: $StateFilePath" }

    $state   = Get-Content $StateFilePath | ConvertFrom-Json
    $context = Get-PpApiContext -ConnectionString $state.ConnectionString

    $statusMap = @{
        0  = 'Waiting For Resources'
        10 = 'Waiting'
        20 = 'In Progress'
        21 = 'Pausing'
        22 = 'Canceling'
        30 = 'Succeeded'
        31 = 'Failed'
        32 = 'Canceled'
    }

    function Get-OperationStatus {
        param([string]$Id)
        if (-not $Id) { return $null }
        $select = 'asyncoperationid,name,statecode,statuscode,message,friendlymessage,errorcode,startedon,completedon'
        $url    = "$($context.ApiUrl)/asyncoperations($Id)?`$select=$select"
        $r      = Invoke-RestMethod -Uri $url -Method Get -Headers $context.JsonHeaders
        $code   = [int]$r.statuscode
        return @{
            AsyncOperationId = $r.asyncoperationid
            Name             = $r.name
            StatusCode       = $code
            StatusText       = if ($statusMap.ContainsKey($code)) { $statusMap[$code] } else { "Unknown ($code)" }
            Message          = $r.message
            FriendlyMessage  = $r.friendlymessage
            ErrorCode        = $r.errorcode
            StartedOn        = $r.startedon
            CompletedOn      = $r.completedon
            IsTerminal       = $code -in @(30, 31, 32)
            IsSuccess        = $code -eq 30
        }
    }

    function Write-StatusLine {
        param($Label, $Status)
        $icon = switch ($Status.StatusCode) { 30 { '[OK]' } 31 { '[X]' } 32 { '[-]' } default { '[..]' } }
        $color = switch ($Status.StatusCode) { 30 { 'Green' } 31 { 'Red' } 32 { 'Yellow' } default { 'Cyan' } }
        Write-Host "  $icon $Label - $($Status.StatusText)" -ForegroundColor $color
        if ($Status.FriendlyMessage) { Write-Host "       $($Status.FriendlyMessage)" -ForegroundColor Gray }
        elseif ($Status.Message)     { Write-Host "       $($Status.Message)" -ForegroundColor Gray }
    }

    Write-Host "`nDeployment: $($state.DeploymentId)" -ForegroundColor Cyan
    Write-Host "Started:    $($state.StartTime)" -ForegroundColor Gray
    Write-Host ""

    $results = @{
        DeploymentId = $state.DeploymentId
        Solution     = @()
        Fno          = $null
    }
    $allTerminal = $true
    $anyFailed   = $false

    if ($state.Solution) {
        Write-Host "Dataverse solutions:" -ForegroundColor Yellow
        foreach ($s in $state.Solution) {
            $st = Get-OperationStatus -Id $s.AsyncOperationId
            Write-StatusLine $s.FileName $st
            if (-not $st.IsTerminal)          { $allTerminal = $false }
            if ($st.StatusCode -in @(31, 32)) { $anyFailed = $true }
            $results.Solution += @{ FileName = $s.FileName; Status = $st }
        }
    }

    if ($state.Fno) {
        Write-Host "`nF&O batch ($($state.Fno.Packages.Count) package(s), $($state.Fno.BuildType)/$($state.Fno.PackageType)):" -ForegroundColor Yellow
        $st = Get-OperationStatus -Id $state.Fno.AsyncOperationId
        Write-StatusLine 'Finance & Operations deployment' $st
        if (-not $st.IsTerminal)          { $allTerminal = $false }
        if ($st.StatusCode -in @(31, 32)) { $anyFailed = $true }
        $results.Fno = @{
            AsyncOperationId = $state.Fno.AsyncOperationId
            Packages         = $state.Fno.Packages
            Status           = $st
        }
        foreach ($p in $state.Fno.Packages) {
            Write-Host "       - $($p.FileName)" -ForegroundColor DarkGray
        }
    }

    $overall = if (-not $allTerminal) { 'InProgress' } elseif ($anyFailed) { 'Failed' } else { 'Succeeded' }
    $results.OverallStatus = $overall
    $color = switch ($overall) { 'Succeeded' { 'Green' } 'Failed' { 'Red' } default { 'Cyan' } }
    Write-Host "`nOverall: $overall" -ForegroundColor $color

    return $results
}
