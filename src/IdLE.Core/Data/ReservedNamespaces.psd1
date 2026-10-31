# ReservedNamespaces.psd1 - IdLE.Core
#
# Data-only single source of truth for identifier namespaces (no ScriptBlocks).
#
# Rules (owner first, then product):
# - 'IdLE.' is reserved for the IdLE project (first-party modules shipped in the IdLE bundle).
# - Extensions (every other module, host or organization) use '<Owner>.IdLE.<...>', e.g. 'Contoso.IdLE.Step.Hr.SyncManager'.
#
# Each identifier kind declares:
#   ExtensionPattern - regex an extension identifier must match
#   Example          - extension example used in error messages
@{
    ReservedPrefix = 'IdLE.'

    StepType       = @{
        FirstPartyPattern = '^IdLE\.Step(\.[A-Za-z][A-Za-z0-9]*)+$'
        ExtensionPattern = '^(?!IdLE\.)[A-Za-z][A-Za-z0-9]*\.IdLE\.Step(\.[A-Za-z][A-Za-z0-9]*)+$'
        Example          = 'Contoso.IdLE.Step.Hr.SyncManager'
    }

    Capability     = @{
        ExtensionPattern = '^(?!IdLE\.)[A-Za-z][A-Za-z0-9]*\.IdLE(\.[A-Za-z][A-Za-z0-9]*){2,}$'
        Example          = 'Contoso.IdLE.Hr.Manager.Read'

        # Capabilities defined by IdLE. 'IdLE.*' capabilities not listed here are rejected,
        # whether advertised by a provider or required by step metadata.
        # Keep in sync with docs/reference/capabilities.md (enforced by tests).
        Defined          = @(
            'IdLE.DirectorySync.Status'
            'IdLE.DirectorySync.Trigger'
            'IdLE.Entitlement.Grant'
            'IdLE.Entitlement.List'
            'IdLE.Entitlement.Prune'
            'IdLE.Entitlement.Revoke'
            'IdLE.Identity.Attribute.Ensure'
            'IdLE.Identity.Create'
            'IdLE.Identity.Delete'
            'IdLE.Identity.Disable'
            'IdLE.Identity.Enable'
            'IdLE.Identity.List'
            'IdLE.Identity.Move'
            'IdLE.Identity.Read'
            'IdLE.Identity.RevokeSessions'
            'IdLE.Mailbox.Info.Read'
            'IdLE.Mailbox.OutOfOffice.Ensure'
            'IdLE.Mailbox.Permissions.Ensure'
            'IdLE.Mailbox.Type.Ensure'
        )

        # Deprecated capability -> replacement. Accepted with a warning and mapped to the replacement.
        Deprecated       = @{
            'IdLE.Mailbox.Read' = 'IdLE.Mailbox.Info.Read'
        }
    }
}
