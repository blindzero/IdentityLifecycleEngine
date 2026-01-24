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

### Template Substitution in Workflow Configs

IdLE supports **template substitution** using `{{...}}` syntax in string values within workflow configurations. This allows dynamic values from the lifecycle request to be inserted during plan building.

**Syntax:**
```powershell
'{{Request.Input.PropertyName}}'
```

**Example - Simple substitution:**
```powershell
@{
    Name = 'Create user account'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        Provider    = 'Identity'
        IdentityKey = '{{Request.Input.UserPrincipalName}}'
        DisplayName = '{{Request.Input.DisplayName}}'
    }
}
```

**Example - Out of Office message with substitution:**
```powershell
@{
    Name = 'Enable Out of Office'
    Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = '{{Request.Input.UserPrincipalName}}'
        Config      = @{
            Mode            = 'Enabled'
            InternalMessage = '{{Request.Input.DisplayName}} is no longer with the organization. For assistance, please contact {{Request.Input.ManagerEmail}}.'
            ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
        }
    }
}
```

**How Request.Input is populated:**

The host creates the lifecycle request and provides the Input hashtable:

```powershell
$request = New-IdleLifecycleRequest `
    -LifecycleEvent 'Leaver' `
    -IdentityKeys @{ UserPrincipalName = 'john.doe@contoso.com' } `
    -Input @{
        UserPrincipalName = 'john.doe@contoso.com'
        DisplayName       = 'John Doe'
        ManagerEmail      = 'jane.smith@contoso.com'
        Department        = 'Engineering'
    }
```

Template substitution happens during `New-IdlePlan`, replacing `{{...}}` with actual values from the request.

**Limitations for formatted messages:**

- **Single-line only**: Multi-line strings with line breaks are not supported in workflow configs due to the data-only constraint
- **No script expressions**: Cannot use `@"..."@` or script blocks for string formatting
- **Simple substitution only**: Only `{{Path.To.Value}}` syntax is supported, no formatting options

**For complex message formatting:**

If you need multi-line messages or complex formatting:

1. **External templates**: Store message templates in separate files and reference them by name, with the host loading and formatting them before creating the request
2. **Pre-formatted in Input**: Format the complete message in the host code and pass it as a single Input parameter
3. **Step-level formatting**: Create a custom step that handles message formatting logic

**Example - Pre-formatted message approach:**
```powershell
# Host code
$oofMessage = @"
$displayName is no longer with the organization.

For assistance, please contact:
- Manager: $managerEmail
- HR: hr@contoso.com
- IT Support: it@contoso.com
"@

$request = New-IdleLifecycleRequest `
    -LifecycleEvent 'Leaver' `
    -Input @{
        UserPrincipalName = 'john.doe@contoso.com'
        OOFInternalMessage = $oofMessage
    }
```

```powershell
# Workflow
@{
    Name = 'Enable Out of Office'
    Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = '{{Request.Input.UserPrincipalName}}'
        Config      = @{
            Mode            = 'Enabled'
            InternalMessage = '{{Request.Input.OOFInternalMessage}}'
            ExternalMessage = '{{Request.Input.OOFExternalMessage}}'
        }
    }
}
```

This approach keeps workflows data-only while allowing rich message formatting in the host code.

## Related

- [Steps](steps.md)
- [Providers](providers.md)
