function Assert-IdleNoCredentialObject {
    <#
    .SYNOPSIS
    Asserts that the provided object does not contain PSCredential or SecureString objects.

    .DESCRIPTION
    Recursively walks hashtables, enumerables and PSCustomObjects. Used for step State, which later steps
    can read: authentication material must be acquired via the AuthSessionBroker, never passed between steps.

    .PARAMETER InputObject
    The object to validate.

    .PARAMETER Path
    Logical path of InputObject, used in error messages.

    .OUTPUTS
    None. Throws an ArgumentException if a credential object is found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if ($null -eq $InputObject) { return }

    if ($InputObject -is [System.Management.Automation.PSCredential] -or $InputObject -is [System.Security.SecureString]) {
        throw [System.ArgumentException]::new(
            "Credential objects ($($InputObject.GetType().Name)) are not allowed. Found at: $Path",
            $Path
        )
    }

    if ($InputObject -is [string] -or $InputObject.GetType().IsValueType) { return }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            Assert-IdleNoCredentialObject -InputObject $InputObject[$key] -Path "$Path.$key"
        }
        return
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $i = 0
        foreach ($item in $InputObject) {
            Assert-IdleNoCredentialObject -InputObject $item -Path "$Path[$i]"
            $i++
        }
        return
    }

    if ($InputObject -is [pscustomobject]) {
        foreach ($p in $InputObject.PSObject.Properties) {
            if ($p.MemberType -eq 'NoteProperty') {
                Assert-IdleNoCredentialObject -InputObject $p.Value -Path "$Path.$($p.Name)"
            }
        }
    }
}
