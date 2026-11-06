# Environments: where the lab runs, who builds it, who the participant is

Decide these three at intake, record them in `PLAN.md`, then apply the
matching sections below. The rest of the skill is the same for every
combination.

| Question | Options |
|---|---|
| Where | **RHDP order** (Field Content CI deploys `automation/argocd`) or **pre-existing cluster** (a facilitator or customer hands one over) |
| Who builds the stack | **GitOps** (`lab-prereqs` and other components) or **participants** (guide steps install it), or a mix |
| Tenancy | **Dedicated** cluster per participant (the default), or **shared** cluster with one namespace set per user, only when intake asks for it |

## Participant identity (decides RBAC, terminal and verification)

| If the lab… | The participant acts as | Showroom terminal |
|---|---|---|
| stays inside namespaces the chart creates, on a dedicated cluster | the `showroom` ServiceAccount, with a minimal Role (`automation-gitops.md`) | on |
| needs cluster-scoped writes (operators, CRDs, cluster config), or runs on a shared cluster | **their own OpenShift user** | **off**: `showroom.terminal: false` |

The Showroom URL has no login, so whatever its terminal can do, anyone with
the URL can do. Never give the terminal ServiceAccount operator-install,
CRD, or cross-tenant rights.

When the terminal is off, participants run commands as themselves:

- The Web Terminal operator in the console. On RHDP, copy the
  `rhdp-gitops-patterns` `service-mesh-lab` Subscription. Elsewhere, use the
  `redhat-operators` catalog instead of `rhpds-redhat-operators`, and make it
  a toggle: if the operator is already installed, Argo CD must not adopt it,
  or teardown deletes the owner's Subscription. The Web Terminal runs inside
  a project, so deleting that project kills the terminal; warn on the cleanup
  page. It also pulls in the DevWorkspace operator, which is left behind.
- Or their own `oc login` on a workstation.

Update the tab list in `ui-config.yml`, then swap the pre-flight's `oc whoami`
expectation to their username. Verification uses the same identity
(`verification.md`).

## Shared cluster

A shared lab can run on an RHDP order too. The Field Sourced Content order
form sets:
- cluster size: `multinode`, not SNO, for worker MachineSets;
- worker count and instance type;
- base workloads, such as OpenShift AI preinstalled;
- "Create users on cluster?", which creates Keycloak users `user1`…`userN`.

The chart also receives the list as `multi_user.users` (`[{username: user1}, …]`)
and `multi_user.num_users`, so a per-user Application or namespace can be
templated from it directly (`field-content.md`). The facilitator reads the same
list from the `KeycloakRealmImport` named `sso` in the `keycloak` namespace:
`oc get keycloakrealmimport sso -n keycloak -o jsonpath='{.spec.realm.users[*].username}'`.
Participants keep minimal rights. Never make them cluster-admin: it makes
every isolation claim meaningless and lets one participant break the
workshop for all.

- **One Showroom for everyone.** Showroom's `user_data` cannot vary per user,
  so pages derive each user's namespace in the shell. Pick the rule by who
  creates the namespace:
  - **GitOps creates it** (the tenant pattern below, from the facilitator's
    DNS-safe user list): `NS=$(oc whoami)-<suffix>`, matching the
    `<username>-<suffix>` the tenant chart creates.
  - **Participants self-provision it** and usernames may be arbitrary (SSO,
    email addresses): the sanitized username plus the full checksum of the
    username, so distinct users get distinct, valid names. A CRC collision
    is still possible but fails loudly: `oc new-project` reports
    `AlreadyExists`, and RBAC forbids touching another user's project.

    ```bash
    ME=$(oc whoami)
    B=$(printf '%s' "$ME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | cut -c1-38 | sed 's/^-*//; s/-*$//')
    NS="${B:+$B-}u$(printf '%s' "$ME" | cksum | cut -d' ' -f1)-<suffix>"   # suffix of 12 characters or fewer
    echo "$NS"
    ```

  GUI steps tell participants to type the printed name. Have participants re-run the block after a terminal
  restart.
