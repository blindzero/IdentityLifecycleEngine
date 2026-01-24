function New-IdleEntraConnectDirectorySyncProvider {
    <#
    .SYNOPSIS
    Creates an Entra Connect directory sync provider for IdLE.

    .DESCRIPTION
    This provider triggers and monitors Entra ID Connect (ADSync) sync cycles on an
    on-premises server via remote execution.

    The provider uses an AuthSession object (remote execution handle) provided by the host.
    The AuthSession must implement InvokeCommand(CommandName, Parameters) to execute
    commands in an elevated/privileged context on the Entra Connect server.

    No interactive prompts are made; elevation and authentication are the host's responsibility
    via the AuthSessionBroker.

    .OUTPUTS
    PSCustomObject
    Provider instance with methods: GetCapabilities(), StartSyncCycle(PolicyType, AuthSession), GetSyncCycleState(AuthSession)

    .EXAMPLE
    $provider = New-IdleEntraConnectDirectorySyncProvider
    $provider.GetCapabilities()
    # Returns: @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')

    .EXAMPLE
    # With a mock remote execution handle
    $mockAuthSession = [pscustomobject]@{
        InvokeCommand = { param($CommandName, $Parameters)
            # Mock implementation
            return @{ Started = $true }
        }
    }
    $provider = New-IdleEntraConnectDirectorySyncProvider
    $result = $provider.StartSyncCycle('Delta', $mockAuthSession)
    #>
    [CmdletBinding()]
    param()

    $provider = [pscustomobject]@{
        PSTypeName = 'IdLE.Provider.EntraConnectDirectorySync'
        Name       = 'EntraConnectDirectorySyncProvider'
    }

    $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
        <#
        .SYNOPSIS
        Advertises the capabilities provided by this provider instance.

        .DESCRIPTION
        Capabilities are stable string identifiers used by IdLE to validate that
        a workflow plan can be executed with the available providers.
        #>

        return @(
            'IdLE.DirectorySync.Trigger'
            'IdLE.DirectorySync.Status'
        )
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name StartSyncCycle -Value {
        <#
        .SYNOPSIS
        Triggers an Entra Connect sync cycle.

        .DESCRIPTION
        Triggers a sync cycle via Start-ADSyncSyncCycle on the remote Entra Connect server.

        .PARAMETER PolicyType
        The sync policy type: 'Delta' or 'Initial'.

        .PARAMETER AuthSession
        Remote execution handle provided by the host's AuthSessionBroker.
        Must implement InvokeCommand(CommandName, Parameters).

        .OUTPUTS
        PSCustomObject with properties:
        - Started (bool): indicates whether the sync cycle was triggered
        - Message (string, optional): additional information
        #>
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Delta', 'Initial', IgnoreCase = $true)]
            [string] $PolicyType,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $AuthSession
        )

        # Validate AuthSession contract
        if ($null -eq $AuthSession.PSObject.Methods['InvokeCommand']) {
            throw "AuthSession must implement InvokeCommand(CommandName, Parameters) method. " + `
                "The host must provide an elevated remote session via AuthSessionBroker."
        }

        try {
            # Execute Start-ADSyncSyncCycle remotely
            # The remote session should already have ADSync module available or will import it
            $AuthSession.InvokeCommand('Start-ADSyncSyncCycle', @{
                    PolicyType = $PolicyType
                }) | Out-Null

            # Start-ADSyncSyncCycle returns a result object or throws on error
            # Success case: return Started = true
            return [pscustomobject]@{
                Started = $true
                Message = "Sync cycle triggered with PolicyType: $PolicyType"
            }
        }
        catch {
            # Check for common privilege/elevation errors
            $errorMessage = $_.Exception.Message

            if ($errorMessage -match 'access.*denied|permission|privilege|elevation|administrator|unauthorized') {
                throw "Failed to start sync cycle. Missing privileges or elevation. " + `
                    "The AuthSession must provide an elevated execution context. Original error: $errorMessage"
            }

            # Re-throw other errors
            throw "Failed to start sync cycle: $errorMessage"
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetSyncCycleState -Value {
        <#
        .SYNOPSIS
        Retrieves the current state of Entra Connect sync cycles.

        .DESCRIPTION
        Queries the sync scheduler state via Get-ADSyncScheduler to determine if a
        sync cycle is currently in progress.

        .PARAMETER AuthSession
        Remote execution handle provided by the host's AuthSessionBroker.
        Must implement InvokeCommand(CommandName, Parameters).

        .OUTPUTS
        PSCustomObject with properties:
        - InProgress (bool): indicates whether a sync cycle is currently running
        - State (string): 'InProgress', 'Idle', or 'Unknown'
        - Details (hashtable, optional): additional state information
        #>
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $AuthSession
        )

        # Validate AuthSession contract
        if ($null -eq $AuthSession.PSObject.Methods['InvokeCommand']) {
            throw "AuthSession must implement InvokeCommand(CommandName, Parameters) method. " + `
                "The host must provide an elevated remote session via AuthSessionBroker."
        }

        try {
            # Execute Get-ADSyncScheduler remotely
            $scheduler = $AuthSession.InvokeCommand('Get-ADSyncScheduler', @{})

            # Determine if sync is in progress
            # Get-ADSyncScheduler returns an object with SyncCycleInProgress property
            $inProgress = $false
            $state = 'Unknown'
            $details = @{}

            if ($null -ne $scheduler) {
                # Extract relevant properties
                if ($scheduler.PSObject.Properties.Name -contains 'SyncCycleInProgress') {
                    $inProgress = [bool]$scheduler.SyncCycleInProgress
                    $state = if ($inProgress) { 'InProgress' } else { 'Idle' }
                }

                # Capture additional details for diagnostics
                if ($scheduler.PSObject.Properties.Name -contains 'AllowedSyncCycleInterval') {
                    $details['AllowedSyncCycleInterval'] = $scheduler.AllowedSyncCycleInterval
                }
                if ($scheduler.PSObject.Properties.Name -contains 'NextSyncCyclePolicyType') {
                    $details['NextSyncCyclePolicyType'] = $scheduler.NextSyncCyclePolicyType
                }
            }

            return [pscustomobject]@{
                InProgress = $inProgress
                State      = $state
                Details    = $details
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            if ($errorMessage -match 'access.*denied|permission|privilege|elevation|administrator|unauthorized') {
                throw "Failed to get sync cycle state. Missing privileges or elevation. " + `
                    "The AuthSession must provide an elevated execution context. Original error: $errorMessage"
            }

            throw "Failed to get sync cycle state: $errorMessage"
        }
    } -Force

    return $provider
}
