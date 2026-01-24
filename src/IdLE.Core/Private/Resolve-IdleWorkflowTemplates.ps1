function Resolve-IdleWorkflowTemplates {
    <#
    .SYNOPSIS
    Recursively resolves template placeholders in workflow step data.

    .DESCRIPTION
    Walks through hashtables, arrays, and nested objects to find and resolve
    template strings using Resolve-IdleTemplateString.

    This function is called during planning to resolve templates in:
    - Steps[*].With (including nested structures)
    - OnFailureSteps[*].With (including nested structures)

    .PARAMETER Value
    The value to process (hashtable, array, string, or scalar).

    .PARAMETER Request
    The request object providing context for template resolution.

    .PARAMETER StepName
    The name of the step being processed (for error messages).

    .OUTPUTS
    The value with all template strings resolved.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Request,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName
    )

    if ($null -eq $Value) {
        return $null
    }

    # Strings: resolve templates
    if ($Value -is [string]) {
        return Resolve-IdleTemplateString -Value $Value -Request $Request -StepName $StepName
    }

    # Primitives: return as-is
    if ($Value -is [int] -or
        $Value -is [long] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [bool] -or
        $Value -is [datetime] -or
        $Value -is [guid]) {
        return $Value
    }

    # Hashtables/dictionaries: recurse on values
    if ($Value -is [System.Collections.IDictionary]) {
        $resolved = @{}
        foreach ($key in $Value.Keys) {
            $resolved[$key] = Resolve-IdleWorkflowTemplates -Value $Value[$key] -Request $Request -StepName $StepName
        }
        return $resolved
    }

    # Arrays/lists: recurse on items
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $resolved = @()
        foreach ($item in $Value) {
            $resolved += Resolve-IdleWorkflowTemplates -Value $item -Request $Request -StepName $StepName
        }
        return $resolved
    }

    # PSCustomObject: recurse on properties
    $props = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property'))
    if (@($props).Count -gt 0) {
        $resolved = [ordered]@{}
        foreach ($prop in $props) {
            $resolved[$prop.Name] = Resolve-IdleWorkflowTemplates -Value $prop.Value -Request $Request -StepName $StepName
        }
        return [pscustomobject]$resolved
    }

    # Fallback: return as-is
    return $Value
}
