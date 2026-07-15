# Developer convenience targets for charts/.
#
# All targets assume `make` is invoked with this Makefile's directory as the
# working directory. Both `cd charts && make lint` and
# `make -C charts lint` (from the repo root) work.

CHARTS   := upcloud-ccm upcloud-csi cloudflare-operator digitalocean-ccm digitalocean-csi psono
HELM     ?= helm
KCONFORM ?= kubeconform

.PHONY: help lint template unittest test secret-scan \
        sync sync-ccm sync-csi sync-cloudflare sync-do-ccm sync-do-csi check docs

help:
	@printf 'Available targets:\n'
	@awk '/^[a-zA-Z][a-zA-Z0-9_-]*:/ {print "  " $$0}' $(MAKEFILE_LIST) | sort -u

lint:
	@echo "==> helm lint upcloud-ccm"
	@$(HELM) lint upcloud-ccm \
		--set ccmConfig.clusterID=ci-test \
		--set credentials.username=ci --set credentials.password=ci
	@echo "==> helm lint upcloud-csi"
	@$(HELM) lint upcloud-csi
	@echo "==> helm lint cloudflare-operator"
	@$(HELM) lint cloudflare-operator
	@echo "==> helm lint digitalocean-ccm"
	@$(HELM) lint digitalocean-ccm \
		--set credentials.token=ci
	@echo "==> helm lint digitalocean-csi"
	@$(HELM) lint digitalocean-csi \
		--set credentials.token=ci
	@echo "==> helm lint psono"
	@$(HELM) lint psono \
		--set base_url=https://psono.example.com \
		--set domain=example.com

template:
	@mkdir -p /tmp/rendered
	@$(HELM) template ccm upcloud-ccm \
		--set ccmConfig.clusterID=ci-test \
		--set credentials.username=ci --set credentials.password=ci \
		> /tmp/rendered/upcloud-ccm.yaml
	@$(HELM) template csi upcloud-csi > /tmp/rendered/upcloud-csi.yaml
	@$(HELM) template cf  cloudflare-operator \
		--namespace cloudflare-operator-system \
		> /tmp/rendered/cloudflare-operator.yaml
	@$(HELM) template do-ccm digitalocean-ccm \
		--set credentials.token=ci \
		> /tmp/rendered/digitalocean-ccm.yaml
	@$(HELM) template do-csi digitalocean-csi \
		--set credentials.token=ci \
		> /tmp/rendered/digitalocean-csi.yaml
	@$(HELM) template psono psono \
		--namespace psono \
		--set base_url=https://psono.example.com \
		--set domain=example.com \
		--set ingress.enabled=true \
		--set adminClient.enabled=true \
		> /tmp/rendered/psono.yaml
	@echo "rendered to /tmp/rendered/{upcloud-ccm,upcloud-csi,cloudflare-operator,digitalocean-ccm,digitalocean-csi,psono}.yaml"

unittest:
	@for c in $(CHARTS); do \
		if [ -d "$$c/tests" ]; then \
			echo "==> helm unittest $$c"; \
			$(HELM) unittest $$c; \
		else \
			echo "==> skipping $$c (no tests/ directory)"; \
		fi; \
	done

test: lint template unittest

secret-scan:
	@command -v gitleaks >/dev/null 2>&1 || { echo "install gitleaks: https://github.com/gitleaks/gitleaks#installing"; exit 1; }
	@echo "==> gitleaks dir (working tree — tracked, staged & untracked)"
	@gitleaks dir . --redact --verbose --no-banner
	@echo "==> gitleaks git (full history — same as CI)"
	@gitleaks git . --redact --no-banner

sync:
	@./scripts/sync-upstream.sh ccm
	@./scripts/sync-upstream.sh csi
	@./scripts/sync-upstream.sh cloudflare
	@./scripts/sync-upstream.sh do-ccm
	@./scripts/sync-upstream.sh do-csi

sync-ccm:
	@./scripts/sync-upstream.sh ccm $(VERSION)

sync-csi:
	@./scripts/sync-upstream.sh csi $(VERSION)

sync-cloudflare:
	@./scripts/sync-upstream.sh cloudflare $(VERSION)

sync-do-ccm:
	@./scripts/sync-upstream.sh do-ccm $(VERSION)

sync-do-csi:
	@./scripts/sync-upstream.sh do-csi $(VERSION)

check:
	@./scripts/sync-upstream.sh check

docs:
	@command -v helm-docs >/dev/null 2>&1 || { echo "install helm-docs: https://github.com/norwoodj/helm-docs"; exit 1; }
	@helm-docs --chart-search-root=.
