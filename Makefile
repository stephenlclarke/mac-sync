SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := all

SWIFT ?= swift
SWIFT_RESOLVED_FLAGS ?= --disable-automatic-resolution
SWIFT_RELEASE_FLAGS ?= -Xswiftc -Osize
PYTHON ?= python3
MARKDOWNLINT ?= markdownlint
COVERAGE_MIN ?= 80
DIST_DIR ?= dist
MAC_SYNC_ARCHIVE ?= mac-sync-main-release-arm64.tar.gz
MAC_SYNC_VERSION ?= 0.1.0
MAC_SYNC_SOURCE ?= $(shell $(PYTHON) -c 'import subprocess; result = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True); url = result.stdout.strip() if result.returncode == 0 else ""; url = url.removeprefix("git@github.com:").removeprefix("https://github.com/").removesuffix(".git"); print(url or "stephenlclarke/mac-sync")')
MAC_SYNC_BRANCH ?= $(shell git branch --show-current 2>/dev/null || git rev-parse --short HEAD)
MAC_SYNC_LANE ?= $(shell $(PYTHON) -c 'branch = "$(MAC_SYNC_BRANCH)"; print("main" if branch == "main" else "release" if branch == "release" or branch.startswith("release-") else "detached" if branch in ("", "HEAD") else "development")')
MAC_SYNC_COMMIT ?= $(shell git rev-parse HEAD)
SONAR_QUALITYGATE_WAIT ?= false
SONAR_SCAN_ATTEMPTS ?= 3
SWIFT_RUNTIME_RESOURCE_PATH ?= $(shell $(SWIFT) -print-target-info 2>/dev/null | $(PYTHON) -c 'import json, sys; print(json.load(sys.stdin).get("paths", {}).get("runtimeResourcePath", ""))' 2>/dev/null || true)
SWIFT_TOOLCHAIN_USR_DIR := $(patsubst %/lib/swift,%,$(SWIFT_RUNTIME_RESOURCE_PATH))
SWIFT_LLVM_COV ?= $(firstword $(wildcard $(SWIFT_TOOLCHAIN_USR_DIR)/bin/llvm-cov) $(shell xcrun --find llvm-cov 2>/dev/null || command -v llvm-cov 2>/dev/null || true))
SWIFT_LLVM_PROFDATA ?= $(firstword $(wildcard $(SWIFT_TOOLCHAIN_USR_DIR)/bin/llvm-profdata) $(shell xcrun --find llvm-profdata 2>/dev/null || command -v llvm-profdata 2>/dev/null || true))
SWIFT_TEST_RESULT_LOG ?= .build/swift-test.log
SWIFT_TEST_ATTEMPTS ?= 2
SWIFT_COVERAGE_TEST_ATTEMPTS ?= 3
SWIFT_TEST_RUN_FLAGS ?= --no-parallel
MAC_SYNC_BINARY ?= $(abspath .build/debug/mac-sync)
MAC_SPINNER_BINARY ?= $(abspath .build/debug/mac-spinner)
SHELL_TESTS := spinner help manifest status restore homebrew editor github-repositories secrets concurrent-machines
MARKDOWN_FILES := README.md CODE_OF_CONDUCT.md CONTRIBUTING.md SECURITY.md SUPPORT.md WORKFLOW.md NOTICE.md LICENSE.md .github/pull_request_template.md

.PHONY: all workflow ci clean run build build-release test resolve swift-test-build swift-test swift-coverage coverage-shell-test shell-test cli-smoke cli-smoke-built coverage coverage-check sonar sonar-scan package package-release package-debug package-built coverage-tools-test check lint format fmt

all: workflow

workflow: ci package

ci: check coverage-check cli-smoke-built

resolve:
	$(SWIFT) package resolve

build:
	$(SWIFT) build $(SWIFT_RESOLVED_FLAGS) --product mac-sync
	$(SWIFT) build $(SWIFT_RESOLVED_FLAGS) --product mac-spinner

