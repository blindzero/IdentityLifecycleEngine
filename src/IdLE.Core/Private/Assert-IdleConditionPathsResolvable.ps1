Set-StrictMode -Version Latest

function Assert-IdleConditionPathsResolvable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Condition,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Source,

        [Parameter()]
        [switch] $AllowMissingRequestContextPaths,

        [Parameter()]
        [AllowNull()]
        [object] $WarningSink,

        # When set, skips validation of paths used by the Exists operator.
        # Exists semantics intentionally allow missing paths (returns $false if absent),
        # so strict execution-time path validation should exclude those paths.
        [Parameter()]
        [switch] $ExcludeExistsOperatorPaths
    )

    # Contains/NotContains/Like/NotLike paths are not validated here (unchanged behavior).
    # State paths are checked during planning (State reference validation); at execution a State path whose
    # producer published nothing resolves to $null instead of failing.
    $validatedOperators = @('Equals', 'NotEquals', 'Exists', 'In')
    $paths = foreach ($conditionPath in @(Get-IdleConditionPath -Condition $Condition)) {
        if ($validatedOperators -notcontains $conditionPath.Operator) { continue }
        if ($ExcludeExistsOperatorPaths -and $conditionPath.Operator -eq 'Exists') { continue }
        if ($conditionPath.Path -eq 'State' -or $conditionPath.Path.StartsWith('State.', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $conditionPath.Path
    }

    $uniquePaths = @($paths | Select-Object -Unique)
    if ($uniquePaths.Count -eq 0) {
        return
    }

    $missingPaths = @()
    $softMissingContextPaths = @()
    foreach ($path in $uniquePaths) {
        if (-not (Test-IdlePathExists -Object $Context -Path $path)) {
            if ($AllowMissingRequestContextPaths -and $path.StartsWith('Request.Context.')) {
                $softMissingContextPaths += $path
                continue
            }
            $missingPaths += $path
        }
    }

    if ($softMissingContextPaths.Count -gt 0) {
        $uniqueSoftPaths = @($softMissingContextPaths | Select-Object -Unique)
        $warningMessage = "Workflow step '{0}' references Request.Context path(s) in {1} that are not yet available at planning time: [{2}]. Evaluation will continue and paths may be resolved at runtime." -f $StepName, $Source, ([string]::Join(', ', $uniqueSoftPaths))

        # Emit a visible PowerShell warning for immediate host feedback during planning.
        Write-Warning $warningMessage

        if ($null -ne $WarningSink) {
            $warningItem = [ordered]@{
                Code    = 'PreconditionContextPathUnresolvedAtPlan'
                Type    = 'Warning'
                Step    = $StepName
                Source  = $Source
                Paths   = $uniqueSoftPaths
                Message = $warningMessage
            }

            if ($WarningSink -is [System.Collections.IList]) {
                $null = $WarningSink.Add($warningItem)
            }
        }
    }

    if ($missingPaths.Count -gt 0) {
        $missingPathList = [string]::Join(', ', $missingPaths)
        throw [System.ArgumentException]::new(
            ("Workflow step '{0}' has unresolved condition path(s) in {1}: [{2}]. Check Request/Plan structure or ContextResolvers outputs." -f $StepName, $Source, $missingPathList),
            'Workflow'
        )
    }
}
