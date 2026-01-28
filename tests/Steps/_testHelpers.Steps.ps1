Set-StrictMode -Version Latest

<#
.SYNOPSIS
Step-specific test helpers for IdLE tests.

.DESCRIPTION
This file contains helper functions, fixtures, and test doubles specifically
related to step testing.

This file is sourced by tests/_testHelpers.ps1 and should not be dot-sourced
directly by test files.
#>

function New-IdleTestStepMetadata {
    <#
    .SYNOPSIS
    Creates test step metadata for custom step types used in tests.

    .DESCRIPTION
    Helper function to create StepMetadata entries for test-specific step types.
    By default, creates metadata with no required capabilities.

    .PARAMETER StepTypes
    Array of step type names to create metadata for.

    .PARAMETER RequiredCapabilities
    Hashtable mapping step types to their required capabilities.

    .EXAMPLE
    $metadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity', 'IdLE.Step.Primary')

    .EXAMPLE
    $metadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Custom') -RequiredCapabilities @{
        'IdLE.Step.Custom' = @('Custom.Capability')
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $StepTypes,

        [Parameter()]
        [hashtable] $RequiredCapabilities = @{}
    )

    $metadata = @{}
    foreach ($stepType in $StepTypes) {
        $caps = if ($RequiredCapabilities.ContainsKey($stepType)) {
            $RequiredCapabilities[$stepType]
        }
        else {
            @()
        }
        
        $metadata[$stepType] = @{
            RequiredCapabilities = $caps
        }
    }

    return $metadata
}
