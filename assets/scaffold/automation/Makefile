SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
GITOPS_NS ?= openshift-gitops
SHOWROOM_NS ?= showroom
REVISION ?= main

.PHONY: help bootstrap status verify teardown

help:
	@printf '%s\n' \
	  '  make bootstrap   Deploy the lab through OpenShift GitOps (clusters without an RHDP order)' \
	  '  make status      Show sync and health of the lab Applications' \
	  '  make verify      PASS/FAIL readiness checks for class' \
	  '  make teardown    Delete the lab Applications and everything they created'

bootstrap:
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
