# IdLE.Step.EmitEvent

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.EmitEvent`
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

The required input keys could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'IdLE.Step.EmitEvent Example'
  Type = 'IdLE.Step.EmitEvent'
  With = @{
    # See step description for available options
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations
