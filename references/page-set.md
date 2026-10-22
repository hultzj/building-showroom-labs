# Page set and module template

Pages live in `content/modules/ROOT/pages/`, numbered so files sort in reading
order. Every page must appear in `nav.adoc` (`check-lab.sh` enforces this). Put
drafts you want kept but unpublished in `content/extra/`, outside `pages/`.

| File | Sections, in order |
|---|---|
| `index.adoc` | One-line tagline · what the lab examines and why · numbered task list · Learning objectives · How to run the lab (command completion is not proof) · Choose your track (only with more than one track) · Lab map table: Module / Outcome / Time, with a track total · Technical model (each layer in one sentence, what none covers alone) · Start here |
| `01-overview.adoc` | Control questions (the customer's questions, answered with evidence) · The stack table: Layer / Component / Responsibility · the one distinction learners must be able to explain · Lab progression (one short `===` per module) · Interpretation guardrails (what is *not* claimed) |
| `02-details.adoc` | What you need: table by role · Provided by the facilitator · Verify the tools · Pre-flight: `oc whoami` plus one `oc auth can-i` per permission the exercises need, run from the Showroom terminal (for the namespace itself use `oc get namespace <ns>`: `can-i get namespaces/<ns>` answers `no` even when a RoleBinding allows it) · Access details table |
| `NN-module-MM-<slug>.adoc` | The module template below |
| `90-cleanup.adoc` | Participant-local cleanup first, then cluster-owner cleanup with a look-before-delete check |
| `91-reference.adoc` | What each upstream project contributes (links) · Evidence interpretation table: Topic / Supported interpretation / Required evidence · What this lab does not prove · Further reading |
| `92-facilitator-guide.adoc` | Provision (RHDP order with the repo URL; any other cluster: `make -C automation bootstrap`) · Verify every cluster (`make -C automation verify`) · Day of class |

`nav.adoc` groups modules under `.Track name (time)` captions and ends with
`.Wrap-up` (cleanup, reference) and `.Facilitators`.

## Module template

`assets/scaffold/content/modules/ROOT/pages/03-module-01-CHANGE-ME.adoc` is
the filled-in skeleton. Its parts, in order:

1. `= Module N: <Title>` and `:navtitle:`.
2. Opening paragraph: why this matters, ending on the customer question the module answers. Then one sentence on what the learner will do.
3. `.New to X?` collapsible glossary: up to five terms, one sentence each.
4. `== Technical context`: the mechanism the exercises prove. Define jargon in parentheses the first time it appears.
5. `== Learning objectives`: verb-first bullets.
6. `== Exercise K: <verb phrase>`, each with:
   - one or two sentences on what changes and why;
   - a `[source,bash,role="execute",subs="attributes+"]` block;
   - `Expected result:` followed by the observed field or value and what it proves, then `// UNVERIFIED` until verified live;
   - `In short:` a one-line takeaway (for key steps);
   - optionally a `.The scripted assertion for this exercise` `[%collapsible]` block: a non-execute bash block that exits non-zero on failure;
   - optionally `GUI view:` where to see the same evidence in the console tab.
   At least one exercise per module is a negative control (the action that must fail) or a break-and-restore.
7. `== Evidence checkpoint`: questions the learner should now be able to answer, then a `.Answer key` collapsible.
8. `Proceed to xref:<next page>[<title>].`

## AsciiDoc idioms

- Participant commands: `[source,bash,role="execute",subs="attributes+"]`. Showroom adds a click-to-run button to `role="execute"` blocks.
- Every block that shows a lab name uses `subs="attributes+"`, including non-execute blocks. Without it `{name}` renders literally with no warning; `check-lab.sh` catches that in `www/`.
- With `subs="attributes+"`, `{name}` is an attribute. Write shell variables as `$VAR`, never `${VAR}`, and escape literal braces (`'%\{http_code\}'`). `attribute-missing: warn` plus `--log-failure-level warn` fails the build on a mistake.
- Long waits, PID-checked kills and full scripted checks go in `[%collapsible]` blocks so the main path stays short.
- Admonitions are rare: `[IMPORTANT]` for safety boundaries, `[CAUTION]` for destructive or irreversible steps.
- No Antora extensions: the field-content Showroom builder image (`quay.io/rhpds/antora`) has none, so `[mermaid]` and tabs fail or render raw. Show a flow as a table (source / destination / result / why) or a numbered list. No screenshots; they drift.
- Links that leave the site: `link:https://...[text^]`. Cross-page: `xref:file.adoc[text]`.
