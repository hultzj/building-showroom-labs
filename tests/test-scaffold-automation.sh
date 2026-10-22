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

# Paths with spaces must reach the shell as one argument.
dir='/tmp/lab checkout/automation'
for target in verify bootstrap teardown; do
  cmd=$(make -n -f "$SCAFFOLD/automation/Makefile" "$target" AUTOMATION_DIR="$dir")
  grep -Fq "\"$dir/" <<<"$cmd" && ok "make $target quotes its paths" || bad "make $target quotes its paths: $cmd"
done

# verify.sh must fail when an expected child Application is missing.
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
cat > "$fake/oc" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *applications.argoproj.io*) printf '%b' "$FAKE_APPS" ;;
  *route*) printf 'showroom.example.test' ;;
esac
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/curl"
chmod +x "$fake/oc" "$fake/curl"
run_verify() { FAKE_APPS=$1 PATH="$fake:$PATH" LAB_NS=ns bash "$SCAFFOLD/automation/verify.sh" >/dev/null 2>&1; }
run_verify 'lab Synced/Healthy\nlab-showroom Synced/Healthy\nlab-prereqs Synced/Healthy\n' \
  && ok "verify passes with every Application Synced/Healthy" || bad "verify passes with every Application Synced/Healthy"
run_verify 'lab-showroom Synced/Healthy\n' \
  && bad "verify fails when the prereqs Application is missing" || ok "verify fails when the prereqs Application is missing"
run_verify 'lab-showroom Synced/Healthy\nlab-prereqs OutOfSync/Healthy\n' \
  && bad "verify fails when an Application is OutOfSync" || ok "verify fails when an Application is OutOfSync"

exit "$errors"
