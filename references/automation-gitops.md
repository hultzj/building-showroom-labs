# Automation and GitOps

## Layout

```
automation/
  Makefile                      participant/facilitator entry point: make -C automation <target>
  verify.sh                     PASS/FAIL readiness checks, non-zero exit on any FAIL
  bootstrap.yaml                parent Application, for clusters without an RHDP order
  argocd/                       RHDP field-content chart (the order's repo path)
    Chart.yaml
    values.yaml                 gitops.*, argocd.*, lab.*, showroom.*, deployer.* (injected)
    templates/applications.yaml one child Application per component
    components/lab-prereqs/     this lab's resources, as a plain Helm chart
```

**How RHDP deploys it:** order the Field Content CI with the repo URL and path
`automation/argocd`. The workload creates the parent Application, injects
`deployer.domain` and `deployer.apiUrl`, and overrides `argocd.project` to
`deployed`. On any other cluster, `make -C automation bootstrap` applies
`bootstrap.yaml` with the cluster's ingress domain filled in.

## Children

- **showroom**: the upstream `rhpds/field-sourced-content-template`
  `examples/helm/components/showroom` chart, referenced by URL and **pinned to
  a commit SHA** (`showroom.chart.revision`), not copied. The parent passes
  only the overrides it needs: content repo and ref, `deployer.domain`, and
  `demo.namespace` (which lands in Showroom's `user_data`).
- **lab-prereqs**: everything the exercises assume already exists —
  namespaces, workloads, operator Subscriptions — plus the RoleBinding that
  gives the Showroom terminal identity its permissions.
- Add more children for heavy or independent parts (an operator, a seed
  job), with `argocd.argoproj.io/sync-wave` to order them.

## The Showroom terminal identity

The Showroom terminal runs as the `showroom` ServiceAccount in the `showroom`
namespace, where it has `edit`. The Showroom Route has no login, so **anyone
with the URL holds these permissions.** Every permission an exercise needs
elsewhere is a Role and RoleBinding in `lab-prereqs`, scoped to the lab
namespace:

- read (`get`, `list`, `watch`) on what the exercises inspect;
- write only on what they change;
- `pods/exec` (`create`, `get`) when a step runs `oc exec`.

Do not use `ClusterRole edit`: it lets a participant relabel pods or edit
workloads and walk around the control the lab teaches. The pre-flight on
`02-details.adoc` checks the same permissions with `oc auth can-i`.

Workload settings (images, ports, names) live in the component's
`values.yaml`. The guide repeats the names it shows as `antora.yml`
attributes. That duplication is accepted: the live pass catches drift.

## Drift that exercises cause on purpose

Child Applications use `selfHeal: true`. If an exercise changes a resource
Argo CD manages (scaling a Deployment, patching a ConfigMap), add an
`ignoreDifferences` entry for exactly that field, with a one-line comment
naming the exercise. The scaffold's children already set the
`RespectIgnoreDifferences=true` sync option; without both, Argo CD reverts the
participant's change.
Resources the participant creates fresh, such as a NetworkPolicy, carry no
Argo CD tracking annotation and are never pruned.

## Makefile and verify.sh

- Targets: `help`, `bootstrap`, `status`, `verify`, `teardown`. Each target
  is a thin wrapper; the logic lives in scripts or the chart.
- `verify.sh` uses a `check "<name>" <command>` helper that prints PASS or
  FAIL per lab prerequisite and exits non-zero if any fail. The facilitator
  runs it before class as cluster-admin, so permission checks and probes
  impersonate the terminal (`--as "$TERMINAL_SA"`).
- `teardown` deletes the parent Application. Its
  `resources-finalizer.argocd.argoproj.io` finalizer cascades the delete to
  the children and their resources.

## Out of scope by default

Multi-cluster fleet scripts and per-user ApplicationSets. Add them only when
intake says the tenancy needs them. For per-user tenancy, see `multi_user` in
the upstream template's `examples/helm/templates/applicationset-per-user.yaml`.
