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
    Resolved string with placeholders replaced by request values.
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

    # Check for unbalanced braces (typo safety)
    $openCount = ([regex]::Matches($stringValue, '(?<!\\)\{\{')).Count
    $closeCount = ([regex]::Matches($stringValue, '\}\}')).Count
    if ($openCount -ne $closeCount) {
        throw [System.ArgumentException]::new(
            ("Template syntax error in step '{0}': Unbalanced braces in value '{1}'. Found {2} opening '{{{{' and {3} closing '}}}}'. Check for typos or missing braces." -f $StepName, $stringValue, $openCount, $closeCount),
            'Workflow'
        )
    }

    # Parse and resolve placeholders
    $result = $stringValue
    $pattern = '(?<!\\)\{\{([^}]+)\}\}'
    $matches = [regex]::Matches($stringValue, $pattern)

    foreach ($match in $matches) {
        $placeholder = $match.Groups[0].Value
        $path = $match.Groups[1].Value.Trim()

        # Validate path pattern (strict: alphanumeric + dots only)
        if ($path -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*$') {
            throw [System.ArgumentException]::new(
                ("Template path error in step '{0}': Invalid path pattern '{1}'. Paths must use dot-separated identifiers (letters, numbers, underscores) with no spaces or special characters." -f $StepName, $path),
                'Workflow'
            )
        }

        # Security: validate allowed roots
        $allowedRoots = @('Request.Input', 'Request.DesiredState', 'Request.IdentityKeys', 'Request.Changes', 'Request.LifecycleEvent', 'Request.CorrelationId', 'Request.Actor')
        $isAllowed = $false
        foreach ($root in $allowedRoots) {
            if ($path -eq $root -or $path.StartsWith("$root.")) {
                $isAllowed = $true
                break
            }
        }

        if (-not $isAllowed) {
            throw [System.ArgumentException]::new(
                ("Template security error in step '{0}': Path '{1}' is not allowed. Only these roots are permitted: {2}" -f $StepName, $path, ([string]::Join(', ', $allowedRoots))),
                'Workflow'
            )
        }

        # Handle Request.Input.* alias to Request.DesiredState.*
        $resolvePath = $path
        if ($path.StartsWith('Request.Input.')) {
            # Check if Request has an Input property
            $hasInputProperty = $false
            if ($Request.PSObject.Properties['Input'] -ne $null) {
                $hasInputProperty = $true
            }
            
            if (-not $hasInputProperty) {
                # Alias to DesiredState
                $resolvePath = $path -replace '^Request\.Input\.', 'Request.DesiredState.'
            }
        }
        elseif ($path -eq 'Request.Input') {
            # Check if Request has an Input property
            $hasInputProperty = $false
            if ($Request.PSObject.Properties['Input'] -ne $null) {
                $hasInputProperty = $true
            }
            
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
            ($resolvedValue -is [array] -and @($resolvedValue).Count -gt 0) -or
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
