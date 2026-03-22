---
title: Walkthrough 1 - Workflow definition
sidebar_label: "1. Workflow definition"
---

In this walkthrough series, you build a complete IdLE run step by step:

**Workflow → Request → Plan → Invoke → Providers/Auth**

This page focuses on the first artifact: the **workflow definition**.

:::info
Workflows are **data-only** (`.psd1`). They describe *what* to do, not *how* to authenticate or connect.
Providers and authentication are supplied by your host.
:::

---

## Goal

**Create a minimal workflow** file that IdLE can validate and turn into a plan.

## You will have

- A workflow file on disk: `joiner.psd1`
- A workflow with one safe step (`IdLE.Step.EmitEvent`) and one provider-backed step (`IdLE.Step.EnsureAttributes`)

---

## 1) Create a minimal workflow file

Create a file `joiner.psd1` with this content:

```powershell
@{
  Name           = 'Walkthrough - Joiner (Minimal)'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Starting Joiner workflow (Walkthrough)'
      }
    }

    @{
      Name = 'Ensure demo attributes'
      Type = 'IdLE.Step.EnsureAttributes'
      With = @{
        Provider    = 'Identity'
        IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
        Attributes  = @{
          GivenName = '{{Request.Intent.GivenName}}'
          Surname   = '{{Request.Intent.Surname}}'
        }
      }
    }
  )
}
```

:::warning
Do not embed executable code (ScriptBlocks) and do not store secrets in workflow files.
Workflows are treated as **untrusted input** and must remain **data-only**.
:::

---

## 2) What the workflow describes

- `LifecycleEvent` ties the workflow to a request intent (Joiner/Mover/Leaver).
- `Steps` is an ordered list.
- Each step references a **StepType** by name (`Type`).
- Step configuration lives under `With`.
- Template expressions like `{{Request.Intent.GivenName}}` are resolved when building the plan.

---

## Next

Continue with [**Walkthrough 2: Request creation**](02-request-creation.md).
