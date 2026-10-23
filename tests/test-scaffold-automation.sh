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
grep -q 's|GIT_REVISION|event-2026|' <<<"$(make -n -f "$SCAFFOLD/automation/Makefile" bootstrap REVISION=event-2026)" \
  && ok "make bootstrap REVISION= sets the parent's revision" || bad "make bootstrap REVISION= sets the parent's revision"
grep -q 'targetRevision: "GIT_REVISION"' "$SCAFFOLD/automation/bootstrap.yaml" \
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
printf '#!/usr/bin/env bash\n[[ " $* " =~ \\ -[a-zA-Z]*I ]] && printf "HTTP/1.1 200 OK\\r\\n"\nexit "${FAKE_CURL_RC:-0}"\n' > "$fake/curl"
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
run_verify 'lab-showroom Synced/Healthy lab\n' \
  && bad "verify fails when the parent Application is missing" || ok "verify fails when the parent Application is missing"
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
grep -q 'argocd.argoproj.io/managed-by=' <<<"$(make -n -f "$SCAFFOLD/automation/Makefile" bootstrap)" \
  && ok "bootstrap labels the Showroom namespace first" || bad "bootstrap labels the Showroom namespace first"
n_retry=$(grep -c '^    retry:' <<<"$apps" || true)
[[ $n_retry == "$n_apps" ]] && ok "every child Application retries (grant arrives after the namespace)" || bad "every child Application retries ($n_retry of $n_apps)"

# verify.sh: every external (url:) tab is an iframe and only renders if its target allows framing.
lab=$(mktemp -d); cp -R "$SCAFFOLD/." "$lab/"
cat > "$fake/oc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *ingresses.config*) printf 'apps.example.com' ;;
  *applications.argoproj.io*) printf 'lab Synced/Healthy lab\nlab-showroom Synced/Healthy lab\n' ;;
  *route*) printf 'showroom.example.test' ;;
esac
SH
cat > "$fake/curl" <<'SH'
#!/usr/bin/env bash
[[ " $* " =~ \ -[a-zA-Z]*I ]] || exit 0
echo "$*" >> "$FAKE_CURL_LOG"
[[ -n ${FAKE_REDIRECT:-} ]] && printf 'HTTP/1.1 302 Found\r\nlocation: https://x\r\n\r\n'
printf 'HTTP/1.1 %s\r\n' "${FAKE_STATUS:-200 OK}"
[[ -n ${FAKE_XFO:-} ]] && printf 'x-frame-options: %s\r\n' "$FAKE_XFO"
[[ -n ${FAKE_CSP:-} ]] && printf 'content-security-policy: %s\r\n' "$FAKE_CSP"
printf 'content-security-policy-report-only: frame-ancestors '"'"'none'"'"'\r\n'
exit 0
SH
chmod +x "$fake/oc" "$fake/curl"
export FAKE_CURL_LOG="$fake/curl.log"
cverify() { : > "$FAKE_CURL_LOG"; env "$@" PATH="$fake:$PATH" LAB_NS=ns LAB_APP=lab bash "$lab/automation/verify.sh" > "$fake/verify.out" 2>&1; }
tabfail() { grep -q 'FAIL: Showroom tab' "$fake/verify.out"; }
cverify FAKE_XFO=DENY && bad "verify exits non-zero when a tab target refuses framing (X-Frame-Options)" || { tabfail && ok "verify exits non-zero when a tab target refuses framing (X-Frame-Options)" || bad "verify exits non-zero when a tab target refuses framing (X-Frame-Options)"; }
cverify FAKE_CSP="default-src 'self'; frame-ancestors 'self'" && bad "an enforced CSP frame-ancestors also refuses framing" || ok "an enforced CSP frame-ancestors also refuses framing"
cverify FAKE_STATUS='503 Service Unavailable' && bad "a tab target answering 503 fails" || ok "a tab target answering 503 fails"
cverify FAKE_REDIRECT=1 FAKE_XFO=DENY && bad "headers are judged after following redirects" || ok "headers are judged after following redirects"
cverify && grep -q 'PASS: Showroom tab' "$fake/verify.out" && ok "a frameable tab target passes (report-only CSP ignored)" || bad "a frameable tab target passes (report-only CSP ignored)"
grep -q 'https://console-openshift-console.apps.example.com' "$FAKE_CURL_LOG" && ok "\${DOMAIN} in tab URLs is filled in from the cluster" || bad "\${DOMAIN} in tab URLs is filled in from the cluster"
sed -i.bak "s|url: 'https://console-openshift-console.\${DOMAIN}'|url: 'https://my-console.example.org'|" "$lab/ui-config.yml"
cverify FAKE_XFO=DENY || true; tabfail && ok "a tab on a custom hostname is still checked" || bad "a tab on a custom hostname is still checked"
sed -i.bak '/OpenShift Console/,+1d' "$lab/ui-config.yml"
cverify FAKE_XFO=DENY || true; grep -q 'Showroom tab' "$fake/verify.out" && bad "no tab check when ui-config has no url tabs" || ok "no tab check when ui-config has no url tabs"
rm -rf "$lab"
grep -qx '.playwright-mcp/' "$SCAFFOLD/.gitignore" && ok "Playwright auth state is gitignored" || bad "Playwright auth state is gitignored"
grep -q 'feature_maturity:' "$SCAFFOLD/content/antora.yml" && grep -q 'ifeval::\["{feature_maturity}" == "TP"\]' "$SCAFFOLD/content/modules/ROOT/pages/index.adoc" \
  && grep -q 'ifeval::\["{feature_maturity}" == "DP"\]' "$SCAFFOLD/content/modules/ROOT/pages/index.adoc" && grep -q 'Developer Preview' "$SCAFFOLD/content/modules/ROOT/pages/index.adoc" \
  && ok "scaffold carries feature_maturity and its TP/DP banners" || bad "scaffold carries feature_maturity and its TP/DP banners"

