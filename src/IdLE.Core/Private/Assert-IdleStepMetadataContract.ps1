function Assert-IdleStepMetadataContract {
    <#
    .SYNOPSIS
    Validates the WithSchema and Provider entries of a step metadata entry.

    .DESCRIPTION
    Throws ArgumentException with a message starting with LegacyWithSchema (RequiredKeys/OptionalKeys format)
    or InvalidWithSchema (any other shape error). See docs/extend/steps.md for the format.

    .PARAMETER Metadata
    Step metadata entry.

    .PARAMETER StepType
    Step type the entry belongs to.

    .PARAMETER SourceName
    Source of the entry (step pack module name or 'Providers.StepMetadata').

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Metadata,

        [Parameter(Mandatory)]
        [string] $StepType,

        [Parameter(Mandatory)]
        [string] $SourceName
    )

    $prefix = "$SourceName entry for step type '$StepType'"
    $commonKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
    $types = @('String', 'Int', 'Bool', 'Hashtable', 'Array', 'Any')
    $keySchemaProperties = @('Type', 'Required', 'Default', 'AllowedValues', 'AllowEmpty', 'Keys', 'AllowAdditionalKeys', 'Items')
    $example = "WithSchema = @{ Keys = @{ IdentityKey = @{ Type = 'String'; Required = `$true } } }"

    function New-IdleContractError {
        param([string] $Text)
        return [System.ArgumentException]::new("InvalidWithSchema: $prefix $Text", 'Providers')
    }

    function Assert-IdleKeySchema {
        param([object] $KeySchema, [string] $Path)

        if ($KeySchema -isnot [hashtable]) {
            throw (New-IdleContractError "$Path must be a hashtable, e.g. @{ Type = 'String'; Required = `$true }.")
        }

        foreach ($property in $KeySchema.PSBase.Keys) {
            if ($keySchemaProperties -notcontains [string]$property) {
                throw (New-IdleContractError "$Path has unknown property '$property'. Supported: $([string]::Join(', ', $keySchemaProperties)).")
            }
        }

        $type = $KeySchema['Type']
        if ($types -notcontains [string]$type) {
            throw (New-IdleContractError "$Path.Type must be one of: $([string]::Join(', ', $types)) (got '$type').")
        }

        foreach ($flag in @('Required', 'AllowEmpty', 'AllowAdditionalKeys')) {
            if ($KeySchema.ContainsKey($flag) -and $KeySchema[$flag] -isnot [bool]) {
                throw (New-IdleContractError "$Path.$flag must be a Bool.")
            }
        }

        $applicability = @{
            AllowedValues       = @('String', 'Int')
            AllowEmpty          = @('String', 'Array')
            Keys                = @('Hashtable')
            AllowAdditionalKeys = @('Hashtable')
            Items               = @('Array')
        }
        foreach ($property in $applicability.PSBase.Keys) {
            if ($KeySchema.ContainsKey($property) -and $applicability[$property] -notcontains $type) {
                throw (New-IdleContractError "$Path.$property is not supported for Type '$type'.")
            }
        }

        if ($KeySchema.ContainsKey('AllowedValues')) {
            $allowed = @($KeySchema['AllowedValues'])
            if ($allowed.Count -eq 0) {
                throw (New-IdleContractError "$Path.AllowedValues must not be empty.")
            }
            foreach ($item in $allowed) {
                $itemOk = if ($type -eq 'String') { $item -is [string] } else { $item -is [int] -or $item -is [long] }
                if (-not $itemOk) {
                    throw (New-IdleContractError "$Path.AllowedValues must only contain $type values.")
                }
            }
        }

        if ($KeySchema.ContainsKey('Keys')) {
            Assert-IdleKeysSchema -Keys $KeySchema['Keys'] -Path "$Path.Keys"
        }

        if ($KeySchema.ContainsKey('Items')) {
            Assert-IdleKeySchema -KeySchema $KeySchema['Items'] -Path "$Path.Items"
        }

        if ($KeySchema.ContainsKey('Default')) {
            if ($KeySchema['Required'] -eq $true) {
                throw (New-IdleContractError "$Path must not declare both Required and Default.")
            }
            try {
                $null = ConvertTo-IdleSchemaValue -Schema $KeySchema -Value $KeySchema['Default'] -Path "$Path.Default" -ErrorPrefix $prefix
            }
            catch {
                throw (New-IdleContractError "$Path.Default does not match its schema: $($_.Exception.Message)")
            }
        }
    }

    function Assert-IdleKeysSchema {
        param([object] $Keys, [string] $Path)

        if ($Keys -isnot [hashtable]) {
            throw (New-IdleContractError "$Path must be a hashtable that maps key names to key schemas.")
        }
        foreach ($key in $Keys.PSBase.Keys) {
            if ([string]::IsNullOrWhiteSpace([string]$key)) {
                throw (New-IdleContractError "$Path contains an empty key name.")
            }
            Assert-IdleKeySchema -KeySchema $Keys[$key] -Path "$Path.$key"
        }
    }

    if (-not $Metadata.ContainsKey('WithSchema') -or $null -eq $Metadata['WithSchema']) {
        throw (New-IdleContractError "is missing 'WithSchema'. Every step type must declare its With contract, e.g. $example.")
    }

    $withSchema = $Metadata['WithSchema']
    if ($withSchema -isnot [hashtable]) {
        throw (New-IdleContractError "has an invalid 'WithSchema'. Expected a hashtable, e.g. $example.")
    }

    if ($withSchema.ContainsKey('RequiredKeys') -or $withSchema.ContainsKey('OptionalKeys')) {
        throw [System.ArgumentException]::new(
            "LegacyWithSchema: $prefix uses WithSchema.RequiredKeys/OptionalKeys. Declare typed keys instead, e.g. $example. Provider, AuthSessionName and AuthSessionOptions are added by the engine when the entry declares Provider = @{ DefaultAlias = '<alias>' }.",
            'Providers'
        )
    }

    foreach ($property in $withSchema.PSBase.Keys) {
        if (@('Keys', 'AllowAdditionalKeys') -notcontains [string]$property) {
            throw (New-IdleContractError "WithSchema has unknown property '$property'. Supported: Keys, AllowAdditionalKeys.")
        }
    }

    if (-not $withSchema.ContainsKey('Keys')) {
        throw (New-IdleContractError "WithSchema is missing 'Keys' (may be empty: @{}).")
    }
    if ($withSchema.ContainsKey('AllowAdditionalKeys') -and $withSchema['AllowAdditionalKeys'] -isnot [bool]) {
        throw (New-IdleContractError 'WithSchema.AllowAdditionalKeys must be a Bool.')
    }

    Assert-IdleKeysSchema -Keys $withSchema['Keys'] -Path 'WithSchema.Keys'

    foreach ($key in $withSchema['Keys'].PSBase.Keys) {
        if ($commonKeys -contains [string]$key) {
            throw (New-IdleContractError "WithSchema.Keys must not declare '$key'. Declare Provider = @{ DefaultAlias = '<alias>' } instead; the engine adds Provider, AuthSessionName and AuthSessionOptions.")
        }
    }

    if ($Metadata.ContainsKey('Provider')) {
        $provider = $Metadata['Provider']
        $providerOk = $false
        if ($provider -is [hashtable] -and $provider['DefaultAlias'] -is [string] -and -not [string]::IsNullOrWhiteSpace($provider['DefaultAlias'])) {
            $unknownProperties = @($provider.PSBase.Keys | Where-Object { @('DefaultAlias', 'AuthSessionNameFromAlias') -notcontains [string]$_ })
            $flagOk = -not $provider.ContainsKey('AuthSessionNameFromAlias') -or $provider['AuthSessionNameFromAlias'] -is [bool]
            $providerOk = $unknownProperties.Count -eq 0 -and $flagOk
        }
        if (-not $providerOk) {
            throw (New-IdleContractError "has an invalid 'Provider'. Expected @{ DefaultAlias = '<alias>'; AuthSessionNameFromAlias = <bool, optional> }, e.g. @{ DefaultAlias = 'Identity' }.")
        }
    }
}
