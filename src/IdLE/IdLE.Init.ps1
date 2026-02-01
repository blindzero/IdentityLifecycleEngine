# IdLE Module Initialization Script
# This script runs via ScriptsToProcess BEFORE NestedModules are imported

# Set environment variable to suppress internal module warnings during correct nested load
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'

# NOTE: PSModulePath bootstrap for repo/zip layouts is done AFTER NestedModules load
# (in IdLE.psm1) to avoid interfering with nested module resolution
