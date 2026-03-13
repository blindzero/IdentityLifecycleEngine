@{
  Name           = 'Resolver Profile Attribute Condition Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      With       = @{
        IdentityKey = 'user1'
        Provider    = 'Identity'
      }
    }
  )
  Steps = @(
    @{
      Name      = 'ContractorStep'
      Type      = 'IdLE.Step.EmitEvent'
      # Profile attributes are nested under Attributes key.
      # Use Views path for the aggregated view across all providers.
      Condition = @{
        Like = @{
          Path    = 'Request.Context.Views.Identity.Profile.Attributes.Department'
          Pattern = 'Contractors'
        }
      }
    }
    @{
      Name      = 'ScopedProfileStep'
      Type      = 'IdLE.Step.EmitEvent'
      # Scoped path: check attribute from the specific provider/session.
      Condition = @{
        Exists = 'Request.Context.Providers.Identity.Default.Identity.Profile.Attributes'
      }
    }
  )
}
