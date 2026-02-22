# Domain model: LifecycleRequest
# Actor is intentionally optional in V1 (see architecture).
#
# Intent   - canonical caller-provided input block.
# Context  - read-only associated context provided by the host or resolvers.

class IdleLifecycleRequest {
    [string] $LifecycleEvent
    [hashtable] $IdentityKeys
    [hashtable] $Intent
    [hashtable] $Context
    [string] $CorrelationId
    [string] $Actor

    IdleLifecycleRequest(
        [string] $lifecycleEvent,
        [hashtable] $identityKeys,
        [hashtable] $intent,
        [hashtable] $context,
        [string] $correlationId,
        [string] $actor
    ) {
        $this.LifecycleEvent = $lifecycleEvent
        $this.IdentityKeys = $identityKeys
        $this.Intent = $intent
        $this.Context = $context
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

        if ($null -eq $this.Intent) {
            $this.Intent = @{}
        }

        if ($null -eq $this.Context) {
            $this.Context = @{}
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
