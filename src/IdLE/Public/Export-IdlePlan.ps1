<#
.SYNOPSIS
Exports an IdLE LifecyclePlan as a canonical JSON artifact.

.DESCRIPTION
This cmdlet is the **user-facing** wrapper exposed by the IdLE meta module.

It delegates to IdLE.Core's `Export-IdlePlanObject`, which implements the canonical
plan export contract.

By default, the cmdlet returns a pretty-printed JSON string. If -Path is provided,
the JSON is written to disk as UTF-8 (no BOM). Use -PassThru to also return the JSON
string when writing a file.

.PARAMETER Plan
The LifecyclePlan object to export. Accepts pipeline input.

.PARAMETER Path
Optional file path to write the JSON artifact to.

.PARAMETER PassThru
When -Path is used, returns the JSON string in addition to writing the file.

.EXAMPLE
$plan = New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry
$plan | Export-IdlePlan

Exports the plan and returns the JSON string.

.EXAMPLE
New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlan -Path ./artifacts/plan.json

Exports the plan and writes the JSON to a file.

.EXAMPLE
New-IdlePlan -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlan -Path ./artifacts/plan.json -PassThru

Writes the file and also returns the JSON string.

.OUTPUTS
System.String
#>
function Export-IdlePlan {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [switch] $PassThru
    )

    process {
        # Delegate to IdLE.Core to ensure the canonical contract is implemented in one place.
        $params = @{
            Plan = $Plan
        }

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $params.Path = $Path
        }

        if ($PassThru) {
            $params.PassThru = $true
        }

        return IdLE.Core\Export-IdlePlanObject @params
    }
}
