function Get-IdleStepRegistry {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    # Registry maps workflow Step.Type -> handler
    # Handler can be:
    # - [string]      : PowerShell function name
    # - [scriptblock] : executable handler (useful for tests / hosts)
    $registry = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1) Copy host-provided StepRegistry (optional)
    # We support two shapes for compatibility:
    # - StepRegistry['Type'] = 'FunctionName' | { scriptblock }
    # - StepRegistry['Type'] = @{ Handler = 'FunctionName' }   (legacy/demo style)
    if ($null -ne $Providers) {

        $source = $null

        if ($Providers -is [System.Collections.IDictionary]) {
            if ($Providers.Contains('StepRegistry')) {
                $source = $Providers['StepRegistry']
            }
        }
        else {
            $prop = $Providers.PSObject.Properties['StepRegistry']
            if ($null -ne $prop) {
                $source = $prop.Value
            }
        }

        if ($null -ne $source -and ($source -is [System.Collections.IDictionary])) {
            foreach ($k in @($source.Keys)) {

                $v = $source[$k]

                # Allow legacy shape: @{ Handler = 'Invoke-...' }
                if ($v -is [hashtable] -and $v.ContainsKey('Handler')) {
                    $v = $v['Handler']
                }

                $registry[[string]$k] = $v
            }
        }
    }

    # 2) Built-in defaults (only if commands are available)
    # Do not overwrite host-provided entries.
    if (-not $registry.ContainsKey('IdLE.Step.EmitEvent')) {
        $cmd = Get-Command -Name 'Invoke-IdleStepEmitEvent' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $registry['IdLE.Step.EmitEvent'] = $cmd.Name
        }
    }

    if (-not $registry.ContainsKey('IdLE.Step.EnsureAttribute')) {
        $cmd = Get-Command -Name 'Invoke-IdleStepEnsureAttribute' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $registry['IdLE.Step.EnsureAttribute'] = $cmd.Name
        }
    }

    return $registry
}
