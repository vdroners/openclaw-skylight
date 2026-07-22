.PHONY: install gates scrub publish smoke household-gates mail-gates talk-gates ai-gates day-review shell-cron recipes-gates recipes-web-sync recipes-full-sync

OPENCLAW_DIR ?= $(HOME)/.openclaw

install:
	bash scripts/install-to-openclaw.sh --force

gates: scrub publish
	bash scripts/skylight-household-gates.sh --skip-mail
	$(MAKE) mail-gates talk-gates ai-gates

scrub:
	bash scripts/scrub-for-publish.sh

publish:
	bash scripts/publish-gates.sh

smoke:
	bash scripts/skylight-smoke.sh

household-gates:
	bash scripts/skylight-household-gates.sh

mail-gates:
	bash scripts/mail-gates.sh --check

talk-gates:
	bash scripts/talk-response-audit.sh --check --phase all

ai-gates:
	bash scripts/openclaw-ai-gates.sh --check

day-review:
	bash $(OPENCLAW_DIR)/scripts/openclaw-day-review.sh --check

shell-cron:
	OPENCLAW_SKYLIGHT_ROOT=$$(pwd) python3 scripts/install-openclaw-shell-cron.sh

chore-fill-dry:
	bash scripts/skylight-chores-fill-blanks.sh --dry-run

chore-dedupe-dry:
	bash scripts/skylight-chores-dedupe-parent.sh --dry-run

recipes-gates:
	bash scripts/skylight-recipe-gates.sh --check --web-only

recipes-web-sync:
	bash scripts/skylight-sync-web-recipes.sh

recipes-full-sync:
	bash scripts/skylight-sync-all-bb-recipes.sh
