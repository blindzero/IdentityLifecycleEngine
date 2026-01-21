@{
  Name           = 'Joiner - Entitlement Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Ensure group membership'
      Type = 'IdLE.Step.EnsureEntitlement'
      With = @{ IdentityKey = 'user1'; Entitlement = @{ Kind = 'Group'; Id = 'demo-group' }; State = 'Present' }
    }
  )
}
