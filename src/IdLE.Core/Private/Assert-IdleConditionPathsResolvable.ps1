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

    foreach ($path in @($paths | Select-Object -Unique)) {
        if (-not (Test-IdlePathExists -Object $Context -Path $path)) {
            throw [System.ArgumentException]::new(
                ("Workflow step '{0}' references path '{1}' in {2}, but the path does not exist in the current planning context. Check Request/Plan structure or ContextResolvers outputs." -f $StepName, $path, $Source),
                'Workflow'
            )
        }
    }
}
