# EmitEvent

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EmitEvent`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEmitEvent`
- **Idempotent**: `Unknown`

## Synopsis

Emits a custom event (demo step).

## Description

This step does not change external state. It emits a custom event message.
The engine provides an EventSink on the execution context that the step can use
to write structured events.

## Inputs (With.*)

This step may not require specific input keys, or they could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'EmitEvent Example'
  Type = 'IdLE.Step.EmitEvent'
  With = @{
    # See step description for available options
  }
}
```
