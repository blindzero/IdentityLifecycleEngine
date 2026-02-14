function Test-IdleTransientError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Exception] $Exception
    )

    # Retries must be safe-by-default:
    # We only retry when a trusted code path explicitly marks an exception as transient.
    #
    # Supported markers:
    # - Exception.Data['Idle.IsTransient'] = $true
    # - Exception.Data['IdleIsTransient']  = $true
    #
    # We accept common "truthy" representations to avoid fragile integrations:
    # - $true
    # - 'true' (case-insensitive)
    # - 1
    $markerKeys = @(
        'Idle.IsTransient',
        'IdleIsTransient'
    )

    foreach ($key in $markerKeys) {
        if (-not $Exception.Data.Contains($key)) {
            continue
        }

        $value = $Exception.Data[$key]

        if ($value -is [bool] -and $value) {
            return $true
        }

        if ($value -is [int] -and $value -eq 1) {
            return $true
        }

        if ($value -is [string] -and $value.Trim().ToLowerInvariant() -eq 'true') {
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

    if ($JitterRatio -le 0.0) {
        return 0.0
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)

    $u64 = [System.BitConverter]::ToUInt64($hash, 0)
    $unit = $u64 / [double][UInt64]::MaxValue

    return (($unit * 2.0) - 1.0) * $JitterRatio
}

function Invoke-IdleWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $Operation,

        [Parameter()]
        [int] $MaxAttempts = 3,

        [Parameter()]
        [int] $InitialDelayMilliseconds = 250,

        [Parameter()]
        [double] $BackoffFactor = 2.0,

        [Parameter()]
        [int] $MaxDelayMilliseconds = 5000,

        [Parameter()]
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

    Assert-IdleRetryParameters `
        -MaxAttempts $MaxAttempts `
        -InitialDelayMilliseconds $InitialDelayMilliseconds `
        -BackoffFactor $BackoffFactor `
        -MaxDelayMilliseconds $MaxDelayMilliseconds `
        -JitterRatio $JitterRatio `
        -SourceName 'Invoke-IdleWithRetry'

    # Handle MaxAttempts = 0 (no retry): run once and propagate any error
    if ($MaxAttempts -eq 0) {
        $value = & $Operation
        return [pscustomobject]@{
            PSTypeName = 'IdLE.RetryResult'
            Value      = $value
            Attempts   = 1
        }
    }

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

            if (-not (Test-IdleTransientError -Exception $exception)) {
                # Fail fast for non-transient errors.
                throw
            }

            if ($attempt -ge $MaxAttempts) {
                throw
            }

            $baseDelay = [math]::Min(
                $MaxDelayMilliseconds,
                [math]::Round($InitialDelayMilliseconds * [math]::Pow($BackoffFactor, ($attempt - 1)))
            )

            $seed = if ([string]::IsNullOrWhiteSpace($DeterministicSeed)) {
                "$OperationName|$StepName|$attempt"
            } else {
                "$DeterministicSeed|$attempt"
            }

            $jitterFactor = Get-IdleDeterministicJitter -JitterRatio $JitterRatio -Seed $seed
            $delay = [math]::Round($baseDelay * (1.0 + $jitterFactor))
            if ($delay -lt 0) { $delay = 0 }

            if ($null -ne $EventSink -and $EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
                try {
                    $EventSink.WriteEvent(
                        'StepRetrying',
                        "Transient failure in '$OperationName' (attempt $attempt/$MaxAttempts). Retrying.",
                        $StepName,
                        @{
                            attempt     = $attempt
                            maxAttempts = $MaxAttempts
                            delayMs     = $delay
                            errorType   = $exception.GetType().FullName
                            message     = $exception.Message
                        }
                    )
                }
                catch {
                    # Intentionally ignored, but surfaced for diagnostics.
                    Write-Verbose "EventSink.WriteEvent failed: $($_.Exception.Message)"
                }
            }

            if ($delay -gt 0) {
                Start-Sleep -Milliseconds $delay
            }

            continue
        }
    }
}
