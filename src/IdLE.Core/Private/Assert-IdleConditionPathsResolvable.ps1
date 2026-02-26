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

    function Add-IdlePathIfPresent {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]] $PathList,

            [Parameter(Mandatory)]
            [AllowNull()]
            [object] $PathCandidate
        )

        if ($null -eq $PathCandidate) {
            return
        }

        $pathText = [string]$PathCandidate
        if ([string]::IsNullOrWhiteSpace($pathText)) {
            return
        }

        if ($pathText.StartsWith('context.', [System.StringComparison]::OrdinalIgnoreCase)) {
            $pathText = $pathText.Substring(8)
        }

        $null = $PathList.Add($pathText)
    }

    function Get-IdleConditionPaths {
        param(
            [Parameter(Mandatory)]
            [System.Collections.IDictionary] $Node,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]] $PathList,

            [Parameter()]
            [switch] $ExcludeExistsPaths
        )

        if ($Node.Contains('All')) {
            foreach ($child in @($Node.All)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList -ExcludeExistsPaths:$ExcludeExistsPaths
                }
            }
            return
        }

        if ($Node.Contains('Any')) {
            foreach ($child in @($Node.Any)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList -ExcludeExistsPaths:$ExcludeExistsPaths
                }
            }
            return
        }

        if ($Node.Contains('None')) {
            foreach ($child in @($Node.None)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList -ExcludeExistsPaths:$ExcludeExistsPaths
                }
            }
            return
        }

        if ($Node.Contains('Equals')) {
            Add-IdlePathIfPresent -PathList $PathList -PathCandidate $Node.Equals.Path
            return
        }

        if ($Node.Contains('NotEquals')) {
            Add-IdlePathIfPresent -PathList $PathList -PathCandidate $Node.NotEquals.Path
            return
        }

        if ($Node.Contains('Exists')) {
            # Exists operator semantics: checking for the presence of a path is intentional.
            # When -ExcludeExistsPaths is set (e.g. strict execution-time validation), skip these
            # so that Exists can still return $false without causing a path-not-found error.
            if (-not $ExcludeExistsPaths) {
                $existsVal = $Node.Exists
                if ($existsVal -is [string]) {
                    Add-IdlePathIfPresent -PathList $PathList -PathCandidate $existsVal
                }
                elseif ($existsVal -is [System.Collections.IDictionary]) {
                    Add-IdlePathIfPresent -PathList $PathList -PathCandidate $existsVal.Path
                }
            }
            return
        }

        if ($Node.Contains('In')) {
            Add-IdlePathIfPresent -PathList $PathList -PathCandidate $Node.In.Path
            return
        }
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    Get-IdleConditionPaths -Node $Condition -PathList $paths -ExcludeExistsPaths:$ExcludeExistsOperatorPaths

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

    if ($softMissingContextPaths.Count -gt 0 -and $null -ne $WarningSink) {
        $warningItem = [ordered]@{
            Code    = 'PreconditionContextPathUnresolvedAtPlan'
            Type    = 'Warning'
            Step    = $StepName
            Source  = $Source
            Paths   = @($softMissingContextPaths | Select-Object -Unique)
            Message = ("Workflow step '{0}' references Request.Context path(s) in {1} that are not yet available at planning time: [{2}]. Evaluation will continue and paths may be resolved at runtime." -f $StepName, $Source, ([string]::Join(', ', @($softMissingContextPaths | Select-Object -Unique))))
        }

        if ($WarningSink -is [System.Collections.IList]) {
            $null = $WarningSink.Add($warningItem)
        }
        elseif ($WarningSink -is [object[]]) {
            # Fallback for fixed arrays: cannot mutate by reference safely.
            # Caller should pass an IList (plan.Warnings is an ArrayList) for collection.
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
