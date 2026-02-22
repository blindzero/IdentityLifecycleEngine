---
title: Walkthrough 2 - Request creation
sidebar_label: "2. Request creation"
---

This page covers the second artifact in the IdLE lifecycle:

**Workflow → Request → Plan → Invoke → Providers/Auth**

A **request** represents business intent (Joiner/Mover/Leaver) plus the input data used by workflows (identity keys, desired state, and optional context).

---

## Goal

Create a minimal request that matches the workflow from [Walkthrough 1](01-workflow-definition.md).

## You will have

- A request object that contains:
  - `LifecycleEvent`
  - `IdentityKeys.EmployeeId`
  - `Intent.GivenName` and `Intent.Surname`

---

## 1) Create the request

In PowerShell, create the request like this:

```powershell
$request = New-IdleRequest -LifecycleEvent 'Joiner' -IdentityKeys @{
  EmployeeId = '12345'
} -Intent @{
  GivenName = 'Max'
  Surname   = 'Power'
}
```

This request provides the values referenced in the workflow templates:

- `{{Request.IdentityKeys.EmployeeId}}`
- `{{Request.Intent.GivenName}}`
- `{{Request.Intent.Surname}}`

---

## 2) What belongs into a request

### IdentityKeys
Identity keys uniquely identify the identity you are acting on (for example: EmployeeId, SamAccountName, UPN).

Identity keys are typically:

- stable
- unique
- provided by the upstream system (HR, IAM, ticket)

### Intent
Intent contains the caller-provided action inputs (attributes, entitlements, mailbox settings, …) that the workflow should act on.

For this walkthrough we keep it minimal and only set two attributes.

:::info
Requests are **data-only**.
Do not embed executable code (ScriptBlocks) and do not store secrets in requests.
:::

---

## Next

Continue with [**Walkthrough 3: Plan build**](03-plan-creation.md).
