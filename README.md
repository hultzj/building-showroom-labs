# building-showroom-labs

A [Claude Code](https://claude.com/claude-code) skill for building Red Hat Demo
Platform (RHDP) **Showroom labs that run on OpenShift**. It produces all three
parts of a lab and keeps them in agreement:

- **the guide**: Antora/AsciiDoc pages that Showroom renders;
- **the automation**: `make` targets for facilitators;
- **the GitOps chart**: the RHDP field-content Helm chart that OpenShift
  GitOps (Argo CD) deploys.

Its core rule is that every step's expected result is **observed on a real
cluster, as the participant**, never written from memory. The included
`check-lab.sh` blocks release while any step is still unverified.

It covers RHDP orders and pre-existing clusters, GitOps-built and
participant-built stacks, and dedicated (the default) or shared clusters.

## Install

The repository is private; you need read access to it.

```bash
git clone https://github.com/hultzj/building-showroom-labs.git \
  ~/.claude/skills/building-showroom-labs
```

Start a new Claude Code session; the skill loads automatically. To update:

```bash
git -C ~/.claude/skills/building-showroom-labs pull
```

## Use

In Claude Code, either type `/building-showroom-labs` or describe the lab you
want, for example:

> Build a Showroom lab that teaches default-deny NetworkPolicy on OpenShift,
> about 45 minutes, one cluster per participant.

A complete prompt answers the skill's intake questions up front, so it can go
straight to planning. Copy this one and change the details:

```text
Use the building-showroom-labs skill to build a new Showroom lab.

Topic: Serving a model with OpenShift AI and controlling who can call it.
Audience: application developers new to OpenShift AI.
Customer question: "Can we serve models on our own cluster and prove only
approved apps can reach them?"
Modules:
  1. Deploy a small CPU model with KServe in your project and query it.
  2. Restrict access to the model endpoint, prove an unapproved client is
     refused, then restore.
Products: OpenShift 4.20+, OpenShift AI 3.x (already installed).
Time: one track, about 60 minutes.
Environment: RHDP order, one dedicated cluster per participant. GitOps
deploys the prerequisites; participants do the exercises.
Repo Argo CD will sync: https://github.com/<you>/<lab-repo>.git (public).
Test cluster for live verification: I am logged in with oc (cluster-admin).
```

The skill then works through these steps, asking you for anything it needs:

1. **Intake.** Topic, audience and the customer question each module answers;
   products and versions; time budget; the test cluster; the git repo Argo CD
   will sync. It also settles where the lab runs, who builds the stack, and
   who shares a cluster. Those answers decide the participant's identity.
2. **Scaffold.** It copies the starter repo from `assets/scaffold/` into a new
   git repo.
3. **Plan.** It writes `PLAN.md` and waits for your OK.
4. **Pages, automation and GitOps.**
5. **Local checks.**
6. **Review.** Whatever reviews your own instructions require.
7. **Live verification on your cluster.** It deploys the lab, walks every step
   as the participant (driving GUI steps with the Playwright browser tools),
   records what it observed, and proves the lab repeats from a clean install.

## Commands in a generated lab

| Command | What it does |
|---|---|
| `npm install` | Once, after scaffolding: installs Antora and creates the lockfile |
| `npm run build` | Builds the guide into `www/`; fails on any warning, including a missing attribute |
| `bash scripts/check-lab.sh --draft` | Checks the lab's structure while you draft |
| `bash scripts/check-lab.sh` | Release check: also fails while any step is still marked `// UNVERIFIED` (CI runs this) |
| `make -C automation help` | Lists the targets below |
| `make -C automation bootstrap` | Deploys the lab through OpenShift GitOps on a cluster without an RHDP order. Requires the pushed revision with no local changes; refuses to take over a namespace that is not this lab's |
| `make -C automation status` | Shows sync and health of the lab's Argo CD Applications |
| `make -C automation verify` | Facilitator readiness check: one PASS/FAIL line per prerequisite, checked as the participant, including whether each Showroom tab (such as the OpenShift console) can be shown in its frame |
| `make -C automation teardown` | Deletes the lab's Applications and everything they created |

On an RHDP order, skip `bootstrap`: order the Field Content CI with the lab's
repository URL and the path `automation/argocd`.

**Event branches.** Event-specific values (a bucket endpoint, a model URL) go on
a branch. On that branch, set `gitops.revision` in
`automation/argocd/values.yaml` to the branch name, commit, push, check the
branch out, and run `make -C automation bootstrap`. It deploys that revision.
On an RHDP order, give the branch in the order instead.

## Requirements

- **To build and check a lab:** git, Node.js 22 with npm, Helm 3, bash, make,
  awk.
- **To deploy and verify it:** `oc` and `curl`.
  - **Cluster:** OpenShift with OpenShift GitOps and a default StorageClass
    (Showroom always creates a PVC).
  - **Permissions:** you must be logged in with cluster-admin or equivalent
    rights. `bootstrap` creates and labels namespaces, and `verify`
    impersonates participants.
  - **Repository:** the lab repository must be **public** (usually on
    GitHub). Argo CD and Showroom's content builder both clone it without
    credentials.
- **For GUI steps:** the Playwright plugin for Claude Code.
- **For the skill's own tests:** Ruby (to parse YAML) and Python 3.

## Repository layout

| Path | Contents |
|---|---|
| `SKILL.md` | The workflow and rules Claude follows |
| `references/environments.md` | RHDP vs pre-existing clusters, participant-built stacks and operators, shared tenancy, participant identity |
| `references/page-set.md` | Every guide page's sections, the module template, GUI steps, AsciiDoc pitfalls |
| `references/automation-gitops.md` | Chart layout, the Showroom terminal's identity, Makefile and `verify.sh` |
| `references/verification.md` | Preparing a test cluster and the live verification pass |
| `assets/scaffold/` | The starter lab repository |
| `tests/` | Self-tests for `check-lab.sh` and the scaffold's chart and automation |

## Testing the skill

```bash
bash tests/test-check-lab.sh            # check-lab.sh contract (32 cases)
bash tests/test-scaffold-automation.sh  # chart, Makefile, verify.sh (76 cases)
```

## Security notes

- The Showroom URL has no login, so whatever its terminal can do, anyone with
  the URL can do. The skill grants the terminal's ServiceAccount only a
  minimal Role. Labs that need cluster-wide rights, or that run on a shared
  cluster, use each participant's own login with the Showroom terminal
  switched off.
- The upstream RHDP Showroom chart binds `ClusterRole edit` to its terminal
  in the `showroom` namespace and cannot be configured otherwise. On a shared
  cluster, keep a lab deployed only while you need it.
- Secrets never go into a lab repository; `make bootstrap` reads them from
  environment variables.

## Credits

The guide structure follows
[taylorjordanNC/rhai-agent-security](https://github.com/taylorjordanNC/rhai-agent-security).
The chart layout and Showroom component come from
[rhpds/field-sourced-content-template](https://github.com/rhpds/field-sourced-content-template)
and [rhpds/rhdp-gitops-patterns](https://github.com/rhpds/rhdp-gitops-patterns).
