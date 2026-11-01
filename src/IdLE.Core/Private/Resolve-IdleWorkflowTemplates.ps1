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
    - ContextResolvers[*].With

    With -DeferredList, strings that contain State placeholders are left unchanged and recorded
    (Path, Segments, StatePaths) for execution-time resolution. Without it, the State root is not allowed.

    .PARAMETER Value
    The value to process (hashtable, array, string, or scalar).

    .PARAMETER Request
    The request object providing context for template resolution.

    .PARAMETER StepName
    The name of the step being processed (for error messages).

    .PARAMETER Path
    Path of Value (e.g. 'With.Message'), matching the paths used by ConvertTo-IdleSchemaValue.

    .PARAMETER Segments
    Keys and array indexes leading from the root to Value.

    .PARAMETER DeferredList
    Receives one entry per deferred string: @{ Path; Segments; StatePaths }.

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
        [string] $StepName,

        [Parameter()]
        [string] $Path = 'With',

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Segments = @(),

        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.List[object]] $DeferredList
    )

    if ($null -eq $Value) {
        return $null
    }

    # Strings: resolve templates
    if ($Value -is [string]) {
        if ($null -eq $DeferredList) {
            return Resolve-IdleTemplateString -Value $Value -Request $Request -StepName $StepName
        }

        $resolved = Resolve-IdleTemplateString -Value $Value -Request $Request -StepName $StepName -DeferState
        $statePaths = @(Get-IdleTemplatePath -Value $Value | Where-Object { $_ -ceq 'State' -or $_.StartsWith('State.') })
        if ($statePaths.Count -gt 0) {
            $DeferredList.Add(@{ Path = $Path; Segments = @($Segments); StatePaths = $statePaths })
        }
        return $resolved
    }

    # Primitives: return as-is
    if (Test-IdlePrimitiveValue -Value $Value) {
        return $Value
    }

    # Hashtables/dictionaries: recurse on values
    if ($Value -is [System.Collections.IDictionary]) {
        $resolved = @{}
        foreach ($key in $Value.Keys) {
            $resolved[$key] = Resolve-IdleWorkflowTemplates -Value $Value[$key] -Request $Request -StepName $StepName -Path "$Path.$key" -Segments (@($Segments) + [string]$key) -DeferredList $DeferredList
        }
        return $resolved
    }

    # Arrays/lists: recurse on items
    if (Test-IdleEnumerableValue -Value $Value) {
        $resolved = @()
        $index = 0
        foreach ($item in $Value) {
            $resolved += Resolve-IdleWorkflowTemplates -Value $item -Request $Request -StepName $StepName -Path "$Path[$index]" -Segments (@($Segments) + $index) -DeferredList $DeferredList
            $index++
        }
        # Comma operator: keep single-element and empty arrays as arrays (no pipeline unrolling).
        return , $resolved
    }

    # PSCustomObject: recurse on properties
    $props = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property'))
    if (@($props).Count -gt 0) {
        $resolved = [ordered]@{}
        foreach ($prop in $props) {
            $resolved[$prop.Name] = Resolve-IdleWorkflowTemplates -Value $prop.Value -Request $Request -StepName $StepName -Path "$Path.$($prop.Name)" -Segments (@($Segments) + $prop.Name) -DeferredList $DeferredList
        }
        return [pscustomobject]$resolved
    }

    # Fallback: return as-is
    return $Value
}
