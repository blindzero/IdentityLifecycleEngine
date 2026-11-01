Set-StrictMode -Version Latest

function Assert-IdleStateReference {
    <#
    .SYNOPSIS
    Validates a State.<StepName>.<Key> reference at planning time.

    .DESCRIPTION
    Throws an ArgumentException whose message starts with StateReferenceInvalid, StateReferenceAmbiguous,
    StateReferenceUnknownStep or StateReferenceNotDeclared (see docs/extend/steps.md).
    Paths below <Key> are not validated.

    .PARAMETER Path
    The referenced path (starting with 'State').

    .PARAMETER StepName
    Name of the referencing step.

    .PARAMETER Source
    Where the reference is used ('Precondition' or the With path).

    .PARAMETER Producers
    Steps that run before the referencing step: step name -> StateSchema (root key schema) or $null.

    .PARAMETER AmbiguousNames
    Step names that exist in both Steps and OnFailureSteps (only relevant for OnFailureSteps).

    .OUTPUTS
    None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Source,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Producers,

        [Parameter()]
        [string[]] $AmbiguousNames = @()
    )

    $prefix = "Workflow step '$StepName' references '$Path' in $Source"
    $segments = @($Path -split '\.')

    if ($segments.Count -lt 2 -or $segments[1] -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw [System.ArgumentException]::new(
            "StateReferenceInvalid: $prefix. Use State.<StepName>.<Key>; the producing step's Name must be an identifier (letters, digits, underscores, e.g. 'GetMailbox').",
            'Workflow'
        )
    }

    $producerName = $segments[1]

    if ($AmbiguousNames -contains $producerName) {
        throw [System.ArgumentException]::new(
            "StateReferenceAmbiguous: $prefix, but a step named '$producerName' exists in both Steps and OnFailureSteps. Rename one of them.",
            'Workflow'
        )
    }

    if (-not $Producers.ContainsKey($producerName)) {
        throw [System.ArgumentException]::new(
            "StateReferenceUnknownStep: $prefix, but no step named '$producerName' runs before it.",
            'Workflow'
        )
    }

    $stateSchema = $Producers[$producerName]
    if ($null -eq $stateSchema) {
        throw [System.ArgumentException]::new(
            "StateReferenceNotDeclared: $prefix, but the step type of '$producerName' declares no StateSchema (it publishes no State).",
            'Workflow'
        )
    }

    if ($segments.Count -ge 3 -and -not ($stateSchema['AllowAdditionalKeys'] -eq $true)) {
        $key = $segments[2]
        $declared = @($stateSchema['Keys'].PSBase.Keys | Where-Object { [string]::Equals([string]$_, $key, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($declared.Count -eq 0) {
            $supported = [string]::Join(', ', @($stateSchema['Keys'].PSBase.Keys | Sort-Object))
            throw [System.ArgumentException]::new(
                "StateReferenceNotDeclared: $prefix, but the StateSchema of '$producerName' does not declare '$key'. Declared keys: $supported.",
                'Workflow'
            )
        }
    }
}
