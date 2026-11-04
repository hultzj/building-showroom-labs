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
layout. Then harden it before the first push:

- **Showroom.** Drop the example's `deploy-showroom` role. Showroom stays the
  `showroom` child.
- **Runner image.** Pin it by digest. Never use the example's `:latest` tag.
- **Python packages.** Pin every one with `==` in `ansible.requirements`. The
  example's collections are already pinned.
- **Helm binary.** Pin the version and check its SHA-256, or bake Helm into
  the image. Never use a bare `curl | tar`.
- **RBAC.** Grant only what the playbooks touch, using namespaced Roles where
  you can. The example's ClusterRole allows `bind` and `escalate` on cluster
  roles and access to every Secret. That is close to cluster-admin for any pod
  running as that ServiceAccount.
- **Idempotency.** The Job is an Argo CD `Sync` hook with
  `BeforeHookCreation`, so every sync re-runs the playbook. Tasks must be safe
  to re-run: `state: present`, and retry-until loops instead of sleeps.
- **Readiness.** `verify.sh` checks that the Job is `Complete` and that its
  userinfo ConfigMap exists. In the live pass, `oc logs job/<name>` is
  evidence.

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
