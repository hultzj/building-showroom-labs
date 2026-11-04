# The RHDP field-content template

The skill builds to the contract of `rhpds/field-sourced-content-template`
(the field-content template). It is vendored as a git submodule at
`upstream/field-sourced-content-template/`, pinned to the same commit as the
scaffold's `showroom.chart.revision`. A test fails if those two pins drift
apart.

If that directory is empty, run
`git -C <this skill> submodule update --init`.

Read the template's own guide there when you need detail:
- `README.md`;
- `examples/helm/README.md` and `examples/ansible/README.md`;
- `catalog/README.md`;
- `docs/ansible-developer-guide.md`.

This page lists what the skill relies on and where it deliberately differs.

## The contract

- **How RHDP deploys it.** The Field Content CI takes a repo URL and a chart
  path. Its `ocp4_workload_field_content` workload creates an Argo CD
  Application for the chart, injects `deployer.domain` and `deployer.apiUrl`,
  and overrides `argocd.project` to `deployed`. Everything is a Helm chart;
  sync waves order it.
- **Health.** RHDP monitors resources labelled
  `demo.redhat.com/application: <demo name>`. The scaffold's lab namespace
  carries it with the lab's name; label your workloads the same way.
- **Data back to the order.** A ConfigMap labelled
  `demo.redhat.com/userinfo: ""` passes its data keys to the order owner (URLs,
  access notes). Put credentials there only when the order owner is meant to
  see them.

## Pick a pattern

| Pattern | Use when |
|---|---|
| Helm (the default) | The stack is manifests: namespaces, workloads, operator Subscriptions, CRs ordered by sync waves |
| Ansible-via-Helm | You need generated secrets, a wait that Argo CD health cannot express, external API calls, or conditional logic |

## Ansible-via-Helm, the skill's way

Copy `upstream/field-sourced-content-template/examples/ansible` into
`automation/argocd/components/<name>/` as one more child chart, with its own
Application in `templates/applications.yaml`. That keeps the parent/child
layout. The example is a demonstration, not a production chart. Work through
this list before the first push.

**Remove**

- The `deploy-showroom` role. Showroom stays the `showroom` child.
- The Helm download: only that role used Helm.
- The preflight task that creates a random Namespace. It needs cluster-wide
  rights and fails once RBAC is narrowed.
- The example's other roles and `requirements.yml` unless you use them. Its
  collections there are ranges, not pins.
- The scaffold's `lab-prereqs/templates/userinfo.yaml`, if the playbook writes
  userinfo. Otherwise Argo CD's selfHeal reverts the playbook's values.

**Rewire**

- **Playbook source.** Point `ansible.repository.url` and `branch` at the
  lab's own repo (the parent's `gitops.repoUrl` and `gitops.revision`), and
  `path` at `<gitops.basePath>/components/<name>/playbooks`, where the copied
  `site.yml` lives. Otherwise the Job runs upstream's demo playbook. It clones the
  branch tip, so the revision should be the branch Argo CD syncs.
- **Showroom URL.** `site.yml` uses `showroom_url`, which only the dropped
  role set. Compute it the scaffold's way (`https://showroom-<namespace>.<domain>`),
  or look up the `showroom` Route with `kubernetes.core.k8s_info` (which needs
  `get` on Routes there).
- **Namespace ownership.** In `templates/namespace.yaml`:
  - add `app.kubernetes.io/part-of: {{ .Values.partOf }}` and
    `argocd.argoproj.io/managed-by: {{ .Values.argocdNamespace }}`;
  - set `demo.redhat.com/application` to `{{ .Values.partOf }}`, and do the
    same in `_helpers.tpl`'s labels;
  - add `partOf` and `argocdNamespace` to `values.yaml`, and have the parent's
    Application pass them, as it does for `lab-prereqs`.

  Without this, `check-lab.sh` and `make bootstrap`'s ownership guard reject
  the namespace.
