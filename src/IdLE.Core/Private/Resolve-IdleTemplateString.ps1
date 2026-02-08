function Resolve-IdleTemplateString {
    <#
    .SYNOPSIS
    Resolves template placeholders in a string using request context.

    .DESCRIPTION
    Scans a string for {{...}} placeholders and resolves them against the request object.
    Only allowlisted request roots are permitted for security.

    Template syntax:
    - Placeholder format: {{<Path>}}
    - Path is a dot-separated property path
    - Multiple placeholders are supported in one string

    Allowed roots (security boundary):
    - Request.Input.* (aliased to Request.DesiredState.* if Input does not exist)
    - Request.DesiredState.*
    - Request.IdentityKeys.*
    - Request.Changes.*
    - Request.LifecycleEvent
    - Request.CorrelationId
    - Request.Actor

    Escaping:
    - \{{ → literal {{ (escape removed after resolution)

    .PARAMETER Value
    The string value to resolve. If not a string, returns the value unchanged.

    .PARAMETER Request
    The request object providing context for template resolution.

    .PARAMETER StepName
    The name of the step being processed (for error messages).

    .OUTPUTS
    For pure placeholders (single placeholder with no surrounding text), returns the resolved value with its original type preserved (string, bool, int, datetime, guid, etc.).
    For mixed strings (string interpolation with multiple placeholders or surrounding text), returns a string with placeholders replaced.
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

    if ($Value -isnot [string]) {
        return $Value
    }

    $stringValue = [string]$Value

    # Quick exit: no template markers present
    if ($stringValue -notlike '*{{*' -and $stringValue -notlike '*}}*') {
        # Handle escaped braces with no actual templates
        if ($stringValue -like '*\{{*') {
            return $stringValue -replace '\\{{', '{{'
        }
        return $stringValue
    }

    # Define validation constants used in multiple paths
    $pathValidationPattern = '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*$'
    $allowedRoots = @('Request.Input', 'Request.DesiredState', 'Request.IdentityKeys', 'Request.Changes', 'Request.LifecycleEvent', 'Request.CorrelationId', 'Request.Actor')

    # Helper function to validate path pattern
    $validatePath = {
        param([string]$Path)
        if ($Path -notmatch $pathValidationPattern) {
            throw [System.ArgumentException]::new(
                ("Template path error in step '{0}': Invalid path pattern '{1}'. Paths must use dot-separated identifiers (letters, numbers, underscores) with no spaces or special characters." -f $StepName, $Path),
                'Workflow'
            )
        }
    }

    # Helper function to validate allowed roots
    $validateAllowedRoot = {
        param([string]$Path)
        $isAllowed = $false
        foreach ($root in $allowedRoots) {
            if ($Path -eq $root -or $Path.StartsWith("$root.")) {
                $isAllowed = $true
                break
            }
        }
        if (-not $isAllowed) {
            throw [System.ArgumentException]::new(
                ("Template security error in step '{0}': Path '{1}' is not allowed. Only these roots are permitted: {2}" -f $StepName, $Path, ([string]::Join(', ', $allowedRoots))),
                'Workflow'
            )
        }
    }

    # Check if this is a pure placeholder (no prefix/suffix text, single placeholder)
    # If so, we can preserve the type instead of coercing to string
    $purePattern = '^\s*\{\{([^}]+)\}\}\s*$'
    $pureMatch = [regex]::Match($stringValue, $purePattern)
    $isPurePlaceholder = $pureMatch.Success

    # Check for unbalanced braces (typo safety)
    # Skip this validation for pure placeholders as we already validated them
    if (-not $isPurePlaceholder) {
        # Count non-escaped opening braces
        $openCount = ([regex]::Matches($stringValue, '(?<!\\)\{\{')).Count
        # For closing braces, only count those that belong to templates (have a corresponding non-escaped opening)
        # We can do this by counting matches of the full template pattern
        $templatePattern = '(?<!\\)\{\{([^}]+)\}\}'
        $templateCount = ([regex]::Matches($stringValue, $templatePattern)).Count
        # Any }} that's part of a template is matched. Any other }} is unbalanced.
        $allCloseCount = ([regex]::Matches($stringValue, '\}\}')).Count
        
        # The expected close count should equal template count (each template has one closing)
        if ($openCount -ne $templateCount -or $allCloseCount -ne $templateCount) {
            throw [System.ArgumentException]::new(
                ("Template syntax error in step '{0}': Unbalanced braces in value '{1}'. Found {2} opening '{{{{' and {3} closing '}}}}'. Check for typos or missing braces." -f $StepName, $stringValue, $openCount, $allCloseCount),
                'Workflow'
            )
        }
    }

    # Parse and resolve placeholders
    $result = $stringValue
    $pattern = '(?<!\\)\{\{([^}]+)\}\}'
    $matches = [regex]::Matches($stringValue, $pattern)

    # For pure placeholders, we'll return the typed value directly
    if ($isPurePlaceholder) {
        # There should be exactly one match
        $match = $matches[0]
        $path = $match.Groups[1].Value.Trim()

        # Validate path pattern and allowed roots using helper functions
        & $validatePath $path
        & $validateAllowedRoot $path

        # Handle Request.Input.* alias to Request.DesiredState.*
        $resolvePath = $path
        $hasInputProperty = $false
        if ($Request.PSObject.Properties['Input']) {
            $hasInputProperty = $true
        }
        
        if ($path.StartsWith('Request.Input.')) {
            if (-not $hasInputProperty) {
                # Alias to DesiredState
                $resolvePath = $path -replace '^Request\.Input\.', 'Request.DesiredState.'
            }
        }
        elseif ($path -eq 'Request.Input') {
            if (-not $hasInputProperty) {
                $resolvePath = 'Request.DesiredState'
            }
        }

        # Resolve the value (using custom logic that handles hashtables)
        $contextWrapper = [pscustomobject]@{ Request = $Request }
        $current = $contextWrapper
        foreach ($segment in ($resolvePath -split '\.')) {
            if ($null -eq $current) {
                $resolvedValue = $null
                break
            }

            # Handle hashtables/dictionaries
            if ($current -is [System.Collections.IDictionary]) {
                if ($current.ContainsKey($segment)) {
                    $current = $current[$segment]
                }
                else {
                    $current = $null
                }
            }
            # Handle PSCustomObjects and class instances
            else {
                $prop = $current.PSObject.Properties[$segment]
                if ($null -eq $prop) {
                    $current = $null
                }
                else {
                    $current = $prop.Value
                }
            }
        }
        $resolvedValue = $current

        # Fail fast on null/missing values
        if ($null -eq $resolvedValue) {
            throw [System.ArgumentException]::new(
                ("Template resolution error in step '{0}': Path '{1}' resolved to null or does not exist. Ensure the request contains all required values." -f $StepName, $path),
                'Workflow'
            )
        }

        # Type validation: only scalar-ish types allowed
        if ($resolvedValue -is [hashtable] -or
            $resolvedValue -is [System.Collections.IDictionary] -or
            $resolvedValue -is [array] -or
            ($resolvedValue -is [System.Collections.IEnumerable] -and $resolvedValue -isnot [string])) {
            throw [System.ArgumentException]::new(
                ("Template type error in step '{0}': Path '{1}' resolved to a non-scalar value (hashtable/array/object). Templates only support scalar values (string, number, bool, datetime, guid). Use an explicit mapping step or host-side pre-flattening." -f $StepName, $path),
                'Workflow'
            )
        }

        # Return the typed value directly (no string conversion)
        return $resolvedValue
    }

    # For mixed templates (string interpolation), process all placeholders and convert to string

    foreach ($match in $matches) {
        $placeholder = $match.Groups[0].Value
        $path = $match.Groups[1].Value.Trim()

        # Validate path pattern and allowed roots using helper functions
        & $validatePath $path
        & $validateAllowedRoot $path

        # Handle Request.Input.* alias to Request.DesiredState.*
        $resolvePath = $path
        $hasInputProperty = $false
        if ($Request.PSObject.Properties['Input']) {
            $hasInputProperty = $true
        }
        
        if ($path.StartsWith('Request.Input.')) {
            if (-not $hasInputProperty) {
                # Alias to DesiredState
                $resolvePath = $path -replace '^Request\.Input\.', 'Request.DesiredState.'
            }
        }
        elseif ($path -eq 'Request.Input') {
            if (-not $hasInputProperty) {
                $resolvePath = 'Request.DesiredState'
            }
        }

        # Resolve the value (using custom logic that handles hashtables)
        $contextWrapper = [pscustomobject]@{ Request = $Request }
        $current = $contextWrapper
        foreach ($segment in ($resolvePath -split '\.')) {
            if ($null -eq $current) {
                $resolvedValue = $null
                break
            }

            # Handle hashtables/dictionaries
            if ($current -is [System.Collections.IDictionary]) {
                if ($current.ContainsKey($segment)) {
                    $current = $current[$segment]
                }
                else {
                    $current = $null
                }
            }
            # Handle PSCustomObjects and class instances
            else {
                $prop = $current.PSObject.Properties[$segment]
                if ($null -eq $prop) {
                    $current = $null
                }
                else {
                    $current = $prop.Value
                }
            }
        }
        $resolvedValue = $current

        # Fail fast on null/missing values
        if ($null -eq $resolvedValue) {
            throw [System.ArgumentException]::new(
                ("Template resolution error in step '{0}': Path '{1}' resolved to null or does not exist. Ensure the request contains all required values." -f $StepName, $path),
                'Workflow'
            )
        }

        # Type validation: only scalar-ish types allowed
        if ($resolvedValue -is [hashtable] -or
            $resolvedValue -is [System.Collections.IDictionary] -or
            $resolvedValue -is [array] -or
            ($resolvedValue -is [System.Collections.IEnumerable] -and $resolvedValue -isnot [string])) {
            throw [System.ArgumentException]::new(
                ("Template type error in step '{0}': Path '{1}' resolved to a non-scalar value (hashtable/array/object). Templates only support scalar values (string, number, bool, datetime, guid). Use an explicit mapping step or host-side pre-flattening." -f $StepName, $path),
                'Workflow'
            )
        }

        # Convert to string
        $stringReplacement = [string]$resolvedValue

        # Replace placeholder
        $result = $result.Replace($placeholder, $stringReplacement)
    }

    # Process escape sequences (unescape \{{ to {{)
    $result = $result -replace '\\{{', '{{'

    return $result
}
