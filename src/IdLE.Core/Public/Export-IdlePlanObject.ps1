<#
.SYNOPSIS
Exports an IdLE LifecyclePlan as a canonical, machine-readable JSON artifact.

.DESCRIPTION
Exports a LifecyclePlan to the **canonical JSON contract** defined by IdLE.
The output is intended for auditing, approvals, CI checks, and host integrations.

By default, the cmdlet returns a **pretty-printed JSON string**. If -Path is provided,
the JSON is written to disk as UTF-8 (no BOM). Use -PassThru to also return the JSON string
when writing a file.

This cmdlet is part of IdLE.Core and must remain host-agnostic.

.PARAMETER Plan
The LifecyclePlan object to export. Accepts pipeline input.

.PARAMETER Path
Optional file path to write the JSON artifact to.

.PARAMETER PassThru
When -Path is used, returns the JSON string in addition to writing the file.

.EXAMPLE
$plan = New-IdlePlanObject -Request $request -Workflow $workflow -StepRegistry $registry
$plan | Export-IdlePlanObject

Exports the plan and returns the JSON string.

.EXAMPLE
New-IdlePlanObject -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlanObject -Path ./artifacts/plan.json

Exports the plan and writes the JSON to a file.

.EXAMPLE
New-IdlePlanObject -Request $request -Workflow $workflow -StepRegistry $registry |
    Export-IdlePlanObject -Path ./artifacts/plan.json -PassThru

Writes the file and also returns the JSON string.

.OUTPUTS
System.String
#>
function Export-IdlePlanObject {
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

    begin {
        # Keep JSON output stable and review-friendly.
        # Depth must be sufficient for nested step inputs/expectedState.
        $jsonDepth = 20

        # Prefer UTF-8 without BOM for deterministic artifacts across platforms.
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    }

    process {
        # Map internal plan object into a stable export DTO (pure data).
        # NOTE: ConvertTo-IdlePlanExportObject is implemented as a private function in IdLE.Core.
        $exportObject = ConvertTo-IdlePlanExportObject -Plan $Plan

        # Pretty-printed JSON by default (no -Compress).
        $json = $exportObject | ConvertTo-Json -Depth $jsonDepth

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            # Resolve to a full path early to avoid surprises and to improve error messages.
            $resolvedPath = $Path

            try {
                # If the parent directory does not exist, fail with a clear message.
                $parent = Split-Path -Path $resolvedPath -Parent
                if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
                    $message = "The output directory does not exist: '{0}'." -f $parent
                    throw [System.IO.DirectoryNotFoundException]::new($message)
                }

                # Write JSON deterministically. ConvertTo-Json uses LF on PowerShell Core, and
                # WriteAllText will preserve the string's newlines as-is.
                [System.IO.File]::WriteAllText($resolvedPath, $json, $utf8NoBom)
            }
            catch {
                $message = "Failed to write plan export JSON to '{0}'. {1}" -f $resolvedPath, $_.Exception.Message
                throw [System.IO.IOException]::new($message, $_.Exception)
            }

            if ($PassThru) {
                return $json
            }

            return
        }

        return $json
    }
}
