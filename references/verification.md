# Live verification

The goal: every `// UNVERIFIED` marker is replaced with an observed result,
and the guide runs clean from the first step to the last on a fresh install.

## 1. Prepare the test cluster (once)

RHDP clusters come with these in place. A bare test cluster needs:

- **OpenShift GitOps.** Check for `oc get csv -n openshift-gitops-operator`.
  If it is missing, ask the cluster owner before installing it; it is a
  cluster-wide operator.
- **On a pre-existing delivery cluster this setup is part of the lab.** Copy
  it into the facilitator guide's prerequisites; see `environments.md`.
- **Argo CD permission to create the lab's resources.** On RHDP the
  application controller can do this. A fresh OpenShift GitOps install's
  default controller can create Namespaces, RBAC and ConfigMaps, but not
  Deployments, Services or Routes, except in namespaces labelled
  `argocd.argoproj.io/managed-by`. The scaffold labels its namespaces (see
  `environments.md`), so namespace-scoped labs need no extra grant.
  Check with `oc auth can-i create deployments -n <ns>
  --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller`.
  If the chart manages cluster-scoped resources, ask the cluster owner before
  granting more, because that grant is cluster-wide. On a test cluster the grant is setup only and stays out of
  the lab repo.

## 2. Deploy

The first push turns CI red on purpose: strict `check-lab.sh` fails until
every step is verified.

```bash
git push origin main                 # Argo CD syncs from the remote, not your checkout
make -C automation bootstrap
make -C automation status            # repeat until every Application is Synced/Healthy
make -C automation verify            # every line PASS
```

If the Showroom pod sits in `Init:Error`, read the guide build:
`oc -n showroom logs deploy/showroom -c antora-builder`. After pushing a fix,
delete the pod; its init containers keep the old clone until it is replaced.

A sync error is a lab bug. Fix it in the chart, push, and let Argo CD
re-sync. Do not patch the cluster by hand.

## 3. Walk the guide as the participant

- Open the Showroom route (`oc -n showroom get route showroom`) and confirm
  every page renders. Rendering checks: attributes are substituted, user_data
  values such as the cluster domain show real values, the terminal tab
  connects, and every `url:` tab in `ui-config.yml` (the console, a dashboard)
  shows its page rather than a blank frame. `verify.sh` checks each tab
  target's status and framing headers. A lab that links the console instead
  of tabbing it has nothing to check here.
- Walk as the participant identity from `environments.md`. With the
  ServiceAccount identity, run each `role="execute"` block in page order
  **from the Showroom terminal**. The terminal runs as the `showroom` ServiceAccount, and a
  cluster-admin shell hides missing RoleBindings. For long sessions, run the
  same commands with `oc exec -n showroom deploy/showroom -c terminal --
  bash -lc '<command>'`.
- For each block, record the actual output under `evidence/` (gitignored).
  Then rewrite `Expected result:` to name the fields and values you saw, and
  delete its `// UNVERIFIED` line. If the output contradicts the guide's
  claim, fix the lab, not the wording.
- Run every collapsible scripted assertion. Each one must exit 0 on the
  happy path. For at least one per module, confirm it exits non-zero when you
  break the condition.
- With the participant's own identity, log in as a real non-admin participant
  (on a shared cluster, two of them, such as `user1` and `user2`, to see the
  tenants isolated from each other and from the decoy). Run commands with that user's `oc` token.
- **GUI steps:** drive them with the Playwright browser tools as the
  participant. Log in to the console or dashboard, click through the
  numbered steps, and take `browser_snapshot` to read the exact labels the
  guide must quote. Save a screenshot per step to `evidence/`. Screenshots the
  guide embeds are captured in this same pass, into
  `content/modules/ROOT/assets/images/` (see `page-set.md`); replace them on
  every pass. Record the product and console versions in `PLAN.md`. Check
  every `GUI view:` claim the same way.
- Never ask the user to paste credentials into the conversation. Read them
  from a local file or environment variable. Playwright's browser state
  (`.playwright-mcp/`) holds session cookies and stays gitignored.

## 4. Prove it repeats

1. Run the cleanup page.
2. Run `make -C automation teardown`.
3. Wait for the namespaces to disappear.
4. Bootstrap again and repeat the walk without editing anything.

A step that only works the second time is not idempotent; fix it.

## 5. Finish

- `bash scripts/check-lab.sh` (strict) and `npm run build` pass.
- Offer the user the community-catalog PR: `catalog-stub.yaml` to the
  field-content template's `catalog/untested/` (`field-content.md`).
- Push the verified guide. Leave the test cluster as you found it: tear the
  lab down promptly (the Showroom terminal is open to anyone with its URL),
  and tell the owner what test-cluster setup from step 1 remains.
