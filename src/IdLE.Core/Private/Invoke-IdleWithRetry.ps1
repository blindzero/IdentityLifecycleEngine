function Test-IdleTransientError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Exception] $Exception
    )

    # We only retry when a trusted code path explicitly marks the exception as transient.
    # This keeps retries safe-by-default and prevents masking auth/validation/logic errors.
    $markerKeys = @(
        'Idle.IsTransient',
        'IdleIsTransient'
    )

    foreach ($key in $markerKeys) {
        if ($Exception.Data.Contains($key) -and ($Exception.Data[$key] -eq $true)) {
            return $true
        }
    }

    if ($null -ne $Exception.InnerException) {
        return Test-IdleTransientError -Exception $Exception.InnerException
    }

    return $false
}

function Get-IdleDeterministicJitter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0.0, 1.0)]
        [double] $JitterRatio,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Seed
    )

    # Jitter helps avoid thundering-herd effects, but we must keep execution deterministic.
    # Therefore, we derive a stable pseudo-random value from a string seed (no Get-Random).
    if ($JitterRatio -le 0.0) {
        return 0.0
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hash  = [System.Security.Cryptography.SHA256]::HashData($bytes)

    # Convert first 8 bytes to an unsigned integer and normalize to [0, 1].
    $u64 = [System.BitConverter]::ToUInt64($hash, 0)
    $unit = $u64 / [double][UInt64]::MaxValue

    # Convert to [-1, +1] and scale by jitter ratio.
    return (($unit * 2.0) - 1.0) * $JitterRatio
}

function Invoke-IdleWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $Operation,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int] $MaxAttempts = 3,

        [Parameter()]
        [ValidateRange(0, 600000)]
        [int] $InitialDelayMilliseconds = 250,

        [Parameter()]
        [ValidateRange(1.0, 100.0)]
        [double] $BackoffFactor = 2.0,

        [Parameter()]
        [ValidateRange(0, 600000)]
        [int] $MaxDelayMilliseconds = 5000,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double] $JitterRatio = 0.2,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink,

        [Parameter()]
        [AllowEmptyString()]
        [string] $StepName = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $OperationName = 'Operation',

        [Parameter()]
        [AllowEmptyString()]
        [string] $DeterministicSeed = ''
    )

    $attempt = 0

    while ($attempt -lt $MaxAttempts) {
        $attempt++

        try {
            $value = & $Operation
            return [pscustomobject]@{
                PSTypeName = 'IdLE.RetryResult'
                Value      = $value
                Attempts   = $attempt
            }
        }
        catch {
            $exception = $_.Exception
            $isTransient = Test-IdleTransientError -Exception $exception

            # Fail-fast: non-transient errors are never retried.
            if (-not $isTransient) {
                throw
            }

            # Out of attempts: rethrow the last transient error.
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            # Exponential backoff, capped by MaxDelayMilliseconds.
            $baseDelay = [math]::Min(
                $MaxDelayMilliseconds,
                [math]::Round($InitialDelayMilliseconds * [math]::Pow($BackoffFactor, ($attempt - 1)))
            )

            # Deterministic jitter factor in [-JitterRatio, +JitterRatio].
            $seed = if ([string]::IsNullOrWhiteSpace($DeterministicSeed)) {
                # Keep stable even when no seed is provided.
                "$OperationName|$StepName|$attempt"
            } else {
                "$DeterministicSeed|$attempt"
            }

            $jitterFactor = Get-IdleDeterministicJitter -JitterRatio $JitterRatio -Seed $seed
            $delay = [math]::Round($baseDelay * (1.0 + $jitterFactor))

            if ($delay -lt 0) {
                $delay = 0
            }

            # Best-effort event emission (host sinks must never break engine execution).
            if ($null -ne $EventSink -and $EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                try {
                    $EventSink.WriteEvent('StepRetrying', "Transient failure in '$OperationName' (attempt $attempt/$MaxAttempts). Retrying.", $StepName, @{
                        attempt     = $attempt
                        maxAttempts = $MaxAttempts
                        delayMs     = $delay
                        errorType   = $exception.GetType().FullName
                        message     = $exception.Message
                    })
                }
                catch {
                    # Intentionally ignored.
                }
            }

            if ($delay -gt 0) {
                Start-Sleep -Milliseconds $delay
            }

            continue
        }
    }
}
