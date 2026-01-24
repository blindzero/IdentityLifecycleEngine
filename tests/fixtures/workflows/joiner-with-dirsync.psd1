@{
    # This workflow tests DirectorySync step metadata resolution during the Joiner lifecycle event.
    # It intentionally omits actual joiner steps to focus solely on DirectorySync step capability derivation.
    Name           = 'Joiner - DirectorySync Metadata Test'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Trigger directory sync'
            Type = 'IdLE.Step.TriggerDirectorySync'
            With = @{
                AuthSessionName = 'DirSync'
                PolicyType      = 'Delta'
                Wait            = $false
                Provider        = 'DirectorySync'
            }
        }
    )
}
