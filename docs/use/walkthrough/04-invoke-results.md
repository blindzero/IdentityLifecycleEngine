---
title: Walkthrough 4 - Invoke and results
sidebar_label: "4. Invoke and results"
---

This page covers the fourth stage in the IdLE lifecycle:

**Workflow → Request → Plan → Invoke → Providers/Auth**

When you invoke a plan, IdLE executes the steps in order and emits structured events.

---

## Goal

Execute the plan and inspect result data (status, step outcomes, events).

## You will have

- An invocation result object
- A basic understanding of where to look for success/failure and messages

---

## 1) Invoke the plan

If you supplied providers during plan build, invocation is simple:

```powershell
$result = Invoke-IdlePlan -Plan $plan
```

If you did **not** supply providers during plan build, you can supply them at execution time:

```powershell
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## 2) Inspect status and step outcomes

```powershell
$result.Status

$result.Steps | Select-Object Name, Status, StartedUtc, FinishedUtc
```

---

## 3) Inspect events

IdLE produces structured events that you can log, forward, or store.

```powershell
$result.Events | Select-Object Type, StepName, Message
```

---

## 4) If something fails

Typical first-time failure causes:

- StepType not imported / wrong `Type` name in the workflow
- Provider alias referenced by a step is missing in `$providers`
- Template paths resolve to null (missing request data)

Use the step results and event messages to locate the failing step quickly.

---

## Next

Continue with [**Walkthrough 5: Providers and authentication**](05-providers-authentication.md).
