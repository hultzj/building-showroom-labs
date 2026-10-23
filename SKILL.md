---
name: building-showroom-labs
description: Use when creating, extending, or verifying a Red Hat Demo Platform (RHDP) Showroom lab or workshop that runs on OpenShift — on an RHDP order or a pre-existing cluster, dedicated or shared — covering the Antora/AsciiDoc guide, the automation and the OpenShift GitOps chart, especially when guide steps need pass conditions proven on a live cluster.
---

# Building Showroom Labs

## Overview

A lab is three things that must agree: the **guide** (Antora pages Showroom renders), the **automation** (`automation/Makefile` + scripts), and the **GitOps chart** (`automation/argocd`, the RHDP field-content layout). Core rule: every step's pass condition was **observed on a real cluster as the participant**, never written from memory.

## Workflow — create a todo per step

1. **Intake.** Ask for whatever is missing: topic and audience; the customer question each module answers; products and pinned versions; tracks and time budget; the test cluster; the public git repo URL Argo CD will sync. Then settle the environment with `references/environments.md`: RHDP order or pre-existing cluster, GitOps-built or participant-built, dedicated (the default) or shared. That fixes the participant identity.
2. **Scaffold.** In a new git repo (Antora reads content only from git): `cp -R <this skill>/assets/scaffold/. .`, then `npm install`.
3. **Plan.** Fill `PLAN.md`. If the lab's question names a path (egress, an API, another tenant), the plan exercises that path. Get the user's OK.
4. **Write pages.** Follow `references/page-set.md`. Every exercise and every `role="execute"` block gets `Expected result:` plus `// UNVERIFIED` until you have seen the result live.
5. **Automation and GitOps.** Follow `references/automation-gitops.md`.
6. **Local checks.** `npm run build`, then `bash scripts/check-lab.sh --draft`.
7. **Review before deploy.** Run the reviews the user's instructions require (e.g. xreview, ponytail-review). If the RHDP marketplace's `showroom:verify-content` skill is installed, run it too for Red Hat style and accessibility.
8. **Deploy and verify live.** Follow `references/verification.md`. Done when strict `bash scripts/check-lab.sh` passes and a clean re-run succeeds.

## Rules

- `Expected result:` names the field or value seen and what it proves. Command completion is not proof.
- Every allow gets a deny that asserts the specific failure (exit code, error, event); every break gets a restore.
- Behavior checks live in the guide (collapsible assertions) and `automation/verify.sh`. There is no separate test suite.
- Commands are re-runnable (`oc apply`, or `delete --ignore-not-found` before `create`) and name their namespace.
- Lab-owned images: `repo:tag@sha256:<index digest>`. No secrets in content; examples use `example.com` and `192.0.2.x`.

## Common mistakes (seen without this skill)

| Mistake | Fix |
|---|---|
| Expected results written from memory | `// UNVERIFIED` until observed; strict `check-lab.sh` blocks release |
| Invented GitOps layout, no Showroom, terminal at `/wetty` | Field-content chart; pinned upstream Showroom child; terminal at `/terminal` |
| Verified as cluster-admin | Verify as the participant: terminal ServiceAccount, or a real non-admin user |
| Terminal ServiceAccount given `edit`, operator-install, or cross-tenant rights | Anyone with the Showroom URL holds them; cluster-scoped or shared labs use the participant's own login, terminal off |
| Cross-user denial that depends on a peer's progress | A GitOps-deployed decoy tenant |
| GUI step without Expected result, labels from memory | Numbered clicks with labels seen live (Playwright), then a CLI read-back |
| `oc wait` on a CR before its operator's CRD exists | Wait chain: CSV Succeeded → CR exists → Ready |
| Bare steps, no why or checkpoint; facilitator notes in a README | Module template and page set in `page-set.md` |
| Big test harness for a small lab | Guide assertions + `verify.sh` + `check-lab.sh` |

## Files

- `references/environments.md`: RHDP vs pre-existing cluster, participant-built stacks and operators, shared tenancy, participant identity
- `references/page-set.md`: page sections, the module template, GUI steps, AsciiDoc idioms
- `references/automation-gitops.md`: chart layout, terminal identity, Makefile, `verify.sh`
- `references/verification.md`: test-cluster prep and the live pass
- `assets/scaffold/`: the starter repo
