SHELL := /bin/bash
BASH_ENV =
ENV =
export BASH_ENV
export ENV

SCRIPT = bin/mac-sync
SPINNER = bin/mac-spinner
SPINNER_TEST = tests/spinner.sh
RESTORE_TEST = tests/restore.sh
HOMEBREW_TEST = tests/homebrew.sh
SECRETS_TEST = tests/secrets.sh
STATUS_TEST = tests/status.sh
HELP_TEST = tests/help.sh
SELF_UPDATE_TEST = tests/self-update.sh
MANIFEST_TEST = tests/manifest.sh

.PHONY: all check help

all: check

check:
	bash -n $(SCRIPT)
	bash -n $(SPINNER)
	/bin/bash -n $(SCRIPT)
	/bin/bash -n $(SPINNER)
	bash -n $(SPINNER_TEST)
	bash -n $(RESTORE_TEST)
	bash -n $(HOMEBREW_TEST)
	bash -n $(SECRETS_TEST)
	bash -n $(STATUS_TEST)
	bash -n $(HELP_TEST)
	bash -n $(SELF_UPDATE_TEST)
	bash -n $(MANIFEST_TEST)
	$(SCRIPT) --help >/dev/null
	$(SCRIPT) list >/dev/null
	/bin/bash $(SCRIPT) --help >/dev/null
	/bin/bash $(SCRIPT) list >/dev/null
	bash $(SPINNER_TEST) $(CURDIR)/$(SPINNER)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(SPINNER_TEST) $(CURDIR)/$(SPINNER)
	bash $(HELP_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(HELP_TEST) $(CURDIR)/$(SCRIPT)
	bash $(RESTORE_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(RESTORE_TEST) $(CURDIR)/$(SCRIPT)
	bash $(HOMEBREW_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(HOMEBREW_TEST) $(CURDIR)/$(SCRIPT)
	bash $(SECRETS_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(SECRETS_TEST) $(CURDIR)/$(SCRIPT)
	bash $(STATUS_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(STATUS_TEST) $(CURDIR)/$(SCRIPT)
	bash $(SELF_UPDATE_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(SELF_UPDATE_TEST) $(CURDIR)/$(SCRIPT)
	bash $(MANIFEST_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(MANIFEST_TEST) $(CURDIR)/$(SCRIPT)

help:
	@$(SCRIPT) --help
