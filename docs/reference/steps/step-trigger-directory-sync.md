# TriggerDirectorySync

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `TriggerDirectorySync`
- **Implementation**: `Invoke-IdleStepTriggerDirectorySync`
- **Idempotent**: `Unknown`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Triggers a directory sync cycle and optionally waits for completion.

## Description

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements:

- StartSyncCycle(PolicyType, AuthSession)

- GetSyncCycleState(AuthSession)

The step is designed for remote execution and requires an elevated auth session
provided by the host's AuthSessionBroker.

Authentication:

- With.AuthSessionName (required): routing key for AuthSessionBroker

- With.AuthSessionOptions (optional, hashtable): forwarded to broker for session selection

- ScriptBlocks in AuthSessionOptions are rejected (security boundary)

## Inputs (With.*)

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._
