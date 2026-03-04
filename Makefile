.DEFAULT_GOAL := help

APP_NAME     := VidPare
BUILD_DIR    := .build
DEBUG_BIN    := $(BUILD_DIR)/debug/$(APP_NAME)
RELEASE_BIN  := $(BUILD_DIR)/release/$(APP_NAME)

# CI-friendly overrides (e.g. make build VERBOSE=1, make lint-strict REPORTER=github-actions-logging)
VERBOSE  ?=
REPORTER ?=
COVERAGE ?=
V_FLAG   := $(if $(VERBOSE),-v)
COV_FLAG := $(if $(COVERAGE),--enable-code-coverage)

# ── Build ────────────────────────────────────────────────────────────

.PHONY: build
build: ## Debug build
	swift build $(V_FLAG)

.PHONY: build-release
build-release: ## Optimized release build
	swift build -c release $(V_FLAG)

.PHONY: build-universal
build-universal: ## Universal (arm64 + x86_64) release build
	./scripts/release/build-universal.sh

# ── Quality ──────────────────────────────────────────────────────────

.PHONY: lint
lint: ## Run SwiftLint
	swiftlint

.PHONY: lint-strict
lint-strict: ## Run SwiftLint in strict mode (CI)
	swiftlint lint --strict $(if $(REPORTER),--reporter $(REPORTER))

.PHONY: format
format: ## Format all Swift source files in-place
	swift-format -i -r Sources/ Tests/

.PHONY: format-check
format-check: ## Check formatting without modifying files
	swift-format lint -r Sources/ Tests/

# ── Test ─────────────────────────────────────────────────────────────

.PHONY: test
test: ## Run unit and snapshot tests (excludes acceptance tests)
	swift test --skip VidPareAcceptanceTests $(V_FLAG) $(COV_FLAG)

.PHONY: test-verbose
test-verbose: ## Run unit tests with verbose output
	swift test -v

.PHONY: test-snapshots
test-snapshots: ## Run snapshot tests only
	swift test --filter SnapshotTests $(V_FLAG)

.PHONY: test-record-snapshots
test-record-snapshots: ## Re-record all snapshot baselines
	SNAPSHOT_TESTING_RECORD=1 swift test --filter SnapshotTests $(V_FLAG)

.PHONY: test-acceptance
test-acceptance: build ## Run acceptance tests (requires accessibility permissions)
	@swift -e 'import ApplicationServices; exit(AXIsProcessTrusted() ? 0 : 1)' 2>/dev/null || \
		{ echo "Error: Accessibility permissions not granted." >&2; \
		  echo "Add your terminal to System Settings > Privacy & Security > Accessibility." >&2; \
		  exit 1; }
	VIDPARE_BINARY=$(DEBUG_BIN) swift test --filter VidPareAcceptanceTests $(V_FLAG)

.PHONY: coverage
coverage: ## Run tests with code coverage and generate LCOV report
	swift test --enable-code-coverage -v
	@PROF_DATA="$(BUILD_DIR)/debug/codecov/default.profdata"; \
	TEST_BIN="$(BUILD_DIR)/debug/$(APP_NAME)PackageTests.xctest/Contents/MacOS/$(APP_NAME)PackageTests"; \
	if [ ! -f "$$PROF_DATA" ]; then \
		echo "Error: profdata not found at $$PROF_DATA" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$$TEST_BIN" ]; then \
		echo "Error: test bundle not found at $$TEST_BIN" >&2; \
		exit 1; \
	fi; \
	xcrun llvm-cov export \
	  -format="lcov" \
	  -instr-profile="$$PROF_DATA" \
	  "$$TEST_BIN" \
	  > $(BUILD_DIR)/coverage.lcov && \
	echo "Coverage report: $(BUILD_DIR)/coverage.lcov"

# ── Run ──────────────────────────────────────────────────────────────

.PHONY: run
run: build ## Build and run debug binary
	$(DEBUG_BIN)

.PHONY: open
open: build ## Build and open the debug binary
	open $(DEBUG_BIN)

# ── Package & Release ────────────────────────────────────────────────

.PHONY: package-dmg
package-dmg: build-universal ## Create DMG installer
	./scripts/release/package-dmg.sh

.PHONY: sign
sign: ## Sign and notarize (requires Apple credentials)
	./scripts/release/sign-and-notarize.sh

# ── Site ─────────────────────────────────────────────────────────────

site/node_modules/.installed: site/package-lock.json
	cd site && npm ci
	@touch $@

.PHONY: site-dev
site-dev: site/node_modules/.installed ## Start product website dev server
	cd site && npm run dev

.PHONY: site-build
site-build: site/node_modules/.installed ## Production build of product website
	cd site && npm run build

# ── Housekeeping ─────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove build artifacts
	swift package clean

.PHONY: resolve
resolve: ## Resolve package dependencies
	swift package resolve

.PHONY: all
all: check ## Alias for check (tool compatibility)

.PHONY: check
check: lint build test test-acceptance ## Run lint, build, and all tests (pre-push check)
	@echo "All checks passed."

# ── Help ─────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
