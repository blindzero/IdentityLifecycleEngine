# EmitEvent

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EmitEvent`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEmitEvent`
- **Idempotent**: `Unknown`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Emits a custom event (demo step).

## Description

This step does not change external state. It emits a custom event message.
The engine provides an EventSink on the execution context that the step can use
to write structured events.

## Inputs (With.*)

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._
