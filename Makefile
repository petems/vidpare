.DEFAULT_GOAL := help

APP_NAME     := VidPare
BUILD_DIR    := .build
DEBUG_BIN    := $(BUILD_DIR)/debug/$(APP_NAME)
RELEASE_BIN  := $(BUILD_DIR)/release/$(APP_NAME)

# ── Build ────────────────────────────────────────────────────────────

.PHONY: build
build: ## Debug build
	swift build

.PHONY: build-release
build-release: ## Optimized release build
	swift build -c release

.PHONY: build-universal
build-universal: ## Universal (arm64 + x86_64) release build
	./scripts/release/build-universal.sh

# ── Quality ──────────────────────────────────────────────────────────

.PHONY: lint
lint: ## Run SwiftLint
	swiftlint

.PHONY: lint-strict
lint-strict: ## Run SwiftLint in strict mode (CI)
	swiftlint lint --strict

.PHONY: format
format: ## Format all Swift source files in-place
	swift-format -i -r Sources/ Tests/

.PHONY: format-check
format-check: ## Check formatting without modifying files
	swift-format lint -r Sources/ Tests/

# ── Test ─────────────────────────────────────────────────────────────

.PHONY: test
test: ## Run unit tests
	swift test

.PHONY: test-verbose
test-verbose: ## Run unit tests with verbose output
	swift test -v

.PHONY: coverage
coverage: ## Run tests with code coverage and generate LCOV report
	swift test --enable-code-coverage -v
	@PROF_DATA=$$(swift test --show-codecov-path 2>/dev/null) && \
	xcrun llvm-cov export \
	  -format="lcov" \
	  -instr-profile="$$(echo $$PROF_DATA | sed 's|codecov/.*|profdata/merged/default.profdata|')" \
	  "$(DEBUG_BIN)" \
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
package-dmg: ## Create DMG installer (requires prior build-universal)
	./scripts/release/package-dmg.sh

.PHONY: sign
sign: ## Sign and notarize (requires Apple credentials)
	./scripts/release/sign-and-notarize.sh

# ── Site ─────────────────────────────────────────────────────────────

.PHONY: site-dev
site-dev: ## Start product website dev server
	cd site && npm ci && npm run dev

.PHONY: site-build
site-build: ## Production build of product website
	cd site && npm ci && npm run build

# ── Housekeeping ─────────────────────────────────────────────────────

.PHONY: clean
clean: ## Remove build artifacts
	swift package clean

.PHONY: resolve
resolve: ## Resolve package dependencies
	swift package resolve

.PHONY: check
check: lint build test ## Run lint, build, and tests (pre-push check)
	@echo "All checks passed."

# ── Help ─────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
