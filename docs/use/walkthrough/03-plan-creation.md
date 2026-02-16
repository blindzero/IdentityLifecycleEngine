---
title: Walkthrough 3 - Plan build
sidebar_label: "3. Plan build"
---

This page covers the third artifact in the IdLE lifecycle:

**Workflow → Request → Plan → Invoke → Providers/Auth**

A **plan** is the validated, resolved execution contract created from a workflow and a request.
Plan building is designed to be **fail-fast**.

---

## Goal

Build a plan from your workflow and request, while supplying providers (recommended).

## You will have

- A plan object that is safe to review and execute
- Templates resolved (for example `{{Request.DesiredState.GivenName}}`)
- Validation errors surfaced early (before execution)

---

## Prerequisites

- A workflow file `joiner.psd1` from Walkthrough 1
- A request object from Walkthrough 2
- Providers supplied by your host (Walkthrough 5 explains the patterns in detail)

For this walkthrough we use the mock provider:

```powershell
Import-Module -Name IdLE
Import-Module -Name IdLE.Provider.Mock

$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

---

## 1) Build the plan

```powershell
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request -Providers $providers
```

---

## 2) What happens during plan build

During plan build IdLE typically:

- loads the workflow definition
- validates the workflow structure and step types
- validates that referenced providers exist (when supplied)
- checks required capabilities (provider/step contracts)
- resolves template expressions (for example `{{Request.DesiredState.GivenName}}`)
- produces a deterministic execution plan

:::info
Supplying providers during plan build is recommended because it enables **fail-fast** validation.
If you plan to export and execute in another environment, you may supply providers at execution time.
:::

---

## 3) Optional: Export the plan for review

Plan export is useful when you want to:

- review or approve a plan before execution
- publish the plan as a CI artifact
- retain an audit-friendly contract

See [Plan Export](../plan-export.md).

---

## Next

Continue with [**Walkthrough 4: Invoke and results**](04-invoke-results.md).
