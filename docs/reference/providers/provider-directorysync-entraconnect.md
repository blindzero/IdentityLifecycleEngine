---
title: Provider Reference - IdLE.Provider.DirectorySync.EntraConnect
sidebar_label: DirectorySync.EntraConnect
---

> **Purpose:** This page is a **reference** for a specific provider implementation.
> Keep it factual and contract-oriented. Put conceptual explanations elsewhere and link to them.

---

## Summary

- **Provider name:** EntraConnect DirectorySync
- **Module:** `IdLE.Provider.DirectorySync.EntraConnect`
- **Provider kind:** Other
- **Targets:** Entra ID Connect (ADSync) sync scheduler on a Windows server (remote execution)
- **Status:** First-party (bundled)
- **Since:** 0.9.0
- **Compatibility:** PowerShell 7+ (IdLE requirement)

---

## What this provider does

- **Primary responsibilities:**
  - Trigger an Entra Connect sync cycle (`Delta` or `Initial`).
  - Query sync cycle state (whether a cycle is in progress).
- **Out of scope / non-goals:**
  - Establishing remote connectivity, authentication, or elevation (handled by the host/broker).
  - Installing or configuring Entra Connect / ADSync.

---

## Contracts and capabilities

### Contracts implemented

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| Directory sync provider (implicit) | Trigger and monitor directory sync cycles | Exposes `StartSyncCycle(PolicyType, AuthSession)` and `GetSyncCycleState(AuthSession)` as script methods. |

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: Yes
- **Capabilities returned (stable identifiers):**
  - `IdLE.DirectorySync.Trigger`
  - `IdLE.DirectorySync.Status`

---

## Authentication and session acquisition

> Providers must not prompt for auth. Use the host-provided broker contract.

This provider expects a host-provided **AuthSession** object that implements:

- `InvokeCommand(CommandName, Parameters)`

The provider does not call `Context.AcquireAuthSession(...)` directly; IdLE steps acquire an auth session
and pass it to provider methods.

- **Auth session name(s) used by built-in steps:**
  - `DirectorySync` (see `IdLE.Step.TriggerDirectorySync`)
- **Session options (data-only):**
  - Forwarded to the host broker for session selection (provider does not interpret option keys).

:::warning

**Security notes**

- Do not pass secrets in provider options.
- Ensure token/credential objects are not emitted in events.

:::

### Auth examples

**A) Simple WinRM/PowerShell Remoting wrapper (typical)**

The provider expects an auth session object with an `InvokeCommand(CommandName, Parameters)` method.
Your host can wrap `Invoke-Command` like this:

```powershell
$syncCred = Get-Credential -Message 'Enter credentials for Entra Connect server'

$authSession = [pscustomobject]@{
  ComputerName = 'entra-connect-01.contoso.local'
  Credential   = $syncCred
}
$authSession | Add-Member -MemberType ScriptMethod -Name InvokeCommand -Value {
  param([string] $CommandName, [hashtable] $Parameters)

  Invoke-Command -ComputerName $this.ComputerName -Credential $this.Credential -ScriptBlock {
    param($cmd, $params)
    & $cmd @params
  } -ArgumentList $CommandName, $Parameters
}

$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
  param($Name, $Options)
  return $authSession
}

$providers = @{
  DirectorySync     = New-IdleEntraConnectDirectorySyncProvider
  AuthSessionBroker = $broker
}

# Steps use With.AuthSessionName = 'DirectorySync'
```

**B) Role-based routing (Tier0 vs. Admin)**

```powershell
$tier0 = New-EntraConnectAuthSession -ComputerName 'entra-connect-01' -Credential (Get-Credential)
$admin = New-EntraConnectAuthSession -ComputerName 'entra-connect-01' -Credential (Get-Credential)

$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
  param($Name, $Options)
  if ($Options.Role -eq 'Tier0') { return $tier0 }
  return $admin
}
```

> Note: if `Start-ADSyncSyncCycle` requires elevation on your server, handle that in the host
> (scheduled task, JEA endpoint, endpoint configuration), not inside the provider.

---

## Configuration

### Provider constructor / factory

- **Public constructor cmdlet(s):**
  - `New-IdleEntraConnectDirectorySyncProvider` — Creates a provider instance.

> Do not copy full comment-based help here. Link to the cmdlet reference.

### Provider bag / alias usage

```powershell
$providers = @{
  DirectorySync = New-IdleEntraConnectDirectorySyncProvider
}
```

- **Recommended alias pattern:** `DirectorySync`
- **Default alias expected by built-in steps (if any):** `DirectorySync` (used by `IdLE.Step.TriggerDirectorySync`)

---

## Provider-specific options reference

This provider has **no provider-specific option bag**. Runtime behavior depends on the host-provided AuthSession.

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** Partial (triggering a sync cycle is an action; the step may optionally wait for completion)
- **Consistency model:** Depends on the directory synchronization runtime
- **Concurrency notes:**
  - Triggering a new cycle may fail if a cycle is already in progress.

### Error mapping and retry behavior

- **Common error categories:** `PermissionDenied/ElevationRequired`, `Throttled/Busy`, `RemoteExecutionFailed`
- **Retry strategy:** None in the provider; any retries/backoff should be handled by the host or by the calling step.

---

## Observability

- **Events emitted by provider (if any):** None
- **Sensitive data redaction:** Enforced by IdLE output-boundary redaction; hosts should ensure the AuthSession does not leak secrets.

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = New-IdleEntraConnectDirectorySyncProvider

# 2) Build provider map
$providers = @{
  DirectorySync = $provider
  AuthSessionBroker = $broker # host-provided
}

# 3) Plan + execute
$plan = New-IdlePlan -WorkflowPath .\workflow.psd1 -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Example workflow snippet

```powershell
@{
  Steps = @(
    @{
      Name = 'Trigger directory sync'
      Type = 'IdLE.Step.TriggerDirectorySync'
      With = @{
        Provider        = 'DirectorySync'
        AuthSessionName = 'DirectorySync'
        PolicyType      = 'Delta'
        Wait            = $true
        TimeoutSeconds  = 600
        PollIntervalSeconds = 10
      }
    }
  )
}
```

---

## Limitations and known issues

- Requires an elevated remote execution context on the Entra Connect server.
- The remote target must have the ADSync cmdlets available (`Start-ADSyncSyncCycle`, `Get-ADSyncScheduler`).