- **Template details.** Name the Job from `job.name`; the example builds
  `<release>-<chart>` and ignores it. Make `deployer.domain` `required`; the
  example's fallback domain silently produces wrong URLs.

**Harden**

- **Runner image.** Use a public, digest-pinned image, for example
  `registry.access.redhat.com/ubi9/python-312@sha256:…`. The example's
  `registry.redhat.io` image needs a pull secret and ships Python 3.9.
  Confirm in the live pass that the image has `git`.
- **Versions.** Pick a supported `ansible-core` and a matching
  `kubernetes.core`, and pin both. The example's pins target ansible-core
  2.15, which is end-of-life and does not run on Python 3.12.
- **Python packages.** Pin direct packages with `==`. Resolve the full set
  (`pip freeze`) inside the runner image, not on your workstation, so the
  wheels match its Python and platform.
- **RBAC.** Grant only what the playbook touches: namespaced Roles, with
  `resourceNames` wherever the verb allows it. `create` cannot be limited by
  name. The example's ClusterRole allows `bind` and `escalate` on cluster
  roles and access to every Secret, close to cluster-admin for any pod running
  as that ServiceAccount.
- **Secrets stay out of logs.** Put `no_log: true` on every task that reads or
  writes a secret value; the Job's log is evidence. ansible-core still prints
  the error text of a failed `no_log` task, so keep values out of `fail`
  messages. Put credentials in userinfo only when the order owner is meant to
  see them.

**Behave**

- **Idempotent, without rotating secrets.** The Job is an Argo CD `Sync`
  hook with `BeforeHookCreation`, so every sync re-runs the playbook. Use
  `state: present` and retry-until loops. A generated secret must be
  get-then-create-if-absent: `state: present` with a fresh random value
  rotates it under running pods.
- **Job retention.** Set `job.ttlSecondsAfterFinished: 0`; the template then
  omits the TTL. The example's 600 seconds deletes the Job and its logs ten
  minutes after it finishes. `BeforeHookCreation` still replaces it on the
  next sync.
- **Ordering.** Do not sync-wave a child after another child whose health
  depends on it. If a Deployment needs the Job's Secret, it cannot go Healthy
  first, so waiting for it deadlocks. Leave both unwaved and rely on the
  children's retry. A Role or RoleBinding that lands in a namespace another
  child creates is covered by the same retry.
- **Readiness.** `verify.sh` checks that the Job is `Complete` and that its
  userinfo ConfigMap holds the expected keys. In the live pass,
  `oc logs job/<name>` is evidence.

## The community catalog

The scaffold's `catalog-stub.yaml` follows the template's catalog schema:
- `name` (DNS-1123);
- `displayName`, `description`, `owner`;
- `repoURL`, `revision`, `chartPath`;
- `requires` (`virt`, `rhoai`, `aap`, `clusterSize`).

`check-lab.sh` validates it.

1. After the live pass, open a PR to the template repo adding the stub as
   `catalog/untested/<name>.yaml`.
2. Moving it to `catalog/tested/` is a separate PR, once someone has synced
   it on a Field Content cluster.

The template's README still lists `path` as required. That line predates the
rename to `chartPath`, so use `chartPath`, as its tested stubs do. Stubs reach
Argo CD only once the CI's ApplicationSet reads `catalog/tested/`. Ordering the
CI with your own repo URL works regardless.

## Where the skill differs from the template, and why

- **Showroom.** The template's helm example copies its components into your
  repo. The skill references the upstream Showroom chart by URL and commit, so
  a lab carries no copied chart.
- **Example components.** `hello-world` and `operator` are demonstrations.
  `lab-prereqs` and other children replace them; for tested operator installs
  see `environments.md`.
- **Argo CD permissions.** The template's Ansible preflight tells you to make
  the Argo CD controller cluster-admin. On pre-existing clusters the skill uses
  namespace `managed-by` labels instead (`environments.md`). RHDP orders
  already grant the controller what it needs.
- **Updating the pin.** Bump the submodule and `showroom.chart.revision`
  together, then re-run the live pass.
