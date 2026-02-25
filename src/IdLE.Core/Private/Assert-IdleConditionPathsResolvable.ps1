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
        [string] $Source
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

        if ($pathText.StartsWith('context.')) {
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
            [System.Collections.Generic.List[string]] $PathList
        )

        if ($Node.Contains('All')) {
            foreach ($child in @($Node.All)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList
                }
            }
            return
        }

        if ($Node.Contains('Any')) {
            foreach ($child in @($Node.Any)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList
                }
            }
            return
        }

        if ($Node.Contains('None')) {
            foreach ($child in @($Node.None)) {
                if ($child -is [System.Collections.IDictionary]) {
                    Get-IdleConditionPaths -Node $child -PathList $PathList
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
            $existsVal = $Node.Exists
            if ($existsVal -is [string]) {
                Add-IdlePathIfPresent -PathList $PathList -PathCandidate $existsVal
            }
            elseif ($existsVal -is [System.Collections.IDictionary]) {
                Add-IdlePathIfPresent -PathList $PathList -PathCandidate $existsVal.Path
            }
            return
        }

        if ($Node.Contains('In')) {
            Add-IdlePathIfPresent -PathList $PathList -PathCandidate $Node.In.Path
            return
        }
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    Get-IdleConditionPaths -Node $Condition -PathList $paths

    $uniquePaths = @($paths | Select-Object -Unique)
    if ($uniquePaths.Count -eq 0) {
        return
    }

    $missingPaths = @()
    foreach ($path in $uniquePaths) {
        if (-not (Test-IdlePathExists -Object $Context -Path $path)) {
            $missingPaths += $path
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
