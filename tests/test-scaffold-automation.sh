#!/usr/bin/env bash
# Self-check for the scaffold's chart and automation; each case must hold.
set -euo pipefail
SCAFFOLD="$(cd "$(dirname "$0")/../assets/scaffold" && pwd)"
errors=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; errors=1; }

# Exercises that change a managed field rely on ignoreDifferences, which a sync only honors with RespectIgnoreDifferences=true.
apps=$(helm template t "$SCAFFOLD/automation/argocd" --set deployer.domain=apps.example.com)
n_apps=$(grep -c '^kind: Application$' <<<"$apps")
n_respect=$(grep -c 'RespectIgnoreDifferences=true' <<<"$apps" || true)
[[ $n_apps -gt 0 && $n_apps == "$n_respect" ]] && ok "every child Application respects ignoreDifferences" \
  || bad "every child Application respects ignoreDifferences ($n_respect of $n_apps)"

# The terminal toggle reaches the upstream chart as terminal.enabled.
for v in true false; do
  got=$(helm template t "$SCAFFOLD/automation/argocd" --set deployer.domain=x --set showroom.terminal=$v |
    awk '/^          terminal:/ {t = 1; next} t && /enabled:/ {print $2; exit}')
  [[ $got == "$v" ]] && ok "showroom.terminal=$v reaches the chart" || bad "showroom.terminal=$v reaches the chart (got '$got')"
done

# Paths with spaces must reach the shell as one argument.
dir='/tmp/lab checkout/automation'
for target in verify bootstrap teardown; do
  cmd=$(make -n -f "$SCAFFOLD/automation/Makefile" "$target" AUTOMATION_DIR="$dir")
  grep -Fq "\"$dir/" <<<"$cmd" && ok "make $target quotes its paths" || bad "make $target quotes its paths: $cmd"
done

# An event branch deploys from that branch: the parent's targetRevision follows REVISION.
make -n -f "$SCAFFOLD/automation/Makefile" bootstrap REVISION=event-2026 | grep -q 's|GIT_REVISION|event-2026|' \
  && ok "make bootstrap REVISION= sets the parent's revision" || bad "make bootstrap REVISION= sets the parent's revision"
grep -q 'targetRevision: GIT_REVISION' "$SCAFFOLD/automation/bootstrap.yaml" \
  && ok "bootstrap.yaml takes its revision from make" || bad "bootstrap.yaml takes its revision from make"

# verify.sh must fail when an expected child Application is missing.
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
cat > "$fake/oc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *applications.argoproj.io*) printf '%b' "$FAKE_APPS" ;;
  *route*) [[ -n ${FAKE_NO_ROUTE:-} ]] && exit 1; printf 'showroom.example.test' ;;
esac
SH
printf '#!/usr/bin/env bash\nexit "${FAKE_CURL_RC:-0}"\n' > "$fake/curl"
chmod +x "$fake/oc" "$fake/curl"
run_verify() { FAKE_APPS=$1 PATH="$fake:$PATH" LAB_NS=ns LAB_APP=lab bash "$SCAFFOLD/automation/verify.sh" >/dev/null 2>&1; }
healthy='lab Synced/Healthy lab\nlab-showroom Synced/Healthy lab\nlab-prereqs Synced/Healthy lab\n'
run_verify "$healthy" \
  && ok "verify passes with every Application Synced/Healthy" || bad "verify passes with every Application Synced/Healthy"
# A child the parent defines but that is missing leaves the parent OutOfSync.
run_verify 'lab OutOfSync/Healthy lab\nlab-showroom Synced/Healthy lab\n' \
  && bad "verify fails when the parent reports a missing child (OutOfSync)" || ok "verify fails when the parent reports a missing child (OutOfSync)"
run_verify 'lab-showroom Synced/Healthy lab\nlab-prereqs OutOfSync/Healthy lab\n' \
  && bad "verify fails when an Application is OutOfSync" || ok "verify fails when an Application is OutOfSync"
run_verify 'other-showroom Synced/Healthy other\nother-prereqs Synced/Healthy other\n' \
  && bad "verify fails when only another lab's Applications exist" || ok "verify fails when only another lab's Applications exist"
FAKE_APPS='lab-v1-showroom Synced/Healthy lab-v1\nlab-v1-prereqs Synced/Healthy lab-v1\n' PATH="$fake:$PATH" LAB_NS=ns LAB_APP=lab.v1 \
  bash "$SCAFFOLD/automation/verify.sh" >/dev/null 2>&1 \
  && bad "a dot in LAB_APP matches only a literal dot" || ok "a dot in LAB_APP matches only a literal dot"
run_verify "${healthy}other-prereqs OutOfSync/Healthy other\n" \
  && ok "another lab's unhealthy Application does not fail this lab" || bad "another lab's unhealthy Application does not fail this lab"
run_verify 'lab Synced/Healthy lab\nlab-showroom Synced/Healthy lab\n' \
  && ok "verify passes for a lab with only the showroom child" || bad "verify passes for a lab with only the showroom child"
