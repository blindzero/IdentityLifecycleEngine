# Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')

    $script:RepoRoot = Get-RepoRootPath
    $script:GeneratorPath = Join-Path $script:RepoRoot 'tools/Generate-IdleStepReference.ps1'

    if (-not (Test-Path -LiteralPath $script:GeneratorPath)) {
        throw "Step reference generator not found: $script:GeneratorPath"
    }

    $script:OutputPath = Join-Path $TestDrive 'steps.md'
    $script:DetailDirectory = Join-Path $TestDrive 'steps'

    # The generator removes and re-imports all IdLE modules, so run it in a separate process to keep the
    # module state of this test session intact.
    $output = & pwsh -NoProfile -NonInteractive -File $script:GeneratorPath -OutputPath $script:OutputPath -DetailOutputDirectory $script:DetailDirectory 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Step reference generator failed (exit code $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }

    # Map step type -> generated page content; the first line of each page is '# <StepType>'.
    $script:PagesByStepType = @{}
    foreach ($file in Get-ChildItem -Path $script:DetailDirectory -Filter '*.md' -File) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $stepType = (($text -split "`r?`n", 2)[0] -replace '^#\s+', '').Trim()
        $script:PagesByStepType[$stepType] = $text
    }
}

Describe 'Generate-IdleStepReference.ps1' {

    Context 'Required capabilities' {

        BeforeDiscovery {
            $repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '../..')).Path
            $catalogFiles = Get-ChildItem -Path (Join-Path $repoRoot 'src') -Directory -Filter 'IdLE.Steps.*' |
                ForEach-Object { Join-Path $_.FullName 'StepMetadataCatalog.psd1' } |
                Where-Object { Test-Path -LiteralPath $_ }

            $script:StepCases = foreach ($catalogFile in $catalogFiles) {
                $catalog = Import-PowerShellDataFile -Path $catalogFile
                foreach ($stepType in $catalog.Keys) {
                    $metadata = $catalog[$stepType]
                    if ($metadata.Contains('RequiredCapabilities') -and @($metadata['RequiredCapabilities']).Count -gt 0) {
                        @{ StepType = $stepType; Capabilities = @($metadata['RequiredCapabilities']) }
                    }
                }
            }
        }

        It 'catalogs declare at least one step with required capabilities' -ForEach @(@{ CaseCount = @($script:StepCases).Count }) {
            # Guards against the test silently passing because no cases were discovered.
            $CaseCount | Should -BeGreaterThan 0
        }

        It 'renders the required capabilities of <StepType>' -ForEach $script:StepCases {
            $script:PagesByStepType.ContainsKey($StepType) | Should -BeTrue -Because "a page for '$StepType' must be generated"

            $expected = ($Capabilities | ForEach-Object { "``$_``" }) -join ', '
            $script:PagesByStepType[$StepType] | Should -Match ([regex]::Escape("- **Required Capabilities**: $expected"))
        }
    }
}
