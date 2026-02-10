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

    Special patterns:
    - @{ FromFile = 'path/to/file.txt' }: Loads file content as a string
      * Supports template placeholders in the file path
      * Supports template placeholders within the file content
      * Relative paths are resolved from the current working directory
      * File must exist at planning time
      * File content is loaded as UTF-8

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

    # Hashtables/dictionaries: check for special patterns first
    if ($Value -is [System.Collections.IDictionary]) {
        # Special pattern: @{ FromFile = 'path/to/file' }
        # Load file content and return as string
        if ($Value.Count -eq 1 -and $Value.ContainsKey('FromFile')) {
            $filePath = $Value['FromFile']
            
            if ($null -eq $filePath -or [string]::IsNullOrWhiteSpace($filePath)) {
                throw [System.ArgumentException]::new(
                    ("FromFile error in step '{0}': File path cannot be null or empty." -f $StepName),
                    'Workflow'
                )
            }
            
            # Resolve template placeholders in the file path (e.g., @{ FromFile = '{{Request.DesiredState.TemplatePath}}' })
            $resolvedPath = Resolve-IdleTemplateString -Value ([string]$filePath) -Request $Request -StepName $StepName
            
            # Convert to absolute path if relative
            if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                # Relative paths are resolved from the current working directory
                $resolvedPath = Join-Path -Path (Get-Location).Path -ChildPath $resolvedPath
            }
            
            # Validate file exists
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                throw [System.ArgumentException]::new(
                    ("FromFile error in step '{0}': File not found at path '{1}'." -f $StepName, $resolvedPath),
                    'Workflow'
                )
            }
            
            # Load file content as UTF-8 string
            try {
                $fileContent = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 -ErrorAction Stop
                
                # Resolve any template placeholders within the loaded file content
                return Resolve-IdleTemplateString -Value $fileContent -Request $Request -StepName $StepName
            }
            catch {
                throw [System.ArgumentException]::new(
                    ("FromFile error in step '{0}': Failed to read file '{1}'. {2}" -f $StepName, $resolvedPath, $_.Exception.Message),
                    'Workflow'
                )
            }
        }
        
        # General hashtable: recurse on values
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
