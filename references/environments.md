# Environments: where the lab runs, who builds it, who the participant is

Decide these three at intake, record them in `PLAN.md`, then apply the
matching sections below. The rest of the skill is the same for every
combination.

| Question | Options |
|---|---|
| Where | **RHDP order** (Field Content CI deploys `automation/argocd`) or **pre-existing cluster** (a facilitator or customer hands one over) |
| Who builds the stack | **GitOps** (`lab-prereqs` and other components) or **participants** (guide steps install it), or a mix |
| Tenancy | **Dedicated** cluster per participant, or **shared** cluster with one namespace set per user |

## Participant identity (decides RBAC, terminal and verification)

| If the lab… | The participant acts as | Showroom terminal |
|---|---|---|
| stays inside namespaces the chart creates, on a dedicated cluster | the `showroom` ServiceAccount, with a minimal Role (`automation-gitops.md`) | on |
| needs cluster-scoped writes (operators, CRDs, cluster config), or runs on a shared cluster | **their own OpenShift user** | **off**: `showroom.terminal: false` |

The Showroom URL has no login, so whatever its terminal can do, anyone with
the URL can do. Never give the terminal ServiceAccount operator-install,
CRD, or cross-tenant rights.

When the terminal is off, participants run commands as themselves:

- The Web Terminal operator in the console. Install it as a GitOps
  component. `rhdp-gitops-patterns` `service-mesh-lab` has a tested
  Subscription.
- Or their own `oc login` on a workstation.

Update the tab list in `ui-config.yml`, then swap the pre-flight's `oc whoami`
expectation to their username. Verification uses the same identity
(`verification.md`).

## Shared cluster

- **One Showroom for everyone.** Showroom's `user_data` cannot vary per user,
  so pages derive per-user values in the shell: `ME=$(oc whoami)` and
  `NS=$ME-<suffix>`. Have participants re-run that block after a terminal
  restart.
- **Per-user namespaces.** Either participants self-provision them as the
  first exercise, or GitOps creates them using RHDP's tenant pattern:
  `rhpds/rhdp-gitops-patterns`, `bootstrap-tenant`, which takes a `username`
  and binds that User to `edit` in `<username>-<ns>`. On RHDP the order's
  deployer creates one Application per user. On a pre-existing cluster, the
  lab ships an ApplicationSet with a list generator, `user1..userN`.
- **Cross-user negative controls get a deterministic target.** GitOps deploys a
  facilitator-owned decoy tenant (for example `peer-demo`), so "you cannot
  reach another tenant" never depends on another participant's progress.
- **Capacity.** The facilitator guide states the per-user footprint times N,
  plus the shared services. `verify.sh` checks that every user can do the
  first step: impersonate `--as userN` in a loop.

## Pre-existing cluster (no RHDP order)

- The facilitator guide lists the cluster prerequisites, each with a check
  command:
  - OpenShift GitOps is installed;
  - the Argo CD controller can create the lab's resources (see
    `verification.md` for the check);
  - users exist, with credentials;
  - capacity, a default StorageClass, and anything else the exercises
    assume.

  On these clusters the Argo CD grant is a standing requirement of the lab.
  Document the exact command, and say it needs the cluster owner's approval.
- The facilitator runs `make -C automation bootstrap` and owns teardown. The
  cleanup page splits into **participant cleanup** (what they created) and
  **facilitator teardown**. Teardown removes only what Argo CD created.
  List the participant-created leftovers (projects, operators) with a
  look-before-delete command.

## Participant-built stack

- The chart deploys Showroom plus fixtures only. Drop `lab-prereqs`, or keep
  only RBAC and decoys. Delete the scaffold's `namespace.yaml` when
  participants create the namespace. `check-lab.sh` and `verify.sh` handle a
  chart with no components.
- **Before the install,** the step must fail: a negative control such as
  `oc api-resources --api-group=<group>` printing nothing.
- **Operator install:** Subscription via `oc apply`, with
  `metadata.name: <package>`. Then a bounded wait chain:
  1. poll `.status.installedCSV`, then the CSV until `phase=Succeeded`;
  2. poll until the operator's CR exists (`oc wait` fails at once on a kind
     that does not exist);
  3. `oc wait --for=condition=Ready --timeout=…`.

  Waits the next step depends on stay in the main path, not in a
  collapsible.
- **Runs that can fail.** `oc wait --for=condition=Succeeded` hangs until
  timeout on a failed run. Poll `status.conditions` until True or False.
- **Versions.** Pin the channel in the Subscription. Record the
  `installedCSV` seen in the live pass in the Expected result, and in
  `PLAN.md` as the verified version. Images shipped by the operator are pinned
  by that version, not by the lab.
- **Uninstall order** (verify live; operators differ):
  1. the participant's resources;
  2. the operator's top-level CR, while the operator still runs, so it
     removes its webhooks and console plugin;
  3. the Subscription, then the CSV;
  4. CRDs last, as cluster-admin, with a look-before-delete.

## GitOps-installed operators

Copy the Subscription, OperatorGroup and CR from the matching
`rhdp-gitops-patterns` example instead of writing one. Its README catalogs
tested installs: Pipelines, RHOAI, Virtualization, Service Mesh, Serverless,
DevSpaces and more. Put CRs whose CRD arrives with the operator in a later
sync wave, annotated
`argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`.
