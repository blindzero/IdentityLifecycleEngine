# Asserts that ExecutionOptions is valid and rejects ScriptBlocks.
# Validates the structure and constraints for retry profiles.

# Retry parameter limits (hard constraints to prevent misconfiguration)
$script:IDLE_RETRY_MAX_ATTEMPTS_LIMIT = 10
$script:IDLE_RETRY_INITIAL_DELAY_MS_LIMIT = 60000
$script:IDLE_RETRY_MAX_DELAY_MS_LIMIT = 300000

function Assert-IdleExecutionOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $ExecutionOptions
    )

    if ($null -eq $ExecutionOptions) {
        return
    }

    # ExecutionOptions must be a hashtable or IDictionary
    if ($ExecutionOptions -isnot [System.Collections.IDictionary]) {
        throw [System.ArgumentException]::new(
            'ExecutionOptions must be a hashtable or IDictionary.',
            'ExecutionOptions'
        )
    }

    # Reject ScriptBlocks anywhere in ExecutionOptions
    Assert-IdleNoScriptBlock -InputObject $ExecutionOptions -Path 'ExecutionOptions'

    # Validate RetryProfiles if present
    if ($ExecutionOptions.Contains('RetryProfiles')) {
        $retryProfiles = $ExecutionOptions['RetryProfiles']

        if ($null -ne $retryProfiles -and $retryProfiles -isnot [System.Collections.IDictionary]) {
            throw [System.ArgumentException]::new(
                'ExecutionOptions.RetryProfiles must be a hashtable or IDictionary.',
                'ExecutionOptions'
            )
        }

        if ($null -ne $retryProfiles) {
            foreach ($profileKey in $retryProfiles.Keys) {
                # Profile key must match pattern: ^[A-Za-z0-9_.-]{1,64}$
                if ([string]$profileKey -notmatch '^[A-Za-z0-9_.-]{1,64}$') {
                    throw [System.ArgumentException]::new(
                        "RetryProfile key '$profileKey' is invalid. Must match pattern: ^[A-Za-z0-9_.-]{1,64}$",
                        'ExecutionOptions'
                    )
                }

                $profile = $retryProfiles[$profileKey]

                if ($null -eq $profile) {
                    throw [System.ArgumentException]::new(
                        "RetryProfile '$profileKey' is null. Each profile must be a hashtable with retry parameters.",
                        'ExecutionOptions'
                    )
                }

                if ($profile -isnot [System.Collections.IDictionary]) {
                    throw [System.ArgumentException]::new(
                        "RetryProfile '$profileKey' must be a hashtable or IDictionary.",
                        'ExecutionOptions'
                    )
                }

                # Validate individual retry parameters
                Assert-IdleRetryProfile -Profile $profile -ProfileKey $profileKey
            }
        }
    }

    # Validate DefaultRetryProfile if present
    if ($ExecutionOptions.Contains('DefaultRetryProfile')) {
        $defaultProfile = $ExecutionOptions['DefaultRetryProfile']

        if ($null -ne $defaultProfile -and [string]::IsNullOrWhiteSpace([string]$defaultProfile)) {
            throw [System.ArgumentException]::new(
                'ExecutionOptions.DefaultRetryProfile must not be an empty string.',
                'ExecutionOptions'
            )
        }

        # DefaultRetryProfile must reference a valid profile key
        if ($null -ne $defaultProfile -and $ExecutionOptions.Contains('RetryProfiles')) {
            $retryProfiles = $ExecutionOptions['RetryProfiles']
            if ($null -ne $retryProfiles -and -not $retryProfiles.Contains([string]$defaultProfile)) {
                throw [System.ArgumentException]::new(
                    "DefaultRetryProfile '$defaultProfile' references a profile that does not exist in RetryProfiles.",
                    'ExecutionOptions'
                )
            }
        }
    }
}

function Assert-IdleRetryProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Profile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProfileKey
    )

    # Validate MaxAttempts (0..10)
    if ($Profile.Contains('MaxAttempts')) {
        $maxAttempts = $Profile['MaxAttempts']
        if ($maxAttempts -isnot [int] -or $maxAttempts -lt 0 -or $maxAttempts -gt $script:IDLE_RETRY_MAX_ATTEMPTS_LIMIT) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': MaxAttempts must be an integer between 0 and $script:IDLE_RETRY_MAX_ATTEMPTS_LIMIT (inclusive).",
                'ExecutionOptions'
            )
        }
    }

    # Validate InitialDelayMilliseconds (0..60000)
    if ($Profile.Contains('InitialDelayMilliseconds')) {
        $initialDelay = $Profile['InitialDelayMilliseconds']
        if ($initialDelay -isnot [int] -or $initialDelay -lt 0 -or $initialDelay -gt $script:IDLE_RETRY_INITIAL_DELAY_MS_LIMIT) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': InitialDelayMilliseconds must be an integer between 0 and $script:IDLE_RETRY_INITIAL_DELAY_MS_LIMIT (inclusive).",
                'ExecutionOptions'
            )
        }
    }

    # Validate BackoffFactor (>= 1.0)
    if ($Profile.Contains('BackoffFactor')) {
        $backoffFactor = $Profile['BackoffFactor']
        # Accept both int and double
        if (($backoffFactor -isnot [double] -and $backoffFactor -isnot [int]) -or ([double]$backoffFactor -lt 1.0)) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': BackoffFactor must be a number >= 1.0.",
                'ExecutionOptions'
            )
        }
    }

    # Validate MaxDelayMilliseconds (0..300000 and >= InitialDelayMilliseconds)
    if ($Profile.Contains('MaxDelayMilliseconds')) {
        $maxDelay = $Profile['MaxDelayMilliseconds']
        if ($maxDelay -isnot [int] -or $maxDelay -lt 0 -or $maxDelay -gt $script:IDLE_RETRY_MAX_DELAY_MS_LIMIT) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': MaxDelayMilliseconds must be an integer between 0 and $script:IDLE_RETRY_MAX_DELAY_MS_LIMIT (inclusive).",
                'ExecutionOptions'
            )
        }

        # Check that MaxDelayMilliseconds >= InitialDelayMilliseconds
        # Use the profile's InitialDelayMilliseconds if present, otherwise use engine default (250ms)
        $initialDelay = if ($Profile.Contains('InitialDelayMilliseconds')) {
            $Profile['InitialDelayMilliseconds']
        } else {
            250  # Engine default
        }
        
        if ($maxDelay -lt $initialDelay) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': MaxDelayMilliseconds ($maxDelay) must be >= InitialDelayMilliseconds ($initialDelay).",
                'ExecutionOptions'
            )
        }
    }

    # Validate JitterRatio (0.0..1.0)
    if ($Profile.Contains('JitterRatio')) {
        $jitterRatio = $Profile['JitterRatio']
        # Accept both int and double
        if (($jitterRatio -isnot [double] -and $jitterRatio -isnot [int]) -or ([double]$jitterRatio -lt 0.0) -or ([double]$jitterRatio -gt 1.0)) {
            throw [System.ArgumentException]::new(
                "RetryProfile '$ProfileKey': JitterRatio must be a number between 0.0 and 1.0 (inclusive).",
                'ExecutionOptions'
            )
        }
    }
}
