# Developer convenience targets for upcloud-charts.
# All targets run from the repository root and are idempotent.

CHARTS := upcloud-ccm upcloud-csi
HELM   ?= helm
KCONFORM ?= kubeconform

.PHONY: help lint template unittest test sync sync-csi sync-ccm check docs

help:
	@printf 'Available targets:\n'
	@awk '/^[a-zA-Z][a-zA-Z0-9_-]*:/ {print "  " $$0}' $(MAKEFILE_LIST) | sort -u

lint:
	@for c in $(CHARTS); do \
		echo "==> helm lint $$c"; \
		$(HELM) lint upcloud-charts/$$c --set ccmConfig.clusterID=ci-test --set credentials.username=ci --set credentials.password=ci; \
	done

template:
	@$(HELM) template ccm upcloud-charts/upcloud-ccm \
		--set ccmConfig.clusterID=ci-test \
		--set credentials.username=ci --set credentials.password=ci \
		> /tmp/upcloud-ccm.yaml
	@$(HELM) template csi upcloud-charts/upcloud-csi > /tmp/upcloud-csi.yaml
	@echo "rendered to /tmp/upcloud-{ccm,csi}.yaml"

unittest:
	@for c in $(CHARTS); do \
		echo "==> helm unittest $$c"; \
		$(HELM) unittest upcloud-charts/$$c; \
	done

test: lint template unittest

sync:
	@./upcloud-charts/scripts/sync-upstream.sh ccm
	@./upcloud-charts/scripts/sync-upstream.sh csi

sync-csi:
	@./upcloud-charts/scripts/sync-upstream.sh csi $(VERSION)

sync-ccm:
	@./upcloud-charts/scripts/sync-upstream.sh ccm $(VERSION)

check:
	@./upcloud-charts/scripts/sync-upstream.sh check

docs:
	@command -v helm-docs >/dev/null 2>&1 || { echo "install helm-docs: https://github.com/norwoodj/helm-docs"; exit 1; }
	@helm-docs --chart-search-root=upcloud-charts
