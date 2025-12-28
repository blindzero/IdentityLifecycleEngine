function Import-IdleWorkflowDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkflowPath
    )

    # Resolve to an absolute path early to keep error messages deterministic.
    $resolvedPath = (Resolve-Path -Path $WorkflowPath -ErrorAction Stop).Path

    # Import PSD1 via built-in data-file loader (safer than dot-sourcing).
    $data = Import-PowerShellDataFile -Path $resolvedPath

    if ($null -eq $data -or $data -isnot [hashtable]) {
        throw [System.ArgumentException]::new(
            "Workflow definition must be a hashtable at the root. Path: $resolvedPath",
            'WorkflowPath'
        )
    }

    return $data
}
