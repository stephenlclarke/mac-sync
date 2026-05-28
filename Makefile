SHELL := /bin/bash

SCRIPT = bin/mac-sync
RESTORE_TEST = tests/restore.sh
HOMEBREW_TEST = tests/homebrew.sh

.PHONY: all check help

all: check

check:
	bash -n $(SCRIPT)
	/bin/bash -n $(SCRIPT)
	bash -n $(RESTORE_TEST)
	bash -n $(HOMEBREW_TEST)
	$(SCRIPT) --help >/dev/null
	$(SCRIPT) list >/dev/null
	/bin/bash $(SCRIPT) --help >/dev/null
	/bin/bash $(SCRIPT) list >/dev/null
	bash $(RESTORE_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(RESTORE_TEST) $(CURDIR)/$(SCRIPT)
	bash $(HOMEBREW_TEST) $(CURDIR)/$(SCRIPT)
	MAC_SYNC_TEST_RUNNER=/bin/bash bash $(HOMEBREW_TEST) $(CURDIR)/$(SCRIPT)

help:
	@$(SCRIPT) --help
