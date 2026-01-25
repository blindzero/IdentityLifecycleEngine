# IdLE Module Initialization Script
# This script runs BEFORE nested modules are loaded (via ScriptsToProcess in manifest)
# Set environment variable to suppress internal module warnings during correct nested load
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'