build-release:
	$(SWIFT) build $(SWIFT_RESOLVED_FLAGS) -c release --product mac-sync $(SWIFT_RELEASE_FLAGS)
	$(SWIFT) build $(SWIFT_RESOLVED_FLAGS) -c release --product mac-spinner $(SWIFT_RELEASE_FLAGS)

run:
	$(SWIFT) run $(SWIFT_RESOLVED_FLAGS) mac-sync --help

test: swift-test shell-test

swift-test-build:
	$(SWIFT) build $(SWIFT_RESOLVED_FLAGS) --build-tests --enable-code-coverage

swift-test: swift-test-build
	@mkdir -p .build
	@SWIFT_TEST_RESULT_LOG="$(SWIFT_TEST_RESULT_LOG)" SWIFT_TEST_ATTEMPTS="$(SWIFT_TEST_ATTEMPTS)" Tools/ci/run-swift-test.sh $(SWIFT) test $(SWIFT_RESOLVED_FLAGS) --skip-build --enable-code-coverage $(SWIFT_TEST_RUN_FLAGS)
	@if ! grep -Eq 'Test run with [1-9][0-9]* tests .* passed|Executed [1-9][0-9]* tests|swiftpm-testing-helper signal 13 toolchain failure' "$(SWIFT_TEST_RESULT_LOG)"; then \
		printf 'swift test completed without running tests; check the active toolchain.\n' >&2; \
		exit 1; \
	fi

swift-coverage: swift-test-build
	@if [[ -z "$(SWIFT_LLVM_COV)" ]]; then \
		printf 'llvm-cov is required; install the active Swift toolchain or set SWIFT_LLVM_COV=/path/to/llvm-cov\n' >&2; \
		exit 1; \
	fi
	@if [[ -z "$(SWIFT_LLVM_PROFDATA)" ]]; then \
		printf 'llvm-profdata is required; install the active Swift toolchain or set SWIFT_LLVM_PROFDATA=/path/to/llvm-profdata\n' >&2; \
		exit 1; \
	fi
	@rm -f .build/*/debug/codecov/*.profraw .build/*/debug/codecov/*.profdata .build/codecov/fallback.profdata coverage.lcov coverage.xml
	@find .build -maxdepth 3 -path '*/debug' -type d -exec mkdir -p '{}/codecov' \;
	@SWIFT_TEST_RESULT_LOG="$(SWIFT_TEST_RESULT_LOG)" SWIFT_TEST_ATTEMPTS="$(SWIFT_COVERAGE_TEST_ATTEMPTS)" SWIFT_TEST_ACCEPT_SIGNAL_13=0 LLVM_PROFILE_FILE="$(abspath .build/codecov)/swift-test-%p.profraw" Tools/ci/run-swift-test.sh $(SWIFT) test $(SWIFT_RESOLVED_FLAGS) --skip-build --enable-code-coverage $(SWIFT_TEST_RUN_FLAGS)
	@$(MAKE) coverage-shell-test
	test_binary="$$(find .build -path '*.xctest/Contents/MacOS/*' -type f ! -path '*.dSYM/*' | while read -r file; do [[ -x "$$file" ]] && { printf '%s\n' "$$file"; break; }; done)"; \
	profile=".build/codecov/fallback.profdata"; \
	if [[ -z "$$test_binary" ]]; then \
		printf 'Swift test binary is missing; run make swift-test-build before make swift-coverage\n' >&2; \
		exit 2; \
	fi; \
	raw_profile_count="$$(find .build -name '*.profraw' -type f | wc -l | tr -d ' ')"; \
	if [[ "$$raw_profile_count" -eq 0 ]]; then \
		printf 'Swift coverage profile is missing and no raw .profraw files were found\n' >&2; \
		exit 2; \
	fi; \
	mkdir -p .build/codecov; \
	find .build -name '*.profraw' -type f -print0 | xargs -0 "$(SWIFT_LLVM_PROFDATA)" merge -sparse -o "$$profile"; \
	"$(SWIFT_LLVM_COV)" export \
		-format=lcov \
		-instr-profile="$$profile" \
		"$$test_binary" \
		--sources Sources/MacSyncCore/MacSyncCore.swift \
		--sources Sources/MacSyncCore/Support.swift \
		> coverage.lcov; \
	$(PYTHON) Tools/coverage/lcov-to-sonarqube-generic.py coverage.lcov coverage.xml