- **Per-user namespaces.** Either participants self-provision them as the
  first exercise, or GitOps creates them using RHDP's tenant pattern:
  `rhpds/rhdp-gitops-patterns`, `bootstrap-tenant`, which takes a `username`
  and binds that User to `edit` in `<username>-<ns>`. Either way the lab
  ships an ApplicationSet with a list generator: on RHDP its elements come
  from `multi_user.users` (the order creates only `field-content`; see
  upstream `examples/helm/templates/applicationset-per-user.yaml`, but take
  `repoURL` from `gitops.repoURL | default gitops.repoUrl`, which that example
  does not); on a pre-existing cluster, list `user1..userN` in `values.yaml`.
- **Cross-user negative controls get a deterministic target.** GitOps deploys a
  facilitator-owned decoy tenant (for example `peer-demo`), so "you cannot
  reach another tenant" never depends on another participant's progress.
- **Capacity.** The facilitator guide states the sizing, worked out like
  this:
  1. Per user, add the CPU and memory *requests* of what each participant
     runs (workbench, Showroom, what the exercises deploy).
  2. Per worker, take the allocatable capacity of the instance type, minus
     the requests of pods that run on every node (DaemonSets).
  3. Reserve one worker's worth for the platform's own pods.

  Workers = 1 + ceil(users ÷ users per worker), and the guide prints that
  table for 10, 20 and 30 users. Size at order time; adding MachineSet
  replicas later is the fallback. `verify.sh` checks that every user can do
  the first step. Impersonate with groups:
  `--as userN --as-group system:authenticated --as-group system:authenticated:oauth`,
  plus `--as-group <g>` for each OpenShift Group that lists the user. `--as`
  alone drops every group, including the ones that grant project
  self-provisioning, and a grant through any Group would go unseen.
- **Participant-chosen names collide.** The facilitator guide lists projects
  whose name does not match their requester
  (`openshift.io/requester` annotation).
- **`User` objects exist only after a first login.** Check the identity
  provider instead, and log in once as the first and last user before class.

## What an RHDP order differs in

Seen on a Field Sourced Content - OpenShift Base order (OpenShift 4.22.18,
OpenShift AI 3.5.2, 2026-11-06); each broke a lab step that passed on a
reused test cluster.

- **Ingress certificate.** The IngressController serves a public
  certificate from cert-manager (`spec.defaultCertificate`:
  `cert-manager-ingress-cert`); `router-certs-default` does not exist.
  Reference the Secret from `spec.defaultCertificate.name`, falling back to
  `router-certs-default`, and check a Gateway listener's `ResolvedRefs`:
  the Gateway reports `Programmed` even when its listener's certificate is
  invalid.
- **Trust bundle.** `default-ingress-cert` (`openshift-config-managed`)
  then holds a chain that stops at a cross-signed intermediate. `curl` and
  Python 3.13 accept that partial chain; Python 3.12 (the OpenShift AI
  workbench image) and `openssl verify` do not. Build the bundle a client
  verifies with from the system CAs plus that chain:
  `{ cat /etc/pki/tls/certs/ca-bundle.crt; oc get configmap default-ingress-cert -n openshift-config-managed -o jsonpath='{.data.ca-bundle\.crt}'; } > ~/ingress-ca.crt`.
  Self-signed ingress keeps working.
- **OpenShift AI base workload.** Only `dashboard` and `workbenches` are
  `Managed`; enable the components the lab needs (`kserve`,
  `modelregistry`, `trustyai`, …) as a facilitator step, and check them in
  `verify.sh`.
- **No GPU.** Add a node from a worker MachineSet if the lab needs one.
- **Several replicas.** Gateways scale out (ten inference-gateway pods were
  seen); read logs by label (`oc logs -l … --max-log-requests=20`), never
  the first pod by name.
- **Web Terminal idles out.** A session with no keystrokes stops after 15
  minutes even while a command runs, and the workspace is stopped. For long
  waits, participants run `wtoctl set timeout 4h` once; automation that
  drives the terminal must account for it.
- **Unreachable is not refused.** A connection to a closed port on a
  ClusterIP is dropped, not refused, so a break-and-restore that points a
  client at a dead port ends in the route's timeout (an HTML 504), not the
  application's error. Parse defensively: report non-JSON as an error.

## Pre-existing cluster (no RHDP order)

