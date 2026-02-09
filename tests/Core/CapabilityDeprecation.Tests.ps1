Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    Import-IdleTestMailboxModule
    
    # Import mailbox steps module for capability metadata
    $mailboxStepsPath = Join-Path $PSScriptRoot '..' '..' 'src' 'IdLE.Steps.Mailbox' 'IdLE.Steps.Mailbox.psd1'
    if (Test-Path $mailboxStepsPath) {
        Import-Module $mailboxStepsPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Capability Deprecation and Migration' {
    Context 'IdLE.Mailbox.Read deprecation' {
        It 'Maps deprecated IdLE.Mailbox.Read to IdLE.Mailbox.Info.Read with warning' {
            # Create a mock provider that advertises the old capability
            $mockProvider = [PSCustomObject]@{
                PSTypeName = 'IdLE.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'IdLE.Mailbox.Read'
                    'IdLE.Mailbox.Type.Ensure'
                    'IdLE.Mailbox.OutOfOffice.Ensure'
                )
            }

            # Use a real workflow file that uses mailbox steps
            $wfPath = Join-Path $PSScriptRoot '..' '..' 'examples' 'workflows' 'templates' 'exo-leaver-mailbox-offboarding.psd1'
            
            # Verify the workflow file exists
            $wfPath | Should -Exist

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver' -DesiredState @{
                Manager = @{
                    DisplayName = 'IT Support'
                    Mail        = 'support@contoso.com'
                }
            }
            $providers = @{ MockProvider = $mockProvider }

            # Planning should succeed and emit a deprecation warning
            # Capture warnings by redirecting stream 3 to output
            $output = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers 3>&1
            
            # Separate plan from warnings
            $plan = $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $warnings = $output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            # Assert plan was created successfully
            $plan | Should -Not -BeNullOrEmpty

            # Assert deprecation warning was emitted
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -Match "DEPRECATED.*IdLE\.Mailbox\.Read.*IdLE\.Mailbox\.Info\.Read" -Because "Should emit deprecation warning for IdLE.Mailbox.Read"
        }

        It 'New capability IdLE.Mailbox.Info.Read does not emit warning' {
            # Create a mock provider that advertises the new capability
            $mockProvider = [PSCustomObject]@{
                PSTypeName = 'IdLE.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'IdLE.Mailbox.Info.Read'
                    'IdLE.Mailbox.Type.Ensure'
                    'IdLE.Mailbox.OutOfOffice.Ensure'
                )
            }

            # Use a real workflow file
            $wfPath = Join-Path $PSScriptRoot '..' '..' 'examples' 'workflows' 'templates' 'exo-leaver-mailbox-offboarding.psd1'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver' -DesiredState @{
                Manager = @{
                    DisplayName = 'IT Support'
                    Mail        = 'support@contoso.com'
                }
            }
            $providers = @{ MockProvider = $mockProvider }

            # Planning should succeed without deprecation warnings
            $output = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers 3>&1

            # Separate plan from warnings
            $plan = $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $warnings = $output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

            # Assert plan was created successfully
            $plan | Should -Not -BeNullOrEmpty

            # Assert NO deprecation warning was emitted for the new capability
            $matchedWarnings = $warnings | Where-Object { $_.Message -match "DEPRECATED.*IdLE\.Mailbox" }
            $matchedWarnings | Should -BeNullOrEmpty -Because "New capability should not emit deprecation warning"
        }
    }
}
