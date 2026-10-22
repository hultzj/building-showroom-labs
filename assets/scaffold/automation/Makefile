SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GITOPS_NS ?= openshift-gitops
# The parent Application name, from bootstrap.yaml; every namespace this lab creates carries part-of=<LAB_APP>.
LAB_APP := $(shell awk '/^metadata:/ {m = 1} m && $$1 == "name:" {print $$2; exit}' "$(AUTOMATION_DIR)/bootstrap.yaml" 2>/dev/null)
# Defaults to the revision values.yaml names, so an event branch deploys itself.
REVISION ?= $(shell awk '/^gitops:/ {g = 1} g && $$1 == "revision:" {print $$2; exit}' "$(AUTOMATION_DIR)/argocd/values.yaml" 2>/dev/null)

.PHONY: help bootstrap status verify teardown

help:
	@printf '%s\n' \
	  '  make bootstrap   Deploy the lab through OpenShift GitOps (clusters without an RHDP order)' \
	  '  make status      Show sync and health of the lab Applications' \
	  '  make verify      PASS/FAIL readiness checks for class' \
	  '  make teardown    Delete the lab Applications and everything they created'

# bootstrap deploys exactly what Argo CD will sync: it refuses unless this checkout is the pushed
# REVISION (no local changes) and REVISION matches gitops.revision. It then guards every namespace a
# child Application deploys into (Argo CD would adopt a foreign one and teardown would delete it),
# creates each missing one atomically and labels it at once (so a partial failure stays retryable),
# so Argo CD may deploy there. No comments inside
# the recipe: after backslash-newline joining, a shell comment would swallow the rest of it.
bootstrap:
	@set -euo pipefail; \
	[[ "$(REVISION)" =~ ^[A-Za-z0-9._/-]+$$ ]] || { echo "REVISION '$(REVISION)' has unsafe characters" >&2; exit 1; }; \
	vrev=$$(awk '/^gitops:/ {g = 1} g && $$1 == "revision:" {print $$2; exit}' "$(AUTOMATION_DIR)/argocd/values.yaml"); \
	[[ "$$vrev" == "$(REVISION)" ]] || { echo "REVISION $(REVISION) differs from gitops.revision ($$vrev) in values.yaml; set it on that branch" >&2; exit 1; }; \
	head=$$(git -C "$(AUTOMATION_DIR)" rev-parse HEAD); \
	remote=$$(git -C "$(AUTOMATION_DIR)" ls-remote origin "refs/heads/$(REVISION)" | cut -f1); \
	if [[ -z "$$remote" || "$$remote" != "$$head" ]] || ! git -C "$(AUTOMATION_DIR)" diff --quiet HEAD -- .; then \
	  echo "check out the pushed $(REVISION) with no local changes under automation/: Argo CD deploys the remote" >&2; exit 1; fi; \
	domain=$$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'); test -n "$$domain"; \
	apps=$$(helm template "$(LAB_APP)" "$(AUTOMATION_DIR)/argocd" --set deployer.domain="$$domain"); \
	nss=$$(awk '$$1 == "destination:" {d = 1} d && $$1 == "namespace:" {print $$2; d = 0}' <<<"$$apps" | sort -u); \
	missing=""; \
	for ns in $$nss; do \
	  state=$$(oc get namespace "$$ns" --ignore-not-found -o jsonpath='{.metadata.name}/{.metadata.labels.app\.kubernetes\.io/part-of}'); \
	  case "$$state" in "") missing="$$missing $$ns" ;; "$$ns/$(LAB_APP)") ;; \
	    *) echo "namespace $$ns exists and is not this lab's ($(LAB_APP)); rename it in values.yaml, content/antora.yml and verify.sh" >&2; exit 1 ;; esac; \
	done; \
	for ns in $$nss; do \
	  case " $$missing " in *" $$ns "*) oc create namespace "$$ns" ;; esac; \
	  oc label namespace "$$ns" "argocd.argoproj.io/managed-by=$(GITOPS_NS)" "app.kubernetes.io/part-of=$(LAB_APP)" --overwrite; \
	done; \
	sed "s|DEPLOYER_DOMAIN|$$domain|; s|GIT_REVISION|$(REVISION)|" "$(AUTOMATION_DIR)/bootstrap.yaml" | oc apply -f -

status:
	oc -n $(GITOPS_NS) get applications.argoproj.io -l demo.redhat.com/application=field-content

verify:
	GITOPS_NS=$(GITOPS_NS) bash "$(AUTOMATION_DIR)/verify.sh"

teardown:
	oc delete -f "$(AUTOMATION_DIR)/bootstrap.yaml" --ignore-not-found --wait=true
