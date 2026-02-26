Set-StrictMode -Version Latest

<#
.SYNOPSIS
Provider-specific test helpers for IdLE tests.

.DESCRIPTION
This file contains helper functions, fixtures, and test doubles specifically
related to provider testing.

This file is sourced by tests/_testHelpers.ps1 and should not be dot-sourced
directly by test files.
#>

# Provider-specific helpers will be added here as needed.

function Invoke-IdleTestBearerTokenError {
    <#
    .SYNOPSIS
    Test helper: throws an exception whose message contains a bearer token.

    .DESCRIPTION
    Used by adapter unit tests to verify that InvokeSafely correctly sanitizes
    bearer tokens from error messages without leaking sensitive data.
    #>
    [CmdletBinding()]
    param()

    throw 'Authentication failed: Bearer eyJhbGciOiJSUzI1NiJ9.payload.sig'
}

function Invoke-IdleEXOSimulateServerSideError {
    <#
    .SYNOPSIS
    Test helper: throws a server-side EXO error (transient pattern).

    .DESCRIPTION
    Used by InvokeSafely unit tests to verify that server-side Exchange Online
    errors are marked as transient so that the plan executor can retry the step.
    #>
    [CmdletBinding()]
    param()

    throw [System.Exception]::new('A server side error has occurred because of which the operation could not be completed.')
}

function Invoke-IdleEXOSimulateThrottleError {
    <#
    .SYNOPSIS
    Test helper: throws a throttling EXO error (transient pattern).

    .DESCRIPTION
    Used by InvokeSafely unit tests to verify that throttling Exchange Online
    errors are marked as transient so that the plan executor can retry the step.
    #>
    [CmdletBinding()]
    param()

    throw [System.Exception]::new('The request has been throttled due to too many requests.')
}

function Invoke-IdleEXOSimulatePermError {
    <#
    .SYNOPSIS
    Test helper: throws a non-transient permission EXO error.

    .DESCRIPTION
    Used by InvokeSafely unit tests to verify that non-transient Exchange Online
    errors are NOT marked as transient.
    #>
    [CmdletBinding()]
    param()

    throw [System.Exception]::new("Access denied. The user does not have the required permission.")
}
