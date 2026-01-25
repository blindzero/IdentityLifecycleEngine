# Resolves effective retry parameters for a step based on ExecutionOptions and step's RetryProfile.

function Resolve-IdleStepRetryParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter()]
        [AllowNull()]
        [object] $ExecutionOptions
    )

    # Default retry parameters (engine defaults)
    $effectiveParams = @{
        MaxAttempts              = 3
        InitialDelayMilliseconds = 250
        BackoffFactor            = 2.0
        MaxDelayMilliseconds     = 5000
        JitterRatio              = 0.2
    }

    # If no ExecutionOptions provided, return defaults
    if ($null -eq $ExecutionOptions) {
        return $effectiveParams
    }

    if ($ExecutionOptions -isnot [System.Collections.IDictionary]) {
        return $effectiveParams
    }

    # Check if ExecutionOptions has RetryProfiles
    $retryProfiles = $null
    if ($ExecutionOptions.Contains('RetryProfiles')) {
        $retryProfiles = $ExecutionOptions['RetryProfiles']
    }

    # Determine which profile to use
    $profileKey = $null

    # Check if step has a RetryProfile property
    if ($Step -is [System.Collections.IDictionary]) {
        if ($Step.Contains('RetryProfile')) {
            $profileKey = [string]$Step['RetryProfile']
        }
    }
    else {
        $stepPropNames = @($Step.PSObject.Properties.Name)
        if ($stepPropNames -contains 'RetryProfile') {
            $profileKey = [string]$Step.RetryProfile
        }
    }

    # If step specifies a RetryProfile but no profiles are configured, fail
    if (-not [string]::IsNullOrWhiteSpace($profileKey) -and ($null -eq $retryProfiles -or $retryProfiles -isnot [System.Collections.IDictionary])) {
        $stepName = ''
        if ($Step -is [System.Collections.IDictionary]) {
            if ($Step.Contains('Name')) {
                $stepName = [string]$Step['Name']
            }
        }
        else {
            if ($null -eq $stepPropNames) {
                $stepPropNames = @($Step.PSObject.Properties.Name)
            }
            if ($stepPropNames -contains 'Name') {
                $stepName = [string]$Step.Name
            }
        }

        throw [System.ArgumentException]::new(
            "Step '$stepName' references RetryProfile '$profileKey' but ExecutionOptions.RetryProfiles is not configured.",
            'ExecutionOptions'
        )
    }

    # If no RetryProfiles configured and step doesn't specify one, return defaults
    if ($null -eq $retryProfiles -or $retryProfiles -isnot [System.Collections.IDictionary]) {
        return $effectiveParams
    }

    # If step doesn't specify a RetryProfile, use DefaultRetryProfile
    if ([string]::IsNullOrWhiteSpace($profileKey)) {
        if ($ExecutionOptions.Contains('DefaultRetryProfile')) {
            $profileKey = [string]$ExecutionOptions['DefaultRetryProfile']
        }
    }

    # If still no profile key, return defaults
    if ([string]::IsNullOrWhiteSpace($profileKey)) {
        return $effectiveParams
    }

    # Look up the profile
    if (-not $retryProfiles.Contains($profileKey)) {
        # Fail-fast: Unknown RetryProfile key
        $stepName = ''
        if ($Step -is [System.Collections.IDictionary]) {
            if ($Step.Contains('Name')) {
                $stepName = [string]$Step['Name']
            }
        }
        else {
            $stepPropNames = @($Step.PSObject.Properties.Name)
            if ($stepPropNames -contains 'Name') {
                $stepName = [string]$Step.Name
            }
        }

        throw [System.ArgumentException]::new(
            "Step '$stepName' references unknown RetryProfile '$profileKey'. Available profiles: $([string]::Join(', ', $retryProfiles.Keys))",
            'ExecutionOptions'
        )
    }

    $profile = $retryProfiles[$profileKey]

    # Apply profile parameters, preserving defaults for missing values
    if ($profile.Contains('MaxAttempts')) {
        $effectiveParams['MaxAttempts'] = [int]$profile['MaxAttempts']
    }

    if ($profile.Contains('InitialDelayMilliseconds')) {
        $effectiveParams['InitialDelayMilliseconds'] = [int]$profile['InitialDelayMilliseconds']
    }

    if ($profile.Contains('BackoffFactor')) {
        $effectiveParams['BackoffFactor'] = [double]$profile['BackoffFactor']
    }

    if ($profile.Contains('MaxDelayMilliseconds')) {
        $effectiveParams['MaxDelayMilliseconds'] = [int]$profile['MaxDelayMilliseconds']
    }

    if ($profile.Contains('JitterRatio')) {
        $effectiveParams['JitterRatio'] = [double]$profile['JitterRatio']
    }

    return $effectiveParams
}
