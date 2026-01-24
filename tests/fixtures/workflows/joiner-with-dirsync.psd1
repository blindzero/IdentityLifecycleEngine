@{
    Name           = 'Joiner - DirectorySync Test'
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
