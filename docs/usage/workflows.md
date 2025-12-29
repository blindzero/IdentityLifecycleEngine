# IdentityLifecycleEngine (IdLE) - Workflows

Workflows are **data-only** configuration files (PSD1) describing which steps should run for a lifecycle event.

## Format

A workflow is a PowerShell hashtable stored as `.psd1`:

```powershell
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name   = 'Emit:Start'
      Step   = 'EmitEvent'
      Inputs = @{ Message = 'Starting Joiner' }
    }
  )
}
```

## Planning and validation

Workflows are validated during planning.

Typical validation rules:

- unknown keys are errors
- required keys must exist
- condition schemas must be valid
- `*From` paths must reference allowed roots

## Conditional steps

Steps can be skipped using declarative `When` conditions.

Example:

```powershell
When = @{
  Path   = 'Plan.LifecycleEvent'
  Equals = 'Joiner'
}
```

If the condition is not met, the step is marked as `Skipped` and a skip event is emitted.

## References and inputs

Prefer explicit reference fields over implicit parsing:

- `Value` for literals
- `ValueFrom` for references (for example: `Request.EmployeeId`)
- `ValueDefault` for fallback literals

This makes configurations safe and statically validatable.

## Related

- [Steps](steps.md)
- [Providers](providers.md)
