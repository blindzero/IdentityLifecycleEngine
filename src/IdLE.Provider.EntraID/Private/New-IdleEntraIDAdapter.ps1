function New-IdleEntraIDAdapter {
    <#
    .SYNOPSIS
    Creates an internal adapter that wraps Microsoft Graph API operations.

    .DESCRIPTION
    This adapter provides a testable boundary between the provider and Graph API REST calls.
    Unit tests can inject a fake adapter without requiring a real Entra ID environment.

    The adapter uses direct REST calls to Microsoft Graph v1.0 endpoints for maximum portability.

    .PARAMETER BaseUri
    Base URI for Microsoft Graph API. Defaults to https://graph.microsoft.com/v1.0
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $BaseUri = 'https://graph.microsoft.com/v1.0'
    )

    $adapter = [pscustomobject]@{
        PSTypeName = 'IdLE.EntraIDAdapter'
        BaseUri    = $BaseUri.TrimEnd('/')
    }

    # Helper to invoke Graph API with error handling
    $invokeGraphRequest = {
        param(
            [Parameter(Mandatory)]
            [string] $Method,

            [Parameter(Mandatory)]
            [string] $Uri,

            [Parameter(Mandatory)]
            [string] $AccessToken,

            [Parameter()]
            [object] $Body,

            [Parameter()]
            [string] $ContentType = 'application/json'
        )

        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Content-Type'  = $ContentType
        }

        $params = @{
            Method      = $Method
            Uri         = $Uri
            Headers     = $headers
            ErrorAction = 'Stop'
        }

        if ($null -ne $Body) {
            if ($Body -is [string]) {
                $params['Body'] = $Body
            }
            else {
                $params['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
            }
        }

        try {
            $response = Invoke-RestMethod @params
            return $response
        }
        catch {
            $statusCode = $null
            $requestId = $null
            $retryAfter = $null

            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                if ($_.Exception.Response.Headers) {
                    $requestId = $_.Exception.Response.Headers['request-id']
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                }
            }

            # Classify transient errors
            $isTransient = $false
            if ($statusCode -ge 500 -or $statusCode -eq 429 -or $statusCode -eq 408) {
                $isTransient = $true
            }

            # Check for network/timeout errors
            if ($_.Exception.InnerException -is [System.Net.WebException] -or
                $_.Exception.Message -match 'timeout|timed out') {
                $isTransient = $true
            }

            # Build error message without exposing sensitive data
            $errorMessage = "Graph API request failed"
            if ($statusCode) {
                $errorMessage += " | Status: $statusCode"
            }
            if ($requestId) {
                $errorMessage += " | RequestId: $requestId"
            }
            if ($retryAfter) {
                $errorMessage += " | RetryAfter: $retryAfter"
            }
            
            # Do not include the full exception message as it might contain tokens or sensitive data
            # Only include safe error details

            $ex = [System.Exception]::new($errorMessage, $_.Exception)
            if ($isTransient) {
                $ex.Data['Idle.IsTransient'] = $true
            }

            throw $ex
        }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name InvokeGraphRequest -Value $invokeGraphRequest -Force

    # Helper to handle paging
    $getAllPages = {
        param(
            [Parameter(Mandatory)]
            [string] $Uri,

            [Parameter(Mandatory)]
            [string] $AccessToken
        )

        $allItems = @()
        $nextLink = $Uri

        while ($null -ne $nextLink) {
            $response = $this.InvokeGraphRequest('GET', $nextLink, $AccessToken, $null)

            if ($response.value) {
                $allItems += $response.value
            }

            $nextLink = $response.'@odata.nextLink'
        }

        return $allItems
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name GetAllPages -Value $getAllPages -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users/$ObjectId"
        $uri += '?$select=id,userPrincipalName,mail,displayName,givenName,surname,accountEnabled,department,jobTitle,officeLocation,companyName'

        try {
            $user = $this.InvokeGraphRequest('GET', $uri, $AccessToken, $null)
            return $user
        }
        catch {
            if ($_.Exception.Message -match '404|not found|does not exist') {
                return $null
            }
            throw
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Upn,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        # URL encode the UPN for the filter
        $encodedUpn = [System.Net.WebUtility]::UrlEncode($Upn)
        $uri = "$($this.BaseUri)/users?`$filter=userPrincipalName eq '$encodedUpn'"
        $uri += '&$select=id,userPrincipalName,mail,displayName,givenName,surname,accountEnabled,department,jobTitle,officeLocation,companyName'

        $users = $this.InvokeGraphRequest('GET', $uri, $AccessToken, $null)

        if ($users.value -and $users.value.Count -gt 0) {
            return $users.value[0]
        }

        return $null
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Mail,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        # URL encode the mail for the filter
        $encodedMail = [System.Net.WebUtility]::UrlEncode($Mail)
        $uri = "$($this.BaseUri)/users?`$filter=mail eq '$encodedMail'"
        $uri += '&$select=id,userPrincipalName,mail,displayName,givenName,surname,accountEnabled,department,jobTitle,officeLocation,companyName'

        $users = $this.InvokeGraphRequest('GET', $uri, $AccessToken, $null)

        if ($users.value -and $users.value.Count -gt 0) {
            return $users.value[0]
        }

        return $null
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Payload,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users"
        $user = $this.InvokeGraphRequest('POST', $uri, $AccessToken, $Payload)
        return $user
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name PatchUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Payload,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users/$ObjectId"
        $null = $this.InvokeGraphRequest('PATCH', $uri, $AccessToken, $Payload)
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users/$ObjectId"
        $null = $this.InvokeGraphRequest('DELETE', $uri, $AccessToken, $null)
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name ListUsers -Value {
        param(
            [Parameter()]
            [hashtable] $Filter,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users"
        $uri += '?$select=id,userPrincipalName,mail'

        if ($null -ne $Filter -and $Filter.ContainsKey('Search') -and -not [string]::IsNullOrWhiteSpace($Filter['Search'])) {
            $searchValue = [string]$Filter['Search']
            $encodedSearch = [System.Net.WebUtility]::UrlEncode($searchValue)
            $uri += "&`$filter=startswith(userPrincipalName,'$encodedSearch') or startswith(displayName,'$encodedSearch')"
        }

        $users = $this.GetAllPages($uri, $AccessToken)
        return $users
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        # Try as GUID first
        $uri = "$($this.BaseUri)/groups/$GroupId"
        $uri += '?$select=id,displayName,mail,mailNickname'

        try {
            $group = $this.InvokeGraphRequest('GET', $uri, $AccessToken, $null)
            return $group
        }
        catch {
            if ($_.Exception.Message -match '404|not found|does not exist') {
                return $null
            }
            throw
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $DisplayName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $encodedName = [System.Net.WebUtility]::UrlEncode($DisplayName)
        $uri = "$($this.BaseUri)/groups?`$filter=displayName eq '$encodedName'"
        $uri += '&$select=id,displayName,mail,mailNickname'

        $groups = $this.InvokeGraphRequest('GET', $uri, $AccessToken, $null)

        if (-not $groups.value -or $groups.value.Count -eq 0) {
            return $null
        }

        if ($groups.value.Count -gt 1) {
            throw "Multiple groups found with displayName '$DisplayName'. Use objectId for deterministic lookup."
        }

        return $groups.value[0]
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name ListUserGroups -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users/$ObjectId/memberOf"
        $uri += '?$select=id,displayName,mail'

        $groups = $this.GetAllPages($uri, $AccessToken)
        return $groups
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $UserObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/groups/$GroupObjectId/members/`$ref"
        $body = @{
            '@odata.id' = "$($this.BaseUri)/directoryObjects/$UserObjectId"
        }

        try {
            $null = $this.InvokeGraphRequest('POST', $uri, $AccessToken, $body)
        }
        catch {
            # Idempotency: if already a member, treat as success
            if ($_.Exception.Message -match 'already exists|already a member') {
                return
            }
            throw
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $UserObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/groups/$GroupObjectId/members/$UserObjectId/`$ref"

        try {
            $null = $this.InvokeGraphRequest('DELETE', $uri, $AccessToken, $null)
        }
        catch {
            # Idempotency: if not a member, treat as success
            if ($_.Exception.Message -match '404|not found|does not exist') {
                return
            }
            throw
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name RevokeSignInSessions -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ObjectId,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AccessToken
        )

        $uri = "$($this.BaseUri)/users/$ObjectId/revokeSignInSessions"
        
        try {
            $response = $this.InvokeGraphRequest('POST', $uri, $AccessToken, $null)
            # Graph returns { "@odata.context": "...", "value": true/false }
            # The value indicates whether sessions were revoked
            return $response
        }
        catch {
            # If user not found or other errors, let them propagate
            throw
        }
    } -Force

    return $adapter
}
