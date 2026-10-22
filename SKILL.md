---
name: building-showroom-labs
description: Use when creating, extending, or verifying a Red Hat Demo Platform (RHDP) Showroom lab or workshop — Antora/AsciiDoc guide modules plus the automation and OpenShift GitOps field-content Helm chart that provision it — especially when guide steps need pass conditions proven on a live OpenShift cluster.
---

# Building Showroom Labs

## Overview

A lab is three things that must agree: the **guide** (Antora pages Showroom renders), the **automation** (`automation/Makefile` + scripts), and the **GitOps chart** RHDP's Field Content CI deploys (`automation/argocd`). Core rule: every step's pass condition was **observed on a real cluster**, never written from memory.

Pattern sources: `taylorjordanNC/rhai-agent-security` (guide structure, evidence style) and `rhpds/field-sourced-content-template` (chart layout, Showroom component).

## Workflow — create a todo per step

1. **Intake.** Ask for whatever is missing: topic and audience; the customer question each module answers; products and pinned versions; tracks and time budget; tenancy (default: dedicated cluster per participant); the test cluster; the public git repo URL Argo CD will sync.
2. **Scaffold.** In a new git repo (Antora reads content only from git): `cp -R <this skill>/assets/scaffold/. .`, then `npm install` once to create the lockfile.
3. **Plan.** Fill `PLAN.md`. If the lab's question is about a direction or path (egress, ingress, a specific API), the plan must exercise that path. Get the user's OK.
4. **Write pages.** Follow `references/page-set.md`. Every `role="execute"` block is followed by `Expected result:` plus a `// UNVERIFIED` line until you have seen the result live.
5. **Automation and GitOps.** Follow `references/automation-gitops.md`.
6. **Local checks.** `npm run build`, then `bash scripts/check-lab.sh --draft`.
7. **Review before deploy.** Run the reviews the user's instructions require (e.g. xreview, ponytail-review) on the lab repo.
8. **Deploy and verify live.** Follow `references/verification.md`. Done when strict `bash scripts/check-lab.sh` passes and a clean re-run succeeds.

## Rules

- Command completion is not proof. `Expected result:` names the field or value seen and what it proves.
- Every allow gets a matching deny; every break gets a restore.
- Behavior checks live in the guide (collapsible scripted assertions) and `automation/verify.sh`. There is no separate test suite.
- Commands are re-runnable (`oc apply`, or `delete --ignore-not-found` before `create`) and name their namespace.
- Images: `repo:tag@sha256:<multi-arch index digest>`, confirmed with `skopeo inspect` or the registry API. No secrets in content.

## Common mistakes (seen without this skill)

| Mistake | Fix |
|---|---|
| Expected output written from memory | `// UNVERIFIED` until observed; strict `check-lab.sh` blocks release |
| Invented `gitops/application.yaml`, Showroom not deployed | Field-content chart; `showroom` child pinned to the upstream chart |
| Terminal tab at `/wetty` | Field-content Showroom serves it at `/terminal` |
| Verified as cluster-admin; participant can't run the steps | Verify from the Showroom terminal; grant its ServiceAccount a minimal Role |
| `ClusterRole edit` for the terminal | Anyone with the URL holds it, and it can bypass the lab's control |
| Bare steps, no why or checkpoint | Module template in `page-set.md` |
| Big test harness for a small lab | Guide assertions + `verify.sh` + `check-lab.sh` |
| Facilitator notes in a README | Rendered `92-facilitator-guide.adoc` |

## Files

- `references/page-set.md`: every page's sections, the module template, AsciiDoc idioms
- `references/automation-gitops.md`: chart layout, terminal identity, Makefile, readiness checks
- `references/verification.md`: test-cluster prep and the live verification pass
- `assets/scaffold/`: the starter repo
