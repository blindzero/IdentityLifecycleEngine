# Module Publishing Order Configuration
#
# This file defines the order in which IdLE modules should be published to PSGallery.
# The order is critical to ensure dependencies are available before dependent modules.
#
# Dependency order:
#   1. IdLE.Core - Foundation module, no IdLE dependencies
#   2. IdLE.Steps.Common - Requires IdLE.Core
#   3. IdLE - Meta-module, requires Core + Steps.Common
#   4. All other modules - Providers and additional step modules

@{
    # Modules to publish in dependency order
    PublishOrder = @(
        'IdLE.Core'
        'IdLE.Steps.Common'
        'IdLE'
        'IdLE.Steps.DirectorySync'
        'IdLE.Steps.Mailbox'
        'IdLE.Provider.AD'
        'IdLE.Provider.EntraID'
        'IdLE.Provider.ExchangeOnline'
        'IdLE.Provider.DirectorySync.EntraConnect'
        'IdLE.Provider.Mock'
    )
}
