#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-openshift-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-CHANGE-ME}
# The parent Application name; children are named <LAB_APP>-<component>. An RHDP order always names
# it field-content; make bootstrap uses bootstrap.yaml's name.
if [[ -z ${LAB_APP:-} ]]; then
  LAB_APP=CHANGE-ME-lab
  [[ -n $(oc -n "$GITOPS_NS" get applications.argoproj.io field-content -o name --ignore-not-found 2>/dev/null) ]] &&
    LAB_APP=field-content
fi
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

# Every url: tab in ui-config.yml is an iframe: its target must answer 2xx (after redirects) and allow
# the Showroom origin to frame it. A default OpenShift console sends X-Frame-Options: DENY and renders
# as a blank tab. RHDP's embedding model drops that header and sets frame-ancestors to the Showroom
# origins (often https://*.apps.<domain>). Report-only CSP is ignored.
# Usage: frameable <url> <showroom host>
frameable() {
  local headers last csp
  headers=$(curl -skIL --max-time 10 "$1") || return 1
  last=$(awk '/^HTTP\// {b = ""} {b = b $0 "\n"} END {printf "%s", b}' <<<"$headers" | tr -d '\r')
  grep -qE '^HTTP/[0-9.]+ 2[0-9][0-9]' <<<"$last" || return 1
  ! grep -qi '^x-frame-options:' <<<"$last" || return 1
  # Browsers enforce every policy, so every enforced frame-ancestors directive (across headers and
  # comma-separated policies) must admit the Showroom origin: *, a *.suffix wildcard covering its host,
  # or the host itself. 'self' never matches: Showroom is on another host.
  csp=$(grep -i '^content-security-policy:' <<<"$last" | cut -d: -f2- || true)  # none is fine
  tr ',;' '\n\n' <<<"$csp" | awk -v host="$(tr '[:upper:]' '[:lower:]' <<<"${2:-}")" '
    {d = tolower($0); sub(/^[ \t]+/, "", d)}
    d ~ /^frame-ancestors/ {
      n = split(d, t, /[ \t]+/); allowed = 0
      for (i = 2; i <= n; i++) {
        tok = t[i]; sub(/^https?:\/\//, "", tok)
        # Browsers match the ancestor origin (root path): only an empty path or "/" can match it.
        if (tok ~ /\//) { path = tok; sub(/^[^\/]*/, "", path); if (path != "/") continue; sub(/\/$/, "", tok) }
        # A port matches the HTTPS Showroom origin only when it is :443 or :*.
        if (tok ~ /:[^:]+$/) { p = tok; sub(/^.*:/, "", p); if (p != "443" && p != "*") continue; sub(/:[^:]+$/, "", tok) }
        if (tok == "*") allowed = 1
        else if (substr(tok, 1, 2) == "*." && host != "") {
          suf = substr(tok, 2)
          if (length(host) > length(suf) && substr(host, length(host) - length(suf) + 1) == suf) allowed = 1
        } else if (host != "" && tok == host) allowed = 1
      }
      if (!allowed) bad = 1
    }
    END {exit bad}'
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
ui_config="$(dirname "$0")/../ui-config.yml"
if [[ ! -r $ui_config ]]; then
  check "ui-config.yml is readable (its url: tabs are checked)" false
else
  domain=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  showroom_host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}' 2>/dev/null || true)
  for url in $(awk '{sub(/^[[:space:]]*-[[:space:]]*/, "")} $1 == "url:" {print $2}' "$ui_config" | tr -d "'\""); do
    url=$(sed "s|\${DOMAIN}|$domain|g" <<<"$url")
    check "Showroom tab $url can embed (2xx, framing allowed)" frameable "$url" "$showroom_host"
  done
fi
# CHANGE-ME: one check per prerequisite the exercises assume, e.g.
# check "demo workload ready" oc -n "$LAB_NS" rollout status deploy/<name> --timeout=10s
# check "terminal can <verb> <resource>" oc auth can-i <verb> <resource> -n "$LAB_NS" --as "$TERMINAL_SA"
# check "ansible Job completed" oc -n <runner-ns> wait --for=condition=Complete job/<name> --timeout=10s

exit "$failed"
