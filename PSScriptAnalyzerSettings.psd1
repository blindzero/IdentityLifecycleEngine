# PSScriptAnalyzer settings for IdentityLifecycleEngine (IdLE)
#
# This file is intentionally data-only (no script blocks, no expressions).
# It is used by CI and can also be referenced from VS Code workspace settings.
#
# Notes:
# - We explicitly list IncludeRules to keep the first rollout focused and low-noise.
# - Formatting rules are enabled to align with STYLEGUIDE.md (4 spaces, consistent whitespace).

@{
    Severity     = @('Error', 'Warning')

    IncludeRules = @(
        # Naming / API hygiene
        'PSUseApprovedVerbs',
        'PSAvoidGlobalVars',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingPositionalParameters',
        'PSUseCorrectCasing',

        # Common correctness issues
        'PSAvoidUsingEmptyCatchBlock',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidTrailingWhitespace',

        # Security / risky constructs
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',

        # Style / formatting (enabled explicitly)
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace'
    )

    Rules        = @{
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }

        PSUseConsistentWhitespace = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator                  = $true
            CheckParameter                  = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
    }
}
