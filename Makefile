.PHONY: install gates scrub publish smoke household-gates mail-gates talk-gates ai-gates

OPENCLAW_DIR ?= $(HOME)/.openclaw

install:
	bash scripts/install-to-openclaw.sh --force

gates: scrub publish household-gates mail-gates talk-gates ai-gates

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
	bash scripts/alfred-ai-gates.sh --check

chore-fill-dry:
	bash scripts/skylight-chores-fill-blanks.sh --dry-run

chore-dedupe-dry:
	bash scripts/skylight-chores-dedupe-mom.sh --dry-run
