SHELL := /bin/bash

SCRIPT = bin/mac-sync

.PHONY: all check help

all: check

check:
	bash -n $(SCRIPT)
	$(SCRIPT) --help >/dev/null
	$(SCRIPT) list >/dev/null

help:
	@$(SCRIPT) --help