coverage-shell-test:
	@for test_name in $(SHELL_TESTS); do \
		target="$(MAC_SYNC_BINARY)"; \
		if [[ "$$test_name" == "spinner" ]]; then \
			target="$(MAC_SPINNER_BINARY)"; \
		fi; \
		printf '== coverage %s ==\n' "$$test_name"; \
		LLVM_PROFILE_FILE="$(abspath .build/codecov)/shell-$${test_name}-%p.profraw" bash "tests/$${test_name}.sh" "$$target"; \
	done

shell-test: build
	@for test_name in $(SHELL_TESTS); do \
		target="$(MAC_SYNC_BINARY)"; \
		if [[ "$$test_name" == "spinner" ]]; then \
			target="$(MAC_SPINNER_BINARY)"; \
		fi; \
		printf '== %s ==\n' "$$test_name"; \
		bash "tests/$${test_name}.sh" "$$target"; \
	done

cli-smoke: build cli-smoke-built

cli-smoke-built:
	@test -x "$(MAC_SYNC_BINARY)" || { \
		printf '%s is missing; run make build before make cli-smoke-built\n' "$(MAC_SYNC_BINARY)" >&2; \
		exit 2; \
	}
	@test -x "$(MAC_SPINNER_BINARY)" || { \
		printf '%s is missing; run make build before make cli-smoke-built\n' "$(MAC_SPINNER_BINARY)" >&2; \
		exit 2; \
	}
	MAC_SYNC_REPO="$(CURDIR)" "$(MAC_SYNC_BINARY)" --help >/dev/null
	MAC_SYNC_REPO="$(CURDIR)" "$(MAC_SYNC_BINARY)" list >/dev/null
	"$(MAC_SPINNER_BINARY)" --message smoke --pending >/dev/null

coverage: swift-coverage

coverage-check: coverage
	$(PYTHON) Tools/coverage/check-coverage.py \
		--minimum "$(COVERAGE_MIN)" \
		--swift coverage.xml

sonar: coverage sonar-scan

sonar-scan:
	@test -s coverage.xml || { \
		printf 'coverage.xml is missing or empty; run make coverage or make ci before make sonar-scan\n' >&2; \
		exit 2; \
	}
	@coverage_lines="$$(grep -c '<lineToCover ' coverage.xml || true)"; \
	if [[ "$$coverage_lines" -eq 0 ]]; then \
		printf 'coverage.xml has no lineToCover entries; run make coverage before make sonar-scan\n' >&2; \
		exit 2; \
	fi; \
	printf 'Sonar coverage report: coverage.xml (%s line entries)\n' "$$coverage_lines"
	@sonar_token="$${SONAR_TOKEN:-$${SONAR_TOKEN_PERSONAL:-}}"; \
	if [[ -z "$$sonar_token" ]]; then \
		printf 'SONAR_TOKEN or SONAR_TOKEN_PERSONAL is required for make sonar\n' >&2; \
		exit 2; \
	fi
	@sonar_token="$${SONAR_TOKEN:-$${SONAR_TOKEN_PERSONAL:-}}"; \
	branch="$${SONAR_BRANCH:-$$(git branch --show-current 2>/dev/null || true)}"; \
	attempt=1; \
	max_attempts="$(SONAR_SCAN_ATTEMPTS)"; \
	scanner_args=(-Dsonar.qualitygate.wait="$(SONAR_QUALITYGATE_WAIT)" -Dsonar.coverageReportPaths=coverage.xml); \
	if [[ -n "$$branch" && "$$branch" != "HEAD" ]]; then \
		scanner_args=(-Dsonar.branch.name="$$branch" "$${scanner_args[@]}"); \
	fi; \
	while true; do \
		set +e; \
		SONAR_TOKEN="$$sonar_token" sonar-scanner "$${scanner_args[@]}"; \
		status="$$?"; \
		set -e; \
		if [[ "$$status" -eq 0 ]]; then \
			exit 0; \
		fi; \
		if [[ "$$status" -eq 3 ]]; then \
			exit "$$status"; \
		fi; \
		if (( attempt >= max_attempts )); then \
			exit "$$status"; \
		fi; \
		printf 'Sonar scanner failed with exit %s; retrying %s/%s after 20 seconds...\n' "$$status" "$$((attempt + 1))" "$$max_attempts" >&2; \
		sleep 20; \
		((attempt += 1)); \
	done

