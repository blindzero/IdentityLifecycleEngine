@{
    Name           = 'Joiner - Ensure Entitlement'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Ensure Department'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{ IdentityKey = 'user1'; Attributes = @{ Department = 'IT' }; Provider = 'Identity' }
        },
        @{
            Name = 'Assign demo group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{ IdentityKey = 'user1'; Entitlement = @{ Kind = 'Group'; Id = 'demo-group'; DisplayName = 'Demo Group' }; State = 'Present'; Provider = 'Identity' }
        }
    )
}
