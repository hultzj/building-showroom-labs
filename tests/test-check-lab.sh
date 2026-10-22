#!/usr/bin/env bash
# Self-check for scaffold/scripts/check-lab.sh: each case must pass or fail as stated.
set -euo pipefail
SCAFFOLD="$(cd "$(dirname "$0")/../assets/scaffold" && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
errors=0

fresh() {
  rm -rf "$work/lab" && mkdir "$work/lab" && cp -R "$SCAFFOLD/." "$work/lab/"
  # Fill every placeholder, as an author would.
  mv "$work"/lab/content/modules/ROOT/pages/03-module-01-{CHANGE-ME,intro}.adoc
  grep -rlI 'CHANGE-ME' "$work/lab" | grep -v check-lab.sh | while read -r f; do
    sed -i.bak 's/03-module-01-CHANGE-ME/03-module-01-intro/g; s/CHANGE-ME/filled/g' "$f" && rm "$f.bak"
  done
  # Stand-in for `npm run build` output.
  mkdir -p "$work/lab/www/modules" && echo '<code>oc -n netpol-demo get pods</code>' > "$work/lab/www/modules/index.html"
}
expect() { # expect pass|fail "<case>" <args...>
  local want=$1 name=$2; shift 2
  if bash "$work/lab/scripts/check-lab.sh" "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want, got $got)"; errors=1; fi
}
page="$work/lab/content/modules/ROOT/pages/03-module-01-intro.adoc"

rm -rf "$work/lab" && mkdir "$work/lab" && cp -R "$SCAFFOLD/." "$work/lab/"
expect fail "untouched scaffold fails on CHANGE-ME" --draft

fresh
expect pass "filled scaffold passes in draft mode" --draft
expect fail "filled scaffold fails strict mode while steps are UNVERIFIED"

fresh
find "$work/lab/content" -name '*.adoc' -exec sed -i.bak '/^\/\/ UNVERIFIED$/d' {} + && find "$work/lab" -name '*.bak' -delete
expect pass "strict mode passes once every step is verified"

fresh
awk 'BEGIN{d=0} /^Expected result/ && !d {d=1; next} {print}' "$page" > "$page.new" && mv "$page.new" "$page"
expect fail "execute block followed by another block without Expected result" --draft

fresh
printf '\n[source,bash,role="execute"]\n----\ntrue\n----\n' >> "$work/lab/content/modules/ROOT/pages/91-reference.adoc"
expect fail "execute block at end of file without Expected result" --draft

fresh
printf '\n[source,bash,role=execute]\n----\ntrue\n----\n' >> "$work/lab/content/modules/ROOT/pages/91-reference.adoc"
expect fail "unquoted role=execute block without Expected result" --draft

fresh
echo '<code>oc -n {lab_namespace} get pods</code>' > "$work/lab/www/modules/x.html"
expect fail "defined attribute rendered literally in the HTML" --draft

fresh
rm -rf "$work/lab/www"
expect fail "no build output to inspect" --draft

fresh
sed -i.bak '/^== Evidence checkpoint$/d' "$page" && rm "$page.bak"
expect fail "module without Evidence checkpoint" --draft

fresh
printf '= Orphan\n' > "$work/lab/content/modules/ROOT/pages/50-orphan.adoc"
expect fail "page missing from nav" --draft

fresh
rm "$page" && sed -i.bak '/03-module-01-intro/d' "$work"/lab/content/modules/ROOT/{nav.adoc,pages/02-details.adoc} && find "$work/lab" -name '*.bak' -delete
expect fail "no module pages at all" --draft

exit "$errors"
