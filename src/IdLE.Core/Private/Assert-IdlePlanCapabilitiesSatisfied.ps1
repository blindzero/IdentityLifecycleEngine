Set-StrictMode -Version Latest

function Assert-IdlePlanCapabilitiesSatisfied {
    <#
    .SYNOPSIS
    Validates that all required step capabilities are available.

    .DESCRIPTION
    Fail-fast validation executed during planning.
    If one or more capabilities are missing, an ArgumentException is thrown with a
    deterministic error message listing missing capabilities and affected steps.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $Steps,

        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    if ($null -eq $Steps -or @($Steps).Count -eq 0) {
        return
    }

    $required = @()
    $requiredByStep = [ordered]@{}

    foreach ($s in @($Steps)) {
        if ($null -eq $s) {
            continue
        }

        $stepName = Get-IdlePropertyValue -Object $s -Name 'Name'
        if ($null -eq $stepName -or [string]::IsNullOrWhiteSpace([string]$stepName)) {
            $stepName = '<UnnamedStep>'
        }

        $capsRaw = Get-IdlePropertyValue -Object $s -Name 'RequiresCapabilities'
        $caps = if ($null -eq $capsRaw) { @() } else { @($capsRaw) }

        if (@($caps).Count -gt 0) {
            $required += $caps
            $requiredByStep[$stepName] = @($caps)
        }
    }

    $required = @($required | Sort-Object -Unique)
    if (@($required).Count -eq 0) {
        return
    }

    $available = @(Get-IdleAvailableCapabilities -Providers $Providers)

    $missing = @()
    foreach ($c in $required) {
        if ($available -notcontains $c) {
            $missing += $c
        }
    }

    $missing = @($missing | Sort-Object -Unique)
    if (@($missing).Count -eq 0) {
        return
    }

    $affectedSteps = @()
    foreach ($k in $requiredByStep.Keys) {
        $capsForStep = @($requiredByStep[$k])
        foreach ($m in $missing) {
            if ($capsForStep -contains $m) {
                $affectedSteps += $k
                break
            }
        }
    }

    $affectedSteps = @($affectedSteps | Sort-Object -Unique)

    $msg = @()
    $msg += "Plan cannot be built because required provider capabilities are missing."
    $msg += ("MissingCapabilities: {0}" -f ([string]::Join(', ', @($missing))))
    $msg += ("AffectedSteps: {0}" -f ([string]::Join(', ', @($affectedSteps))))
    $msg += ("AvailableCapabilities: {0}" -f ([string]::Join(', ', @($available))))

    throw [System.ArgumentException]::new(([string]::Join(' ', $msg)), 'Providers')
}
