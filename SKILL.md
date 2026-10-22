---
name: building-showroom-labs
description: Use when creating, extending, or verifying a Red Hat Demo Platform (RHDP) Showroom lab or workshop — Antora/AsciiDoc guide modules plus the automation and OpenShift GitOps field-content Helm chart that provision it — especially when guide steps need pass conditions proven on a live OpenShift cluster.
---

# Building Showroom Labs

## Overview

A lab is three things that must agree: the **guide** (Antora pages Showroom renders), the **automation** (`automation/Makefile` + scripts), and the **GitOps chart** RHDP's Field Content CI deploys (`automation/argocd`). The core rule: every step's pass condition was **observed on a real cluster**, never written from memory.

Pattern sources: `taylorjordanNC/rhai-agent-security` (guide structure, evidence style) and `rhpds/field-sourced-content-template` (chart layout, Showroom component).

## Workflow — create a todo per step

1. **Intake.** Ask for whatever is missing: topic and audience; the customer question each module answers; products and pinned versions; tracks and time budget; tenancy (dedicated cluster per participant is the default; shared cluster means per-user namespaces); the test cluster; the public git repo URL Argo CD will sync.
2. **Plan.** Fill `PLAN.md` (workshop map + one Teaches/Placement/Draft steps/Caveats entry per exercise). Get the user's OK before writing pages.
3. **Scaffold.** `cp -R <this skill>/assets/scaffold/. <lab repo>/` into a git repo (Antora only reads content from git), then `npm install` once to create the lockfile.
4. **Write pages.** Follow `references/page-set.md`. Every name or version that repeats is an attribute in `content/antora.yml`. Every `role="execute"` block is followed by `Expected result:` and a `// UNVERIFIED` line until you have seen the result live.
5. **Automation and GitOps.** Follow `references/automation-gitops.md`.
6. **Local checks.** `npm run build` (fails on any warning, including a missing attribute) and `bash scripts/check-lab.sh --draft`.
7. **Review before deploy.** Run whatever reviews the user's instructions require (e.g. xreview, ponytail-review) on the lab repo now.
8. **Deploy and verify live.** Follow `references/verification.md`: push, bootstrap, walk every page as the participant from the Showroom terminal, replace each `// UNVERIFIED` with what you observed. Done when `bash scripts/check-lab.sh` (strict) passes and a clean re-run from cleanup to the last module succeeds.

## Rules

- Command completion is not proof. `Expected result:` names the field or value seen and what it proves.
- Every allow gets a matching deny (negative control); every break gets a restore.
- Behavior checks live in the guide as collapsible scripted assertions plus `automation/verify.sh` — no separate test suite.
- Commands are idempotent (`delete ... --ignore-not-found` before `create`) and name their namespace explicitly.
- No secrets in content. Images pinned by digest or exact tag.
- Each lab states what it does **not** prove (reference page).
- Facilitator material is a rendered page, not a README.

## Common mistakes (seen without this skill)

| Mistake | Fix |
|---|---|
| Expected output written from memory | `// UNVERIFIED` until observed; strict `check-lab.sh` blocks release |
| Invented `gitops/application.yaml` with a placeholder repoURL | Field-content chart in `automation/argocd`; RHDP injects `deployer.domain` |
| Showroom not deployed by the chart | `showroom` child Application from the pinned upstream chart |
| Terminal tab at `/wetty` | Field-content Showroom proxies the terminal at `/terminal` |
| Verified as cluster-admin, participant has less | Run steps from the Showroom terminal (`showroom` ServiceAccount); grant it only what exercises need |
| Bare steps with no why or checkpoint | Module template: why → Technical context → Learning objectives → Exercises → Evidence checkpoint + Answer key |
| Hundreds of lines of test harness for a two-module lab | Guide assertions + `verify.sh` + `check-lab.sh` |

## Files

- `references/page-set.md` — every page's sections, the module template, AsciiDoc idioms
- `references/automation-gitops.md` — chart layout, Showroom identity, Makefile, readiness checks
- `references/verification.md` — test-cluster prep and the live verification pass
- `assets/scaffold/` — starter repo; `scripts/check-lab.sh` enforces the mechanical rules
