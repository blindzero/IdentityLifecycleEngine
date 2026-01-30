---
title: Workflows & Steps
sidebar_label: Workflows / Steps
---

# Workflows & Steps

Workflows are **data-only** configuration files (PSD1) describing which steps should run for a lifecycle event.

A step is a self-contained unit of work executed as part of a plan.<br/>
A step:

- performs a single, well-defined responsibility
- operates on the execution context provided by the engine
- may interact with external systems through providers
- reports its outcome through status and events
- does _not_ orchestrate other steps and do _not_ control execution flow beyond their own outcome.

## Workflow File Format

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

#### Name

The identifying name of your workflow

```yaml
Type: String
Required: True
```

#### LifecycleEvent

The type of the lifecycle event described by your workflow.

```yaml
Type: String
Required: True
Options: Joiner, Mover, Leaver
```

#### Steps

An Array of step objects, each a Hashtable.

```yaml
Type: Array
Required: True
```

## Steps

Each step represents a distinct action that is performed, based on data defined in the workflow parameters or that are passed by the host's request object and merges with the workflow definition on the plan.

Steps are represented by PowerShell Hashtable objects.

### Step Types

Step types are treated as **contracts**. Prefer fully-qualified ids (module + step name), for example: `IdLE.Step.EmitEvent`.
Each step type's implementation is made available via a step registry.
Additionally, each step type's implementation defines required capabilities for this step.
Later, provider implementations are providing these capabilities for the steps.
If a provider selected for a step has not the capabilities available required by the step type, the plan of the workflow with fail.

For a list of available Step Types please see the [Step Type Catalog](../reference/steps.md).

Additionally, you can provide your own custom [extend with custom steps](../extend/steps.md).

### Conditional steps

Steps can be skipped using declarative `Condition` key.

Example:

```powershell
@{
    Name           = 'Joiner - Condition Demo'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'EmitOnlyForJoiner'
            Type = 'IdLE.Step.EmitEvent'
            Condition = @{
                Equals = @{
                    Path   = 'Plan.LifecycleEvent'
                    Value  = 'Joiner'
                }
            }
            With = @{
                Message = 'This step runs only if Plan.LifecycleEvent == Joiner.'
            }
        }
    )
}
```

If the condition is not met, the step is marked as `Skipped` and a skip event is emitted.

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
        @{
            Name = 'CreateAccount';
            Type = 'IdLE.Step.CreateAccount'
        }
        @{
            Name = 'EnsureEntitlement';
            Type = 'IdLE.Step.EnsureEntitlement'
        }
    )

    OnFailureSteps = @(
        @{
            Name = 'RollbackAccount';
            Type = 'IdLE.Step.DeleteAccount'
        }
        @{
            Name = 'LogFailure';
            Type = 'IdLE.Step.EmitEvent';
            With = @{
                Message = 'Joiner Failed - Rollback performed'
            }
        }
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
$result.OnFailure.Steps       # Array of OnFailure step results
```

## References and inputs

### Template substitution (double curly braces)

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
      UserPrincipalName = '{{Request.Input.UserPrincipalName}}'
      DisplayName       = '{{Request.Input.DisplayName}}'
    }
  }
}
@{
  Name = 'EmitEvent'
  Type = 'IdLE.Step.EmitEvent'
  With = @{
    Message = 'Creating user {{Request.Input.DisplayName}} ({{Request.Input.UserPrincipalName}})'
  }
}
```

When the plan is built, templates are resolved to the actual values from the request:
- `{{Request.Input.UserPrincipalName}}` → `'jdoe@example.com'`
- `{{Request.Input.DisplayName}}` → `'John Doe'`

**Key features:**

- **Concise syntax**: Use ``{{Path}}`` instead of verbose `@{ ValueFrom = 'Path' }` objects
- **Multiple placeholders**: Place multiple templates in one string
- **Nested structures**: Templates work in nested hashtables and arrays
- **Planning-time resolution**: Templates are resolved during plan build, not execution
- **Security boundary**: Only allowlisted request roots are accessible

**Allowed references:**

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
  Message = 'Literal \{{ braces here and template {{Request.Input.Name}}'
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

:::note

Template substitution (`{{...}}`) is preferred for string fields. Use `ValueFrom` objects when you need non-string references or conditional defaults.

:::

---

## Workflow validation

Workflows are validated during planning.

Typical validation rules:

- unknown keys are errors
- required keys must exist
- condition schemas must be valid
- `*From` paths must reference allowed roots
