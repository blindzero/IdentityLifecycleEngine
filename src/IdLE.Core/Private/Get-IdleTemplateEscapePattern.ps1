function Get-IdleTemplateEscapePattern {
    <#
    .SYNOPSIS
    Returns the regex that matches escaped template openings (\{{ not followed by a valid template path).

    .DESCRIPTION
    \{{ is an escape for a literal {{ unless it is followed by a valid allowed-root template path and }}.
    In that case the backslash is a literal character and the template is resolved (e.g. DOMAIN\{{Request.IdentityKeys.sAMAccountName}}).

    The lookahead is restricted to the exact set of allowed roots so that sequences like \{{Request.Foo}}
    (invalid root) or \{{Request..Name}} (double dot) are escaped to literal {{ rather than failing with path/root errors.

    Shared by Resolve-IdleTemplateString and Get-IdleTemplatePath so that template detection and
    resolution always agree on what is a template.

    .PARAMETER IncludeState
    Treat State.<StepName>.* as an allowed root (With templates of workflow steps).

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [switch] $IncludeState
    )

    $stateRoot = if ($IncludeState) { '|State(?:\.[A-Za-z0-9_]+)+' } else { '' }
    return "\\{{(?!(?:Request\.(?:(?:Intent|Context|IdentityKeys)(?:\.[A-Za-z0-9_]+)*|LifecycleEvent|CorrelationId|Actor)$stateRoot)}})"
}
