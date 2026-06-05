function Get-PpApiContext {
    <#
    .SYNOPSIS
        Builds an authenticated Dataverse Web API context from a connection string.

    .DESCRIPTION
        Parses the connection string, acquires an OAuth access token from Microsoft Entra ID
        using the client-credentials flow, and returns a reusable context object containing the
        Web API base URL and the request headers (including the bearer token).

        Acquiring the context once and passing it to each call avoids re-authenticating for every
        solution import, package upload, or status query.

    .PARAMETER ConnectionString
        Dataverse connection string. Required keys:
            Url           - environment URL, e.g. https://org.crm.dynamics.com
            ClientId      - application (client) ID of the app registration (ApplicationId is also accepted)
            ClientSecret  - client secret for that app registration
        Optional keys:
            Tenant        - directory (tenant) ID; defaults to "common" when omitted

    .OUTPUTS
        PSCustomObject with:
            Url         - environment URL
            ApiUrl      - Web API base URL (…/api/data/v9.2)
            AccessToken - bearer token string
            JsonHeaders - hashtable of headers for JSON Web API calls
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString
    )

    $conn = ConvertFrom-PpConnectionString -ConnectionString $ConnectionString

    if (-not $conn['Url']) { throw "Connection string is missing the required 'Url' value." }

    $tenant   = if ($conn['Tenant']) { $conn['Tenant'] } else { 'common' }
    $clientId = if ($conn['ClientId']) { $conn['ClientId'] } else { $conn['ApplicationId'] }
    if (-not $clientId)             { throw "Connection string is missing 'ClientId' (or 'ApplicationId')." }
    if (-not $conn['ClientSecret']) { throw "Connection string is missing 'ClientSecret'." }

    $tokenUrl  = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $clientId
        client_secret = $conn['ClientSecret']
        scope         = "$($conn['Url'])/.default"
        grant_type    = 'client_credentials'
    }

    try {
        $token = (Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded').access_token
    }
    catch {
        throw "Failed to acquire an access token for $($conn['Url']): $_"
    }
    if (-not $token) { throw "The token endpoint returned an empty access token." }

    return [pscustomobject]@{
        Url         = $conn['Url']
        ApiUrl      = "$($conn['Url'])/api/data/v9.2"
        AccessToken = $token
        JsonHeaders = @{
            Authorization      = "Bearer $token"
            Accept             = 'application/json'
            'Content-Type'     = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
    }
}
