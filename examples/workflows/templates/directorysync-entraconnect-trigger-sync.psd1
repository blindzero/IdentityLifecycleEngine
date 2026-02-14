@{
    Name           = 'DirectorySync - Trigger Entra Connect Sync Cycle'
    LifecycleEvent = 'Operational'
    Description    = 'Triggers an Entra Connect (ADSync) sync cycle on the Entra Connect server and optionally waits for completion.'

    Steps          = @(
        @{
            Name = 'TriggerEntraConnectSync'
            Type = 'IdLE.Step.TriggerDirectorySync'
            With = @{
                Provider            = 'DirectorySync'

                # Auth session is provided by the host (remote execution handle).
                AuthSessionName     = 'EntraConnect'
                AuthSessionOptions  = @{
                    Role = 'EntraConnectAdmin'
                }

                # Delta or Initial
                PolicyType          = 'Delta'

                # Optional wait/polling behavior (step-specific)
                Wait                = $true
                TimeoutSeconds      = 300
                PollIntervalSeconds = 10
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Entra Connect sync cycle ({{Request.Input.PolicyType}}) triggered successfully.'
            }
        }
    )
}