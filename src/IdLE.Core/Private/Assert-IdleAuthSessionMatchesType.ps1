function Assert-IdleAuthSessionMatchesType {
    <#
    .SYNOPSIS
    Validates that an auth session object matches the expected AuthSessionType.

    .DESCRIPTION
    Validates that an auth session object's runtime type is compatible with the
    declared AuthSessionType. This ensures that providers receive the expected
    session format for authentication.

    .PARAMETER AuthSessionType
    The expected authentication session type.

    .PARAMETER Session
    The authentication session object to validate.

    .PARAMETER SessionName
    The session name for error messages.

    .OUTPUTS
    None. Throws if validation fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OAuth', 'PSRemoting', 'Credential')]
        [string] $AuthSessionType,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Session,

        [Parameter()]
        [string] $SessionName = '<unnamed>'
    )

    if ($null -eq $Session) {
        throw "Auth session validation failed for '$SessionName': Session object is null."
    }

    switch ($AuthSessionType) {
        'Credential' {
            if ($Session -isnot [pscredential]) {
                $actualType = $Session.GetType().FullName
                throw "Auth session validation failed for '$SessionName': Expected AuthSessionType='Credential' requires a [PSCredential] object, but received [$actualType]."
            }
        }

        'OAuth' {
            # Accept multiple OAuth session shapes:
            # - [string] raw bearer token
            # - [PSCredential] with token in the Password field
            # - object with an AccessToken property
            # - object with a GetAccessToken() method
            $isValid = $false

            if ($Session -is [string]) {
                $isValid = $true
            }
            elseif ($Session -is [pscredential]) {
                $isValid = $true
            }
            elseif ($null -ne $Session) {
                $psObj = [System.Management.Automation.PSObject]::AsPSObject($Session)

                # Check for AccessToken property
                if ($psObj.Properties['AccessToken']) {
                    $isValid = $true
                }
                else {
                    # Check for GetAccessToken() method
                    $getTokenMethod = $psObj | Get-Member -Name GetAccessToken -MemberType Method -ErrorAction SilentlyContinue
                    if ($null -ne $getTokenMethod) {
                        $isValid = $true
                    }
                }
            }

            if (-not $isValid) {
                $actualType = $Session.GetType().FullName
                throw @"
Auth session validation failed for '$SessionName': Expected AuthSessionType='OAuth' requires one of:
- [string] raw access token
- [PSCredential] with the access token in the Password field
- object with an AccessToken property
- object with a GetAccessToken() method
but received [$actualType].
"@
            }
        }

        'PSRemoting' {
            # Accept PSSession objects or PSCredential for PSRemoting scenarios
            $validTypes = @(
                [System.Management.Automation.Runspaces.PSSession]
                [pscredential]
            )

            $isValid = $false
            foreach ($validType in $validTypes) {
                if ($Session -is $validType) {
                    $isValid = $true
                    break
                }
            }

            if (-not $isValid) {
                $actualType = $Session.GetType().FullName
                $expectedTypes = ($validTypes | ForEach-Object { "[$($_.FullName)]" }) -join ' or '
                throw "Auth session validation failed for '$SessionName': Expected AuthSessionType='PSRemoting' requires $expectedTypes, but received [$actualType]."
            }
        }
    }
}
