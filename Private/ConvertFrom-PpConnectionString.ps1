function ConvertFrom-PpConnectionString {
    <#
    .SYNOPSIS
        Parses a Dataverse connection string into a hashtable of its key/value pairs.

    .DESCRIPTION
        Splits a connection string such as
            "AuthType=ClientSecret;Url=https://org.crm.dynamics.com;Tenant=<id>;ClientId=<id>;ClientSecret=<secret>"
        into a case-sensitive hashtable keyed by the segment name (Url, Tenant, ClientId, ...).
        Empty or malformed segments are ignored.

    .PARAMETER ConnectionString
        The Dataverse connection string to parse.

    .OUTPUTS
        Hashtable of connection-string keys to values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectionString
    )

    $params = @{}
    foreach ($segment in $ConnectionString.Split(';')) {
        $pair = $segment.Split('=', 2)
        if ($pair.Count -eq 2) {
            $params[$pair[0].Trim()] = $pair[1].Trim()
        }
    }
    return $params
}