- The facilitator guide lists the cluster prerequisites, each with a check
  command:
  - OpenShift GitOps is installed;
  - the Argo CD controller can create the lab's resources (see
    `verification.md` for the check);
  - users exist, with credentials;
  - capacity, a default StorageClass, and anything else the exercises
    assume.

  **Argo CD permissions on these clusters** come from namespace labels, not a
  cluster-wide grant. The OpenShift GitOps operator gives its default Argo CD
  instance `admin` in any namespace labelled
  `argocd.argoproj.io/managed-by=openshift-gitops`. That covers Deployments,
  Services, Routes and PVCs, and binding `edit`. It does not extend beyond
  those namespaces. (Verified on OpenShift 5.0 with GitOps 1.22: the grant
  lands within seconds.)
  - The scaffold's `lab-prereqs` namespace carries the label.
  - `make bootstrap` labels the Showroom namespace before applying the parent.
  - The children retry while the grant lands.

  A cluster-wide grant
  (`oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops`)
  is needed only when the chart itself manages cluster-scoped resources
  beyond Namespaces, RBAC and OLM Subscriptions, which the default controller
  already handles. Examples are a DataScienceCluster or TektonConfig. In that
  case it is a documented facilitator prerequisite needing the cluster
  owner's approval, removed at teardown.
- **The console tab.** `ui-config.yml`'s OpenShift Console tab is an iframe. A default console answers `X-Frame-Options: DENY` (verified on OpenShift 5.0), so the tab renders blank. Some RHDP orders embed the console with the `ocp4_workload_ocp_console_embed` workload; the Field Sourced Content - OpenShift Base order does not (`X-Frame-Options: DENY` on OpenShift 4.22.18, 2026-11-06), so remove the tab there as on a pre-existing cluster. The embedding workload: the router drops `X-Frame-Options` and sets `Content-Security-Policy: frame-ancestors 'self' <Showroom origins>` (often `https://*.apps.<domain>`). On a pre-existing cluster the default is to remove the tab and link the console from the guide with `link:...[^]`, which opens a new browser tab. To embed it there instead, with the owner's approval:
  - **Cluster-wide.** Use the same header actions in the default IngressController's `spec.httpHeaders.actions.response`: delete `X-Frame-Options`, and set `frame-ancestors` to exactly the Showroom origins, not `*`.
  - **One app.** Put the same actions in a single Route's `spec.httpHeaders`, for example a workbench.

  Applying it rolls the routers, which can drop Web Terminal sessions, so run it from a workstation and re-check the headers afterwards. `verify.sh` fails while any `url:` tab's target refuses the Showroom origin.
- **The Showroom chart always creates a 5Gi RWO PVC** (terminal on or off),
  so a default StorageClass is a hard requirement.
- **Per-event values** (bucket endpoint, model URL) live on an event branch
  whose `values.yaml` sets `gitops.revision` to that branch, which also drives
  the Showroom content ref. Deploy with `make -C automation bootstrap
  REVISION=<branch>`, or give the branch in the RHDP order, so `main` stays
  generic. Delete `userinfo.yaml` (RHDP order page only).
- The facilitator runs `make -C automation bootstrap` and owns teardown. The
  cleanup page splits into **participant cleanup** (what they created) and
  **facilitator teardown**. Teardown removes only what Argo CD created.
  List the participant-created leftovers (projects, operators) with a
  look-before-delete command.

## Participant-built stack

- The chart deploys Showroom plus fixtures only. Set `prereqs.enabled: false`
  and delete `components/lab-prereqs`, or keep only RBAC and decoys in it. Delete the scaffold's `namespace.yaml` when
  participants create the namespace. `check-lab.sh` and `verify.sh` handle a
  chart with no components.
- **Before the install,** the step must fail: a negative control such as
  `oc api-resources --api-group=<group> -o name` printing nothing. Without
  `-o name` it prints a header even when nothing matches.
- **Choosing the channel:** on the test cluster, read
  `oc get packagemanifest <package> -n openshift-marketplace -o
  jsonpath='{.status.defaultChannel}'` and the channel list. Make the
  channel an attribute, and have `verify.sh` fail if the catalog stops
  offering it.
- **Operator install:** one primary path (console or CLI). The CLI path
  first checks whether a Subscription for the package already exists (`oc
  get subscriptions -A`, matching `.spec.name`), so a participant who used
  the console doesn't create a second one. Subscription via `oc apply`, with
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