# Every image the Showroom child runs is pinned by digest, not a moving tag.
grep -q 'image: .*@sha256:' <<<"$apps" && ok "Showroom terminal image is digest-pinned" || bad "Showroom terminal image is digest-pinned"

# --- make bootstrap: revision default, ownership guard, input validation (fake oc, real helm) ---
lab=$(mktemp -d); cp -R "$SCAFFOLD/automation" "$lab/"
V="$lab/automation/argocd/values.yaml"
sed -i.bak 's/^  revision: main$/  revision: event-x/; s/^  namespace: CHANGE-ME$/  namespace: event-ns/' "$V"
sed -i.bak 's/CHANGE-ME-lab/my-lab/' "$lab/automation/bootstrap.yaml"  # an author's real lab name
grep -q 'event-x' <<<"$(make -n -f "$lab/automation/Makefile" bootstrap 2>/dev/null)" \
  && ok "bootstrap defaults to the revision in values.yaml" || bad "bootstrap defaults to the revision in values.yaml"
APP=my-lab
cat > "$fake/oc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"get namespace "*)
    ns=$(awk '{for (i = 1; i <= NF; i++) if ($i == "namespace") {print $(i + 1); exit}}' <<<"$*")
    [[ -n ${FAKE_NS_ERROR:-} ]] && { echo "Error from server (Forbidden)" >&2; exit 1; }
    if [[ -f "$FAKE_STATE/$ns" ]]; then printf '%s/%s' "$ns" "$(cat "$FAKE_STATE/$ns")"; exit 0; fi
    eval "printf '%s' \"\${FAKE_NS_$(tr - _ <<<"$ns"):-}\"" ;;
  "create -f -")
    m=$(cat); ns=$(awk '$1 == "name:" {print $2; exit}' <<<"$m"); echo "oc create namespace $ns" >> "$FAKE_LOG"
    [[ "create namespace $ns" != *"${FAKE_CREATE_FAIL:-@none@}"* ]] || exit 1
    [[ -n ${FAKE_STATE:-} ]] && awk -F': ' '/app.kubernetes.io\/part-of/ {print $2}' <<<"$m" > "$FAKE_STATE/$ns"; exit 0 ;;
  *ingresses.config*) printf 'apps.example.com' ;;
  "apply -f -") cat > /dev/null; echo "oc apply" >> "$FAKE_LOG" ;;
  "create namespace "*) echo "oc $*" >> "$FAKE_LOG"; [[ "$*" != *"${FAKE_CREATE_FAIL:-@none@}"* ]] ;;
  *) echo "oc $*" >> "$FAKE_LOG" ;;
esac
SH
cat > "$fake/git" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"rev-parse HEAD"*) echo "${FAKE_HEAD:-c0ffee}" ;;
  *"status --porcelain"*) printf '%s' "${FAKE_UNTRACKED:-}" ;;
  *"ls-remote"*) [[ -n ${FAKE_NO_REMOTE:-} ]] || printf '%s\trefs/heads/x\n' "${FAKE_REMOTE:-c0ffee}" ;;
  *"diff --quiet"*) [[ -z ${FAKE_DIRTY:-} ]] ;;
