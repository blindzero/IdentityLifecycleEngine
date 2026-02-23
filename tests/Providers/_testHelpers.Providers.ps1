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
