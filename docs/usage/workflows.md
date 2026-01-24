# Workflows

Workflows are **data-only** configuration files (PSD1) describing which steps should run for a lifecycle event.

## Format

A workflow is a PowerShell hashtable stored as `.psd1`.

Workflow definitions are **data-only**. Do not embed executable code.

Example:

```powershell
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Starting Joiner' }
    }
  )
}
```

### OnFailureSteps (optional)

Workflows can define cleanup or rollback steps that run when primary steps fail.
OnFailureSteps are executed in **best-effort mode**:

- They run only if at least one primary step fails
- Each OnFailure step is attempted regardless of previous OnFailure step failures
- OnFailure step failures do not stop execution of remaining OnFailure steps
- The overall execution status remains 'Failed' even if all OnFailure steps succeed

Example:

```powershell
@{
  Name           = 'Joiner - With Cleanup'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{ Name = 'CreateAccount'; Type = 'IdLE.Step.CreateAccount' }
    @{ Name = 'AssignLicense'; Type = 'IdLE.Step.AssignLicense' }
  )

  OnFailureSteps = @(
    @{ Name = 'NotifyAdmin';      Type = 'IdLE.Step.SendEmail'; With = @{ Recipient = 'admin@example.com' } }
    @{ Name = 'RollbackAccount';  Type = 'IdLE.Step.DeleteAccount' }
    @{ Name = 'LogFailure';       Type = 'IdLE.Step.LogToDatabase' }
  )
}
```

**Best practices:**

- Use OnFailureSteps for notifications, logging, or rollback operations
- Keep OnFailure steps simple and resilient
- Avoid dependencies between OnFailure steps
- Don't assume OnFailure steps will always succeed

**Execution result:**

The execution result includes a separate `OnFailure` section:

```powershell
$result.OnFailure.Status      # 'NotRun', 'Completed', or 'PartiallyFailed'
$result.OnFailure.Steps        # Array of OnFailure step results
```

## Planning and validation

Workflows are validated during planning.

Typical validation rules:

- unknown keys are errors
- required keys must exist
- condition schemas must be valid
- `*From` paths must reference allowed roots

## Step identifiers

Step types are treated as **contracts**. Prefer fully-qualified ids (module + step name),
for example: `IdLE.Step.EmitEvent`.

The host maps step types to step implementations via a step registry.

## Conditional steps

Steps can be skipped using declarative `Condition` key.

Example:

```powershell
Condition = @{
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

## Advanced Workflow Patterns

(Content for advanced patterns will be added in future updates)

This approach keeps workflows data-only while allowing rich message formatting in the host code.

## Related

- [Steps](steps.md)
- [Providers](providers.md)
