@{
  Name           = 'Joiner - Trigger Entra Connect Sync'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Create AD account'
      Type = 'IdLE.Step.CreateIdentity'
      With = @{
        IdentityKey    = '{{ Request.Username }}'
        Attributes     = @{
          GivenName  = '{{ Request.GivenName }}'
          Surname    = '{{ Request.Surname }}'
          Department = '{{ Request.Department }}'
        }
        AuthSessionName = 'SourceAD'
        Provider        = 'Identity'
      }
    }
    @{
      Name = 'Trigger Entra Connect Delta Sync'
      Type = 'IdLE.Step.TriggerDirectorySync'
      With = @{
        AuthSessionName      = 'EntraConnect'
        AuthSessionOptions   = @{
          Role = 'EntraConnectAdmin'
        }
        PolicyType           = 'Delta'
        Wait                 = $true
        TimeoutSeconds       = 300
        PollIntervalSeconds  = 10
        Provider             = 'DirectorySync'
      }
    }
    @{
      Name = 'Assign Entra ID group membership'
      Type = 'IdLE.Step.EnsureEntitlement'
      With = @{
        IdentityKey    = '{{ Request.Username }}'
        Entitlement    = @{
          Kind        = 'Group'
          Id          = 'EntraID-Users-Group'
          DisplayName = 'Entra ID Users'
        }
        State          = 'Present'
        AuthSessionName = 'EntraID'
        Provider        = 'Cloud'
      }
    }
  )
}
