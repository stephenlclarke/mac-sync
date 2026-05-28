SHELL := /bin/bash

SCRIPT = bin/mac-sync
RESTORE_TEST = tests/restore.sh

.PHONY: all check help

all: check

check:
	bash -n $(SCRIPT)
	bash -n $(RESTORE_TEST)
	$(SCRIPT) --help >/dev/null
	$(SCRIPT) list >/dev/null
	bash $(RESTORE_TEST) $(CURDIR)/$(SCRIPT)

help:
	@$(SCRIPT) --help
