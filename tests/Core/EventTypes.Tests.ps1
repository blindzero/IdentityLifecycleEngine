Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleEventTypesFailStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [object] $Step
        )

        throw 'Boom'
    }

    function Invoke-EventTypesWorkflow {
        param(
            [Parameter(Mandatory)]
            [string] $Content,

            [Parameter()]
            [string] $LifecycleEvent = 'Joiner',

            [Parameter()]
            [hashtable] $Providers = @{}
        )

        $wfPath = New-IdleTestWorkflowFile -FileName 'event-types.psd1' -Content $Content
        $req = New-IdleTestRequest -LifecycleEvent $LifecycleEvent
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $Providers
        return Invoke-IdlePlan -Plan $plan -Providers $Providers
    }

    function Get-PreconditionEventWorkflow {
        param(
            [Parameter(Mandatory)]
            [string] $EventBody
        )

        return @"
@{
  Name           = 'Precondition event'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name                = 'Emit'
      Type                = 'IdLE.Step.EmitEvent'
      Precondition        = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
      OnPreconditionFalse = 'Continue'
      PreconditionEvent   = @{ $EventBody }
    }
  )
}
"@
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleEventTypesFailStep' -ErrorAction SilentlyContinue
}

Describe 'Event types and levels' {
    Context 'Event object (New-IdleEvent)' {
        It 'defaults Level to Information' {
            InModuleScope 'IdLE.Core' {
                $evt = New-IdleEvent -Type 'IdLE.Run.Started' -Message 'm'
                $evt.Level | Should -Be 'Information'
            }
        }

        It 'rejects the catch-all type <_>' -ForEach @('Information', 'Warning', 'Error', 'Custom') {
            InModuleScope 'IdLE.Core' -Parameters @{ Type = $_ } {
                param($Type)
                { New-IdleEvent -Type $Type -Message 'm' } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }

        It 'rejects an unknown level' {
            InModuleScope 'IdLE.Core' {
                { New-IdleEvent -Type 'IdLE.Run.Started' -Message 'm' -Level 'Critical' } |
                    Should -Throw -ErrorId 'ParameterArgumentValidationError,New-IdleEvent'
            }
        }
    }

    Context 'Context.EventSink.WriteEvent' {
        It 'keeps four-argument calls working and accepts an optional Level' {
            InModuleScope 'IdLE.Core' {
                $buffer = [System.Collections.Generic.List[object]]::new()
                $sink = New-IdleEventSink -CorrelationId 'c1' -EventBuffer $buffer

                $sink.WriteEvent('Contoso.IdLE.Hr.ManagerSynced', 'm', 'S1', @{})
                $sink.WriteEvent('Contoso.IdLE.Hr.ManagerMissing', 'm', 'S1', @{}, 'Warning')

                $buffer[0].Level | Should -Be 'Information'
                $buffer[1].Level | Should -Be 'Warning'
            }
        }
    }

    Context 'Engine event levels' {
        It 'emits Information events for a successful run' {
            $result = Invoke-EventTypesWorkflow -Content @'
@{
  Name           = 'Ok'
  LifecycleEvent = 'Joiner'
  Steps          = @( @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent' } )
}
'@

            $result.Status | Should -Be 'Completed'
            @($result.Events | ForEach-Object Type) | Should -Be @('IdLE.Run.Started', 'IdLE.Step.Started', 'IdLE.Step.EmitEvent.Emitted', 'IdLE.Step.Completed', 'IdLE.Run.Completed')
            @($result.Events | Where-Object Level -ne 'Information').Count | Should -Be 0
        }

        It 'emits Error levels for a failed step and run' {
            $providers = @{
                StepRegistry = @{ 'Test.IdLE.Step.Fail' = 'Invoke-IdleEventTypesFailStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Fail')
            }

            $result = Invoke-EventTypesWorkflow -Providers $providers -Content @'
@{
  Name           = 'Fail'
  LifecycleEvent = 'Joiner'
  Steps          = @( @{ Name = 'Fail'; Type = 'Test.IdLE.Step.Fail' } )
  OnFailureSteps = @( @{ Name = 'Cleanup'; Type = 'Test.IdLE.Step.Fail' } )
}
'@

            $result.Status | Should -Be 'Failed'
            ($result.Events | Where-Object Type -eq 'IdLE.Step.Failed').Level | Should -Be 'Error'
            ($result.Events | Where-Object Type -eq 'IdLE.OnFailure.StepFailed').Level | Should -Be 'Error'
            ($result.Events | Where-Object Type -eq 'IdLE.OnFailure.Completed').Level | Should -Be 'Warning'
            ($result.Events | Where-Object Type -eq 'IdLE.Run.Completed').Level | Should -Be 'Error'
        }

        It 'emits Warning levels for a blocked step and run' {
            $result = Invoke-EventTypesWorkflow -LifecycleEvent 'Leaver' -Content @'
@{
  Name           = 'Blocked'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name         = 'Emit'
      Type         = 'IdLE.Step.EmitEvent'
      Precondition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
    }
  )
}
'@

            $result.Status | Should -Be 'Blocked'
            ($result.Events | Where-Object Type -eq 'IdLE.Step.PreconditionFailed').Level | Should -Be 'Warning'
            ($result.Events | Where-Object Type -eq 'IdLE.Step.Blocked').Level | Should -Be 'Warning'
            ($result.Events | Where-Object Type -eq 'IdLE.Run.Completed').Level | Should -Be 'Warning'
        }
    }

    Context 'Workflow-defined event types' {
        It 'emits a PreconditionEvent with the configured Level' {
            $content = Get-PreconditionEventWorkflow -EventBody "Type = 'Contoso.ManualActionRequired'; Message = 'Wipe device'; Level = 'Warning'"
            $result = Invoke-EventTypesWorkflow -LifecycleEvent 'Leaver' -Content $content

            $evt = $result.Events | Where-Object Type -eq 'Contoso.ManualActionRequired'
            $evt.Level | Should -Be 'Warning'
        }

        It 'defaults the PreconditionEvent Level to Information' {
            $content = Get-PreconditionEventWorkflow -EventBody "Type = 'Contoso.ManualActionRequired'; Message = 'Wipe device'"
            $result = Invoke-EventTypesWorkflow -LifecycleEvent 'Leaver' -Content $content

            ($result.Events | Where-Object Type -eq 'Contoso.ManualActionRequired').Level | Should -Be 'Information'
        }

        It 'rejects PreconditionEvent.Type <Type> at planning time (<Code>)' -ForEach @(
            @{ Type = 'IdLE.Step.Blocked'; Code = 'ReservedNamespace' }
            @{ Type = 'Warning'; Code = 'InvalidEventType' }
            @{ Type = 'Custom'; Code = 'InvalidEventType' }
        ) {
            $content = Get-PreconditionEventWorkflow -EventBody "Type = '$Type'; Message = 'm'"
            $wfPath = New-IdleTestWorkflowFile -FileName 'event-types-invalid.psd1' -Content $content
            $req = New-IdleTestRequest -LifecycleEvent 'Leaver'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw "*PreconditionEvent.Type*${Code}:*"
        }

        It 'rejects an unknown PreconditionEvent.Level at planning time' {
            $content = Get-PreconditionEventWorkflow -EventBody "Type = 'Contoso.ManualActionRequired'; Message = 'm'; Level = 'Critical'"
            $wfPath = New-IdleTestWorkflowFile -FileName 'event-types-invalid.psd1' -Content $content
            $req = New-IdleTestRequest -LifecycleEvent 'Leaver'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw '*PreconditionEvent.Level*'
        }

        It 'emits EmitEvent with the workflow-defined Type and Level' {
            $result = Invoke-EventTypesWorkflow -Content @'
@{
  Name           = 'Emit'
  LifecycleEvent = 'Joiner'
  Steps          = @( @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Type = 'Contoso.Joiner.Notified'; Level = 'Warning'; Message = 'Hi' } } )
}
'@

            $evt = $result.Events | Where-Object Type -eq 'Contoso.Joiner.Notified'
            $evt.Level | Should -Be 'Warning'
            $evt.Message | Should -Be 'Hi'
        }

        It 'fails the EmitEvent step for a reserved or catch-all With.Type (<_>)' -ForEach @('IdLE.Run.Completed', 'Custom') {
            $content = @"
@{
  Name           = 'Emit'
  LifecycleEvent = 'Joiner'
  Steps          = @( @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Type = '$_' } } )
}
"@
            $result = Invoke-EventTypesWorkflow -Content $content

            $result.Status | Should -Be 'Failed'
            $result.Steps[0].Status | Should -Be 'Failed'
        }

        It 'checks <Identifier> -> <Expected>' -ForEach @(
            @{ Identifier = 'Contoso.ManualActionRequired'; Expected = $null }
            @{ Identifier = 'ManualActionRequired'; Expected = $null }
            @{ Identifier = 'IdLE.Step.Failed'; Expected = 'ReservedNamespace' }
            @{ Identifier = 'idle.custom'; Expected = 'ReservedNamespace' }
            @{ Identifier = 'Information'; Expected = 'InvalidEventType' }
            @{ Identifier = 'Error'; Expected = 'InvalidEventType' }
        ) {
            InModuleScope 'IdLE.Core' -Parameters $_ {
                param($Identifier, $Expected)

                $namespaceError = Get-IdleIdentifierNamespaceError -Kind WorkflowEventType -Identifier $Identifier

                if ($null -eq $Expected) {
                    $namespaceError | Should -BeNullOrEmpty
                }
                else {
                    $namespaceError | Should -BeLike "${Expected}:*"
                }
            }
        }
    }

    Context 'Documentation' {
        It 'documents every first-party event type emitted in src in docs/extend/events.md' {
            $repoRoot = Get-RepoRootPath
            $doc = Get-Content -Path (Join-Path $repoRoot 'docs/extend/events.md') -Raw

            # Event types are the first literal of a WriteEvent(...) call (same line or the next one).
            $emitted = foreach ($file in Get-ChildItem -Path (Join-Path $repoRoot 'src') -Filter '*.ps1' -Recurse -File) {
                $lines = @(Get-Content -Path $file.FullName)
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -notmatch 'WriteEvent\(') { continue }
                    $window = $lines[$i] + ' ' + $(if ($i + 1 -lt $lines.Count) { $lines[$i + 1] } else { '' })
                    if ($window -match "WriteEvent\(\s*'(IdLE\.[A-Za-z.]+)'") { $Matches[1] }
                }
            }
            $emitted = @($emitted | Sort-Object -Unique)

            $emitted.Count | Should -BeGreaterThan 20
            $undocumented = @($emitted | Where-Object { $doc -notmatch [regex]::Escape("``$_``") })
            $undocumented | Should -BeNullOrEmpty
        }
    }
}
