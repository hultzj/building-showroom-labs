#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-openshift-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-CHANGE-ME}
# Participants run every step as this identity; check as it, not as the facilitator.
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
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status}/{.status.health.status}{"\n"}{end}') || return 1
  # Both children must exist, and every Application must be Synced/Healthy.
  grep -q -- '-showroom ' <<<"$apps" && grep -q -- '-prereqs ' <<<"$apps" &&
    ! grep -qv ' Synced/Healthy$' <<<"$apps"
}

showroom_answers() {
  local host
  host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}') || return 1
  curl -fsk -o /dev/null "https://$host"
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
# CHANGE-ME: one check per prerequisite the exercises assume, e.g.
# check "demo workload ready" oc -n "$LAB_NS" rollout status deploy/<name> --timeout=10s
# check "terminal can <verb> <resource>" oc auth can-i <verb> <resource> -n "$LAB_NS" --as "$TERMINAL_SA"

exit "$failed"
