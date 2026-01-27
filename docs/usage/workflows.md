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

### Template substitution (``{{...}}``)

IdLE supports **template substitution** for embedding request values into workflow step configurations using ``{{...}}`` placeholders. Templates are resolved during planning (plan build), producing a plan with resolved values.

**How it works:**

When you create a lifecycle request, you provide data in the request object (via `DesiredState`, `IdentityKeys`, etc.). Templates in workflow configurations reference these values using dot-notation paths. During plan building, IdLE resolves the templates by looking up the paths in the request object and substituting the actual values.

**Creating a request with values:**

```powershell
$req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
    UserPrincipalName = 'jdoe@example.com'
    DisplayName       = 'John Doe'
    GivenName         = 'John'
    Surname           = 'Doe'
    Department        = 'Engineering'
}
```

The values in `DesiredState` are accessible via `Request.Input.*` (or `Request.DesiredState.*`) in templates.

**Using templates in workflows:**

```powershell
@{
  Name = 'CreateUser'
  Type = 'IdLE.Step.CreateIdentity'
  With = @{
    Attributes = @{
      UserPrincipalName = '`{{Request.Input.UserPrincipalName}}`'
      DisplayName       = '`{{Request.Input.DisplayName}}`'
    }
  }
}
@{
  Name = 'EmitEvent'
  Type = 'IdLE.Step.EmitEvent'
  With = @{
    Message = 'Creating user `{{Request.Input.DisplayName}}` (`{{Request.Input.UserPrincipalName}}`)'
  }
}
```

When the plan is built, templates are resolved to the actual values from the request:
- ``{{Request.Input.UserPrincipalName}}`` → `'jdoe@example.com'`
- ``{{Request.Input.DisplayName}}`` → `'John Doe'`

**Key features:**

- **Concise syntax**: Use ``{{Path}}`` instead of verbose `@{ ValueFrom = 'Path' }` objects
- **Multiple placeholders**: Place multiple templates in one string
- **Nested structures**: Templates work in nested hashtables and arrays
- **Planning-time resolution**: Templates are resolved during plan build, not execution
- **Security boundary**: Only allowlisted request roots are accessible

**Allowed roots:**

For security, template resolution only allows accessing these request properties:

- `Request.Input.*` (aliased to `Request.DesiredState.*` if Input does not exist)
- `Request.DesiredState.*`
- `Request.IdentityKeys.*`
- `Request.Changes.*`
- `Request.LifecycleEvent`
- `Request.CorrelationId`
- `Request.Actor`

Attempting to access other roots (like `Plan.*`, `Providers.*`, or `Workflow.*`) will fail during planning with an actionable error.

**Type handling:**

Templates resolve scalar values (string, numeric, bool, datetime, guid) to strings. Non-scalar values (hashtables, arrays, objects) are rejected with an error. If you need to map complex objects, use explicit mapping steps or host-side pre-flattening.

**Error handling:**

Template resolution fails fast during planning if:

- Path does not exist or resolves to `$null`
- Path uses invalid characters or patterns
- Braces are unbalanced (typo safety)
- Root is not in the allowlist
- Value is non-scalar

These deterministic errors prevent silent substitution bugs (like empty UPNs).

**Escaping:**

Use `\{{` to include literal `{{` in a string:

```powershell
With = @{
  Message = 'Literal \`{{ braces here and template `{{Request.Input.Name}}`'
}
# Resolves to: 'Literal `{{ braces here and template <actual name>'
```

**Request.Input alias:**

Workflow authors can use `Request.Input.*` for consistency, even if the request object only provides `DesiredState`. IdLE automatically aliases `Request.Input.*` to `Request.DesiredState.*` when the `Input` property does not exist.

### Legacy reference syntax (ValueFrom)

Prefer explicit reference fields over implicit parsing:

- `Value` for literals
- `ValueFrom` for references (for example: `Request.EmployeeId`)
- `ValueDefault` for fallback literals

This makes configurations safe and statically validatable.

**Note:** Template substitution (``{{...}}``) is preferred for string fields. Use `ValueFrom` objects when you need non-string references or conditional defaults.

## Advanced Workflow Patterns

(Content for advanced patterns will be added in future updates)

This approach keeps workflows data-only while allowing rich message formatting in the host code.

## Related

- [Steps](steps.md)
- [Providers](providers.md)
