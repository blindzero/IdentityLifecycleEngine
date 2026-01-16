# Domain model: LifecycleRequest
# Actor is intentionally optional in V1 (see architecture).
# Changes is optional and stays $null if not provided (intent-only requests typically only provide DesiredState).

class IdleLifecycleRequest {
    [string] $LifecycleEvent
    [hashtable] $IdentityKeys
    [hashtable] $DesiredState
    [hashtable] $Changes
    [string] $CorrelationId
    [string] $Actor

    IdleLifecycleRequest(
        [string] $lifecycleEvent,
        [hashtable] $identityKeys,
        [hashtable] $desiredState,
        [hashtable] $changes,
        [string] $correlationId,
        [string] $actor
    ) {
        $this.LifecycleEvent = $lifecycleEvent
        $this.IdentityKeys = $identityKeys
        $this.DesiredState = $desiredState
        $this.Changes = $changes
        $this.CorrelationId = $correlationId
        $this.Actor = $actor

        $this.Normalize()
    }

    [void] Normalize() {
        if ([string]::IsNullOrWhiteSpace($this.LifecycleEvent)) {
            throw [System.ArgumentException]::new('LifecycleEvent must not be empty.', 'LifecycleEvent')
        }

        if ($null -eq $this.IdentityKeys) {
            $this.IdentityKeys = @{}
        }

        if ($null -eq $this.DesiredState) {
            $this.DesiredState = @{}
        }

        # Changes stays $null if not provided. If provided, it must be a hashtable.
        if ($null -ne $this.Changes -and $this.Changes -isnot [hashtable]) {
            throw [System.ArgumentException]::new('Changes must be a hashtable when provided.', 'Changes')
        }

        if ([string]::IsNullOrWhiteSpace($this.CorrelationId)) {
            $this.CorrelationId = [guid]::NewGuid().Guid
        }

        # Actor is optional; normalize whitespace to $null for consistency.
        if ([string]::IsNullOrWhiteSpace($this.Actor)) {
            $this.Actor = $null
        }
    }
}