run_verify 'lab Synced/Healthy lab\nlab-showroom Synced/Healthy lab\nlab-operator Synced/Progressing lab\n' \
  && bad "verify fails when any lab child is unhealthy" || ok "verify fails when any lab child is unhealthy"
run_verify 'lab Synced/Healthy lab\n' \
  && bad "verify fails without the showroom child" || ok "verify fails without the showroom child"
run_verify "${healthy}lab-v2 Synced/Healthy lab-v2\nlab-v2-showroom OutOfSync/Degraded lab-v2\n" \
  && ok "a lab whose name extends this one's does not fail it" || bad "a lab whose name extends this one's does not fail it"
run_verify "lab OutOfSync/Degraded\nlab-showroom Synced/Healthy lab\n" \
  && bad "verify judges an unlabeled parent by name (RHDP)" || ok "verify judges an unlabeled parent by name (RHDP)"
FAKE_NO_ROUTE=1 run_verify "$healthy" \
  && bad "verify fails when the Showroom route is missing" || ok "verify fails when the Showroom route is missing"
FAKE_CURL_RC=22 run_verify "$healthy" \
  && bad "verify fails when the Showroom route does not answer" || ok "verify fails when the Showroom route does not answer"

n_label=$(grep -c 'app.kubernetes.io/part-of: t$' <<<"$apps" || true)
[[ $n_label == "$n_apps" ]] && ok "every child Application is labeled part-of its parent" || bad "every child Application is labeled part-of its parent ($n_label of $n_apps)"

# Argo CD's default controller gets admin in namespaces labeled managed-by; no cluster-admin needed.
prereqs=$(helm template t "$SCAFFOLD/automation/argocd/components/lab-prereqs" --set lab.namespace=ns1)
grep -q 'argocd.argoproj.io/managed-by: openshift-gitops' <<<"$prereqs" \
  && ok "lab namespace is labeled for the Argo CD instance" || bad "lab namespace is labeled for the Argo CD instance"
make -n -f "$SCAFFOLD/automation/Makefile" bootstrap | grep -q 'argocd.argoproj.io/managed-by=' \
  && ok "bootstrap labels the Showroom namespace first" || bad "bootstrap labels the Showroom namespace first"
n_retry=$(grep -c '^    retry:' <<<"$apps" || true)
[[ $n_retry == "$n_apps" ]] && ok "every child Application retries (grant arrives after the namespace)" || bad "every child Application retries ($n_retry of $n_apps)"

# Every image the Showroom child runs is pinned by digest, not a moving tag.
grep -q 'image: .*@sha256:' <<<"$apps" && ok "Showroom terminal image is digest-pinned" || bad "Showroom terminal image is digest-pinned"

# With no REVISION given, bootstrap deploys the revision values.yaml names (one source of truth).
lab=$(mktemp -d); cp -R "$SCAFFOLD/automation" "$lab/"
sed -i.bak 's/^  revision: main$/  revision: event-x/; s/^  namespace: CHANGE-ME$/  namespace: event-ns/' "$lab/automation/argocd/values.yaml"
make -n -f "$lab/automation/Makefile" bootstrap | grep -q 's|GIT_REVISION|event-x|' \
  && ok "bootstrap defaults to the revision in values.yaml" || bad "bootstrap defaults to the revision in values.yaml"

# bootstrap refuses to take over an existing Showroom namespace that is not this lab's.
cat > "$fake/oc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"get namespace showroom"*) [[ -n ${FAKE_NS_LABEL+x} ]] || exit 1; printf '%s' "$FAKE_NS_LABEL" ;;
  *"get namespace event-ns"*) [[ -n ${FAKE_LAB_NS_LABEL+x} ]] || exit 1; printf '%s' "$FAKE_LAB_NS_LABEL" ;;
  *ingresses.config*) printf 'apps.example.com' ;;
  *) echo "oc $*" >> "$FAKE_LOG" ;;
esac
SH
export FAKE_LOG="$fake/log"
run_boot() { : > "$FAKE_LOG"; PATH="$fake:$PATH" make -s -f "$lab/automation/Makefile" bootstrap >/dev/null 2>&1; }
FAKE_NS_LABEL='' run_boot && bad "bootstrap refuses a foreign showroom namespace" || ok "bootstrap refuses a foreign showroom namespace"
grep -q 'label namespace' "$FAKE_LOG" && bad "a refused bootstrap changes nothing" || ok "a refused bootstrap changes nothing"
FAKE_NS_LABEL='openshift-gitops' run_boot && ok "bootstrap reuses its own labeled namespace" || bad "bootstrap reuses its own labeled namespace"
(unset FAKE_NS_LABEL; run_boot) && ok "bootstrap creates a missing namespace" || bad "bootstrap creates a missing namespace"
FAKE_LAB_NS_LABEL='' run_boot && bad "bootstrap refuses a foreign lab namespace" || ok "bootstrap refuses a foreign lab namespace"
rm -rf "$lab"

exit "$errors"