esac
SH
chmod +x "$fake/git"
export FAKE_LOG="$fake/log" FAKE_STATE=""
boot() { : > "$FAKE_LOG"; env "$@" PATH="$fake:$PATH" make -s -f "$lab/automation/Makefile" bootstrap >/dev/null 2>&1; }
mutated() { grep -qE 'oc (apply|label|create)' "$FAKE_LOG"; }
boot && mutated && ok "bootstrap proceeds when the namespaces do not exist" || bad "bootstrap proceeds when the namespaces do not exist"
boot FAKE_NS_showroom="showroom/$APP" FAKE_NS_event_ns="event-ns/$APP" && ok "bootstrap reuses namespaces this lab owns" || bad "bootstrap reuses namespaces this lab owns"
boot FAKE_NS_showroom="showroom/" && bad "bootstrap refuses an unlabeled showroom namespace" || ok "bootstrap refuses an unlabeled showroom namespace"
mutated && bad "a refused bootstrap changes nothing" || ok "a refused bootstrap changes nothing"
boot FAKE_NS_event_ns="event-ns/other-lab" && bad "bootstrap refuses another lab's namespace" || ok "bootstrap refuses another lab's namespace"
boot FAKE_NS_showroom="showroom/other-lab" && bad "a missing lab namespace plus a foreign showroom is refused" || ok "a missing lab namespace plus a foreign showroom is refused"
mutated && bad "... and nothing is created first" || ok "... and nothing is created first"
export FAKE_STATE="$fake/state"; mkdir -p "$FAKE_STATE"
boot FAKE_CREATE_FAIL="namespace showroom" && bad "bootstrap fails when a namespace create fails" || ok "bootstrap fails when a namespace create fails"
[[ $(cat "$FAKE_STATE/event-ns" 2>/dev/null) == "$APP" ]] && ok "the namespace created before the failure already carries the lab's label" || bad "the namespace created before the failure already carries the lab's label"
boot && ! grep -q 'create namespace event-ns' "$FAKE_LOG" && ok "a retry after a partial failure succeeds without re-creating" || bad "a retry after a partial failure succeeds without re-creating"
rm -rf "$FAKE_STATE"; export FAKE_STATE=""
boot FAKE_NS_ERROR=1 && bad "bootstrap stops when a namespace lookup fails" || ok "bootstrap stops when a namespace lookup fails"
mutated && bad "a failed lookup changes nothing" || ok "a failed lookup changes nothing"
sed -i.bak 's/^  namespace: showroom$/  namespace: team-guide/' "$V"
boot FAKE_NS_team_guide="team-guide/" && bad "the guard checks the Showroom namespace values.yaml deploys to" || ok "the guard checks the Showroom namespace values.yaml deploys to"
printf '\nprereqs:\n  enabled: false\n' >> "$V"
boot FAKE_NS_event_ns="event-ns/" && ok "a namespace no child deploys to is not guarded (prereqs off)" || bad "a namespace no child deploys to is not guarded (prereqs off)"
boot REVISION='event/a&b' && bad "bootstrap rejects a revision with unsafe characters" || ok "bootstrap rejects a revision with unsafe characters"
boot REVISION=other-branch && bad "bootstrap refuses a REVISION that differs from gitops.revision" || ok "bootstrap refuses a REVISION that differs from gitops.revision"
boot FAKE_REMOTE=deadbeef && bad "bootstrap refuses when the checkout is not the pushed revision" || ok "bootstrap refuses when the checkout is not the pushed revision"
mutated && bad "an unpushed checkout changes nothing" || ok "an unpushed checkout changes nothing"
boot FAKE_DIRTY=1 && bad "bootstrap refuses local changes under automation/" || ok "bootstrap refuses local changes under automation/"
boot FAKE_UNTRACKED='?? automation/argocd/.helmignore' && bad "bootstrap refuses untracked or ignored files under automation/" || ok "bootstrap refuses untracked or ignored files under automation/"
boot FAKE_NO_REMOTE=1 && bad "bootstrap refuses a revision missing on the remote" || ok "bootstrap refuses a revision missing on the remote"
boot && grep -q '^oc create namespace team-guide$' "$FAKE_LOG" && ! grep -q 'dry-run' "$FAKE_LOG" \
  && ok "missing namespaces are created atomically (no apply-and-adopt)" || bad "missing namespaces are created atomically (no apply-and-adopt)"
sed -i.bak 's/^  revision: event-x$/  revision: "event-x"/' "$V"
boot && ok "a quoted gitops.revision works by default" || bad "a quoted gitops.revision works by default"
boot REVISION=event-x && ok "a quoted gitops.revision matches an explicit REVISION" || bad "a quoted gitops.revision matches an explicit REVISION"
rm -rf "$lab"
ruby -ryaml -e 'v = YAML.safe_load(File.read(ARGV[0]).gsub("GIT_REVISION", "2026"))["spec"]["source"]["targetRevision"]; exit(v.is_a?(String) ? 0 : 1)' "$SCAFFOLD/automation/bootstrap.yaml" \
  && ok "a numeric revision stays a string in targetRevision" || bad "a numeric revision stays a string in targetRevision"
helm template t "$SCAFFOLD/automation/argocd" --set deployer.domain=x --set-string gitops.revision=2026 |
  ruby -ryaml -e 'YAML.load_stream(STDIN.read).compact.each { |d| r = d.dig("spec", "source", "targetRevision"); exit 1 unless r.nil? || r.is_a?(String) }' \
  && ok "child Applications keep a numeric revision a string" || bad "child Applications keep a numeric revision a string"

# The default terminal Role grants nothing that runs code in pods.
helm template t "$SCAFFOLD/automation/argocd/components/lab-prereqs" --set lab.namespace=ns1 | grep -qE '^ *resources:.*pods/exec' \
  && bad "default terminal Role has no pods/exec" || ok "default terminal Role has no pods/exec"
helm template t "$SCAFFOLD/automation/argocd" --set deployer.domain=x >/dev/null
helm template t "$SCAFFOLD/automation/argocd/components/lab-prereqs" --set lab.namespace=ns1 --set partOf=t | grep -q 'app.kubernetes.io/part-of: t' \
  && ok "lab namespace carries the lab's part-of label" || bad "lab namespace carries the lab's part-of label"

exit "$errors"
