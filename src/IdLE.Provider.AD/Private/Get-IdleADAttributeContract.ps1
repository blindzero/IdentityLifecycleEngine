function Get-IdleADAttributeContract {
    <#
    .SYNOPSIS
    Returns the supported attribute contract for AD Provider operations.

    .DESCRIPTION
    Defines which attributes are supported for CreateIdentity and EnsureAttribute operations.
    This contract serves as the single source of truth for attribute validation.

    For EnsureAttribute, the contract lists named Set-ADUser parameters explicitly, plus a
    _BlockedAttributes meta-key that enumerates CreateIdentity-only attributes that must not
    be used with EnsureAttribute.  Any attribute name that is neither a named parameter nor in
    _BlockedAttributes is treated as a custom LDAP attribute and routed through
    Set-ADUser -Replace / -Clear automatically.

    .PARAMETER Operation
    The operation to get the contract for: 'CreateIdentity' or 'EnsureAttribute'.

    .OUTPUTS
    System.Collections.Hashtable
    Returns a hashtable where keys are supported attribute names and values contain metadata.
    For EnsureAttribute, the special key '_BlockedAttributes' lists forbidden attribute names.

    .EXAMPLE
    $contract = Get-IdleADAttributeContract -Operation 'CreateIdentity'
    $supportedKeys = $contract.Keys

    .EXAMPLE
    $contract = Get-IdleADAttributeContract -Operation 'EnsureAttribute'
    $namedKeys  = $contract.Keys | Where-Object { -not $_.StartsWith('_') }
    $blocked    = $contract['_BlockedAttributes'].Values
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CreateIdentity', 'EnsureAttribute')]
        [string] $Operation
    )

    if ($Operation -eq 'CreateIdentity') {
        return @{
            # Identity Attributes
            SamAccountName           = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            Path                     = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            
            # Name Attributes
            Name                     = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            GivenName                = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            Surname                  = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            
            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            Department               = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            Title                    = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            
            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            
            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            
            # Password Attributes
            AccountPassword          = @{ Target = 'Parameter'; Type = 'SecureString|String'; Required = $false }
            AccountPasswordAsPlainText = @{ Target = 'Parameter'; Type = 'String'; Required = $false }
            ResetOnFirstLogin        = @{ Target = 'Parameter'; Type = 'Boolean'; Required = $false }
            AllowPlainTextPasswordOutput = @{ Target = 'Parameter'; Type = 'Boolean'; Required = $false }
            
            # State Attributes
            Enabled                  = @{ Target = 'Parameter'; Type = 'Boolean'; Required = $false }
            
            # Extension Container
            OtherAttributes          = @{ Target = 'Container'; Type = 'Hashtable'; Required = $false }
        }
    }
    elseif ($Operation -eq 'EnsureAttribute') {
        return @{
            # Named Set-ADUser parameters (explicit parameter bindings in SetUser)
            GivenName                = @{ Target = 'Parameter'; Type = 'String' }
            Surname                  = @{ Target = 'Parameter'; Type = 'String' }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String' }
            
            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String' }
            Department               = @{ Target = 'Parameter'; Type = 'String' }
            Title                    = @{ Target = 'Parameter'; Type = 'String' }
            
            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String' }
            
            # Identity Attributes
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String' }
            
            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String' }

            # Meta: attributes that are CreateIdentity-only and must NOT be used in EnsureAttribute.
            # Any attribute not listed above and not in _BlockedAttributes.Values is accepted as a
            # custom LDAP attribute and routed via Set-ADUser -Replace (set) or -Clear (null).
            _BlockedAttributes       = @{
                Target = 'Meta'
                Type   = 'String[]'
                Values = @(
                    'SamAccountName'
                    'Path'
                    'Name'
                    'AccountPassword'
                    'AccountPasswordAsPlainText'
                    'ResetOnFirstLogin'
                    'AllowPlainTextPasswordOutput'
                    'Enabled'
                    'OtherAttributes'
                )
            }
        }
    }
}
