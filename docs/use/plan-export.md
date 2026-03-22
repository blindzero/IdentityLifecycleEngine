---
title: Plan Export
sidebar_label: Plan Export
---

Plan export provides a **reproducible, machine-readable representation** of what IdLE intends to execute.

---

## Why export a plan?

Plan export is useful to:

- review and approve a plan before execution (four-eyes principle)
- persist evidence for audit and incident investigations
- compare planned actions over time (for example: template/default changes)
- integrate IdLE planning into CI pipelines (validate workflows without executing them)

---

## Export a plan

```powershell
$request = New-IdleRequest -LifecycleEvent 'Joiner' -CorrelationId (New-Guid) -Actor 'HR-System' -IdentityKeys @{
    EmployeeId = '12345'
} -Intent @{
    Department = 'IT'
}

$plan = New-IdlePlan -WorkflowPath ./workflows/joiner.psd1 -Request $request

Export-IdlePlan -Plan $plan -Path ./artifacts/plan.json
```

## What a plan export contains

A plan export typically includes:

- metadata about the exported plan (name, workflow, timestamps)
- the planned step list in execution order
- step configuration after template resolution (as applicable)
- provider alias references (but **not** live provider objects)
- capability information (if available)

:::info
A plan export is an **execution contract**. It is designed to be reviewed and approved before it runs.
Providers and authentication are always supplied by the host at execution time.
:::

---

## Example export

```json
{
    "schemaVersion": "1.0",
    "engine": {
        "name": "IdLE"
    },
    "request": {
        "type": "Joiner",
        "correlationId": "123e4567-e89b-12d3-a456-426614174000",
        "actor": "HR-System",
        "input": {
            "identityKeys": {
                "EmployeeId": "12345"
            },
            "intent": {
                "Department": "IT"
            },
            "context": {}
        }
    },
    "plan": {
        "id": "123e4567-e89b-12d3-a456-426614174000",
        "mode": null,
        "steps": [
            {
                "id": "step-01",
                "name": "Ensure Mailbox",
                "stepType": "IdLE.Step.Mailbox.EnsureMailbox",
                "provider": "ExchangeOnline",
                "condition": {
                    "type": "always",
                    "expression": null
                },
                "inputs": {
                    "mailboxType": "User"
                },
                "expectedState": null,
                "warnings": []
            }
        ],
        "warnings": []
    },
    "metadata": {
        "generatedBy": "Export-IdlePlanObject",
        "environment": null,
        "labels": []
    }
}
```

In this example, `metadata.environment` is `null` and `metadata.labels` is an empty array because
`Export-IdlePlanObject` does not infer or populate these fields automatically. They are part of the
exported contract so that your host or automation (for example, a CI pipeline or runbook) can add
environment information and labels (such as change ticket IDs, deployment rings, or business tags)
as needed before storing or executing the plan.
See the full JSON contract in [plan-export reference](../reference/specs/plan-export.md).

---

## Typical flow (review gate)

1. Build a plan in a controlled environment (CI / staging).
2. Export the plan as an artifact for review/approval.
3. Execute the approved plan in the target environment (prod), supplying providers and auth.

This matches the IdLE separation of concerns: workflows/requests are data-only; providers/auth are host responsibilities.
