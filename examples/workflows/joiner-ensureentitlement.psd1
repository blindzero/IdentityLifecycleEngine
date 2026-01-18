@{
    Name           = 'Joiner - Ensure Entitlement'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name                 = 'Ensure Department'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{ IdentityKey = 'user1'; Name = 'Department'; Value = 'IT'; Provider = 'Identity' }
            RequiresCapabilities = 'IdLE.Identity.Attribute.Ensure'
        },
        @{
            Name                 = 'Assign demo group'
            Type                 = 'IdLE.Step.EnsureEntitlement'
            With                 = @{ IdentityKey = 'user1'; Entitlement = @{ Kind = 'Group'; Id = 'demo-group'; DisplayName = 'Demo Group' }; State = 'Present'; Provider = 'Identity' }
            RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
        }
    )
}