package: package-release

package-release: PACKAGE_BUILD_CONFIGURATION = release
package-release: build-release
	$(MAKE) package-built PACKAGE_BUILD_CONFIGURATION="$(PACKAGE_BUILD_CONFIGURATION)"

package-debug: PACKAGE_BUILD_CONFIGURATION = debug
package-debug: build
	$(MAKE) package-built PACKAGE_BUILD_CONFIGURATION="$(PACKAGE_BUILD_CONFIGURATION)"

package-built:
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(DIST_DIR)/mac-sync/bin" "$(DIST_DIR)/mac-sync/resources"
	cp ".build/$(PACKAGE_BUILD_CONFIGURATION)/mac-sync" "$(DIST_DIR)/mac-sync/bin/mac-sync"
	cp ".build/$(PACKAGE_BUILD_CONFIGURATION)/mac-spinner" "$(DIST_DIR)/mac-sync/bin/mac-spinner"
	$(PYTHON) Tools/release/write-build-info.py \
		--output "$(DIST_DIR)/mac-sync/resources/build-info.json" \
		--version "$(MAC_SYNC_VERSION)" \
		--source "$(MAC_SYNC_SOURCE)" \
		--branch "$(MAC_SYNC_BRANCH)" \
		--lane "$(MAC_SYNC_LANE)" \
		--commit "$(MAC_SYNC_COMMIT)" \
		--build-type "$(PACKAGE_BUILD_CONFIGURATION)"
	tar -czf "$(MAC_SYNC_ARCHIVE)" -C "$(DIST_DIR)" mac-sync
	shasum -a 256 "$(MAC_SYNC_ARCHIVE)" > "$(MAC_SYNC_ARCHIVE).sha256"

coverage-tools-test:
	$(PYTHON) -m py_compile Tools/coverage/*.py Tools/release/*.py

check: lint

lint: coverage-tools-test
	@while IFS= read -r -d '' script; do \
		bash -n "$$script"; \
	done < <(find tests Tools -type f -name '*.sh' -print0)
	$(SWIFT) package dump-package >/dev/null
	@if command -v "$(MARKDOWNLINT)" >/dev/null 2>&1; then \
		"$(MARKDOWNLINT)" $(MARKDOWN_FILES); \
	elif command -v markdownlint-cli2 >/dev/null 2>&1; then \
		markdownlint-cli2 $(MARKDOWN_FILES); \
	else \
		printf 'markdownlint not found; skipping Markdown lint.\n'; \
	fi

fmt: format

format:
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat Package.swift Sources Tests --swift-version 6.2; \
	else \
		printf 'swiftformat not found; skipping Swift formatting.\n'; \
	fi

clean:
	rm -rf .build .swiftpm "$(DIST_DIR)" coverage.lcov coverage.xml *.profraw *.profdata
