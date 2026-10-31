# IdLE.Step.EmitEvent

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.EmitEvent`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEmitEvent`
- **Idempotent**: `Unknown`

## Synopsis

Emits a workflow-defined event.

## Description

This step does not change external state. It writes one structured event to the
EventSink on the execution context (buffered in the execution result and forwarded
to the host event sink, if any).

Inputs (all optional):

- With.Message: event message. Defaults to "Event emitted by step '&lt;Name&gt;'.".

- With.Type: event type, e.g. 'Contoso.Joiner.Notified'. Must not start with 'IdLE.'
  (reserved) and must not be 'Information', 'Warning', 'Error' or 'Custom'.
  Defaults to 'IdLE.Step.EmitEvent.Emitted'.

- With.Level: 'Information' (default), 'Warning' or 'Error'.

## Inputs (With.*)

This step has no required ``With.*`` keys at step schema level.
Inputs may still be provider-specific; refer to the step description and examples for usage details.

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
