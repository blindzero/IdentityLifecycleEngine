function Get-IdleTemplatePath {
    <#
    .SYNOPSIS
    Returns the placeholder paths of a template string.

    .DESCRIPTION
    Applies the same escape handling as Resolve-IdleTemplateString with the State root enabled (escaped \{{
    sequences are not templates) and returns the trimmed path of every {{...}} placeholder, in order of appearance.
    Paths are not validated.

    .PARAMETER Value
    The string to scan.

    .OUTPUTS
    System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    # Paths are enumerated to the pipeline; callers wrap the result in @().
    if ($Value -notlike '*{{*') {
        return
    }

    $normalized = [regex]::Replace($Value, (Get-IdleTemplateEscapePattern -IncludeState), [string][char]0xE001)
    foreach ($match in [regex]::Matches($normalized, '\{\{([^}]+)\}\}')) {
        $match.Groups[1].Value.Trim()
    }
}
