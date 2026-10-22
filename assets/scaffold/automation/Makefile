SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GITOPS_NS ?= openshift-gitops
SHOWROOM_NS ?= showroom
# Defaults to the revision values.yaml names, so an event branch deploys itself.
REVISION ?= $(shell awk '/^gitops:/ {g = 1} g && $$1 == "revision:" {print $$2; exit}' "$(AUTOMATION_DIR)/argocd/values.yaml" 2>/dev/null)

.PHONY: help bootstrap status verify teardown

help:
	@printf '%s\n' \
	  '  make bootstrap   Deploy the lab through OpenShift GitOps (clusters without an RHDP order)' \
	  '  make status      Show sync and health of the lab Applications' \
	  '  make verify      PASS/FAIL readiness checks for class' \
	  '  make teardown    Delete the lab Applications and everything they created'

bootstrap:
	@# Refuse to take over a namespace of that name that is not this lab's (another Showroom on a shared cluster).
	@if label=$$(oc get namespace "$(SHOWROOM_NS)" -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}' 2>/dev/null) && \
	    [ "$$label" != "$(GITOPS_NS)" ]; then \
	  echo "namespace $(SHOWROOM_NS) exists and is not this lab's; choose another with SHOWROOM_NS=..." >&2; exit 1; fi
	# The upstream Showroom chart creates its namespace unlabeled; label it first so Argo CD may deploy there.
	oc create namespace "$(SHOWROOM_NS)" --dry-run=client -o yaml | oc apply -f - && \
	  oc label namespace "$(SHOWROOM_NS)" "argocd.argoproj.io/managed-by=$(GITOPS_NS)" --overwrite
	domain=$$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}') && \
	  test -n "$$domain" && \
	  sed "s|DEPLOYER_DOMAIN|$$domain|; s|GIT_REVISION|$(REVISION)|" "$(AUTOMATION_DIR)/bootstrap.yaml" | oc apply -f -

status:
	oc -n $(GITOPS_NS) get applications.argoproj.io -l demo.redhat.com/application=field-content

verify:
	GITOPS_NS=$(GITOPS_NS) bash "$(AUTOMATION_DIR)/verify.sh"

teardown:
	oc delete -f "$(AUTOMATION_DIR)/bootstrap.yaml" --ignore-not-found --wait=true
