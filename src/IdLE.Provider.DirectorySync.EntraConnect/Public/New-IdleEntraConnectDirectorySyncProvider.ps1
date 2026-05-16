function New-IdleEntraConnectDirectorySyncProvider {
    <#
    .SYNOPSIS
    Creates an Entra Connect directory sync provider for IdLE.

    .DESCRIPTION
    This provider triggers and monitors Entra ID Connect (ADSync) sync cycles on an
    on-premises server via remote execution.

    The provider uses a credential AuthSession provided by the host and establishes
    a PSRemoting session to the target Entra Connect server internally.

    No interactive prompts are made; elevation and authentication are the host's responsibility
    via the AuthSessionBroker.

    .OUTPUTS
    PSCustomObject
    Provider instance with methods: GetCapabilities(), StartSyncCycle(PolicyType, ComputerName, AuthSession), GetSyncCycleState(ComputerName, AuthSession)

    .EXAMPLE
    $provider = New-IdleEntraConnectDirectorySyncProvider
    $provider.GetCapabilities()
    # Returns: @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')

    .EXAMPLE
    # With a credential from AuthSessionBroker (AuthSessionType='Credential')
    $credential = Get-Credential
    $provider = New-IdleEntraConnectDirectorySyncProvider
    $result = $provider.StartSyncCycle('Delta', 'ad-sync1.corp.local', $credential)
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

    $provider | Add-Member -MemberType ScriptMethod -Name NewRemoteSession -Value {
        param(
            [Parameter(Mandatory)]
            [string] $ComputerName,

            [Parameter(Mandatory)]
            [pscredential] $Credential
        )

        try {
            return New-PSSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
        }
        catch {
            throw "Failed to establish PSRemoting session to '$ComputerName': $($_.Exception.Message)"
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name InvokeRemoteCommand -Value {
        param(
            [Parameter(Mandatory)]
            [object] $Session,

            [Parameter(Mandatory)]
            [scriptblock] $ScriptBlock,

            [Parameter()]
            [AllowNull()]
            [object[]] $ArgumentList
        )

        if ($null -eq $ArgumentList -or $ArgumentList.Count -eq 0) {
            return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ErrorAction Stop
        }

        return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name RemoveRemoteSession -Value {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            [object] $Session
        )

        if ($null -ne $Session) {
            try {
                Remove-PSSession -Session $Session -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to remove PSRemoting session: $($_.Exception.Message)"
            }
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name StartSyncCycle -Value {
        <#
        .SYNOPSIS
        Triggers an Entra Connect sync cycle.

        .DESCRIPTION
        Triggers a sync cycle via Start-ADSyncSyncCycle on the remote Entra Connect server.

        .PARAMETER PolicyType
        The sync policy type: 'Delta' or 'Initial'.

        .PARAMETER ComputerName
        Target Entra Connect server hostname for PSRemoting.

        .PARAMETER AuthSession
        Credential ([PSCredential]) provided by the host's AuthSessionBroker.

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
            [ValidateNotNullOrEmpty()]
            [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
            [string] $ComputerName,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $AuthSession
        )

        if ($AuthSession -isnot [pscredential]) {
            $actualType = $AuthSession.GetType().FullName
            throw "AuthSession must be a [PSCredential] for PSRemoting session creation. Received: [$actualType]"
        }

        $remoteSession = $null
        try {
            $remoteSession = $this.NewRemoteSession($ComputerName, $AuthSession)

            $this.InvokeRemoteCommand($remoteSession, {
                param([string] $RemotePolicyType)
                Import-Module -Name ADSync -ErrorAction Stop
                Start-ADSyncSyncCycle -PolicyType $RemotePolicyType -ErrorAction Stop
            }, @($PolicyType)) | Out-Null

            return [pscustomobject]@{
                Started = $true
                Message = "Sync cycle triggered with PolicyType: $PolicyType on $ComputerName"
            }
        }
        catch {
            # Check for common privilege/elevation errors
            $errorMessage = $_.Exception.Message

            if ($errorMessage -match 'access.*denied|permission|privilege|elevation|administrator|unauthorized') {
                throw "Failed to start sync cycle. Missing privileges or elevation. " + `
                    "The AuthSession must provide an elevated execution context. Original error: $errorMessage"
            }

            throw "Failed to start sync cycle: $errorMessage"
        }
        finally {
            $this.RemoveRemoteSession($remoteSession)
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetSyncCycleState -Value {
        <#
        .SYNOPSIS
        Retrieves the current state of Entra Connect sync cycles.

        .DESCRIPTION
        Queries the sync scheduler state via Get-ADSyncScheduler to determine if a
        sync cycle is currently in progress.

        .PARAMETER ComputerName
        Target Entra Connect server hostname for PSRemoting.

        .PARAMETER AuthSession
        Credential ([PSCredential]) provided by the host's AuthSessionBroker.

        .OUTPUTS
        PSCustomObject with properties:
        - InProgress (bool): indicates whether a sync cycle is currently running
        - State (string): 'InProgress', 'Idle', or 'Unknown'
        - Details (hashtable, optional): additional state information
        #>
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ComputerName,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $AuthSession
        )

        if ($AuthSession -isnot [pscredential]) {
            $actualType = $AuthSession.GetType().FullName
            throw "AuthSession must be a [PSCredential] for PSRemoting session creation. Received: [$actualType]"
        }

        $remoteSession = $null
        try {
            $remoteSession = $this.NewRemoteSession($ComputerName, $AuthSession)

            $scheduler = $this.InvokeRemoteCommand($remoteSession, {
                Import-Module -Name ADSync -ErrorAction Stop
                Get-ADSyncScheduler -ErrorAction Stop
            }, @())

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
        finally {
            $this.RemoveRemoteSession($remoteSession)
        }
    } -Force

    return $provider
}
