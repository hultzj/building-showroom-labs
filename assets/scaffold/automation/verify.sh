#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-openshift-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-CHANGE-ME}
# The parent Application name; children are named <LAB_APP>-<component>.
LAB_APP=${LAB_APP:-CHANGE-ME-lab}
# Check as the participant identity (environments.md), not as the facilitator: the terminal
# ServiceAccount below, or a participant user (--as userN --as-group system:authenticated --as-group system:authenticated:oauth).
TERMINAL_SA="system:serviceaccount:${SHOWROOM_NS}:showroom"
failed=0

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failed=1
  fi
}

apps_synced_healthy() {
  local apps
  apps=$(oc -n "$GITOPS_NS" get applications.argoproj.io \
    -l demo.redhat.com/application=field-content \
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status}/{.status.health.status} {.metadata.labels.app\.kubernetes\.io/part-of}{"\n"}{end}') || return 1
  # This lab's Applications carry part-of=<LAB_APP>: the showroom child must exist, and all must be Synced/Healthy.
  awk -v app="$LAB_APP" '
    $1 != app && $3 != app { next }  # the parent by name: RHDP creates it without the label
    $1 == app { p = 1 }  # the parent: missing children or a missing parent must fail
    $1 == app "-showroom" { s = 1 }
    $2 != "Synced/Healthy" { bad = 1 }
    END { exit !(p && s && !bad) }
  ' <<<"$apps"
}

showroom_answers() {
  local host
  host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}') || return 1
  curl -fsk --max-time 10 -o /dev/null "https://$host"
}

# The Showroom console tab is an iframe; a console that sends X-Frame-Options (DENY by default)
# renders as a blank tab. RHDP orders embed the console; elsewhere, drop the tab or get the owner's OK.
console_frameable() {
  local url headers
  url=$(oc whoami --show-console) || return 1
  headers=$(curl -skI --max-time 10 "$url") || return 1
  ! grep -qi '^x-frame-options:' <<<"$headers"
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
if grep -q 'console-openshift-console' "$(dirname "$0")/../ui-config.yml" 2>/dev/null; then
  check "Showroom console tab can embed the console (no X-Frame-Options)" console_frameable
fi
# CHANGE-ME: one check per prerequisite the exercises assume, e.g.
# check "demo workload ready" oc -n "$LAB_NS" rollout status deploy/<name> --timeout=10s
# check "terminal can <verb> <resource>" oc auth can-i <verb> <resource> -n "$LAB_NS" --as "$TERMINAL_SA"

exit "$failed"
