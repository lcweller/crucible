# Crucible Makefile
# CI is the authoritative build environment. Local targets are a convenience.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ---- Module / binary metadata -----------------------------------------------

MODULE       := github.com/crucible-io/crucible
BINARY       := crucible
PKG_VERSION  := $(MODULE)/internal/version

# Version stamping. VERSION may be overridden by CI (e.g. from a git tag).
VERSION      ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "v0.0.0-dev")
COMMIT       ?= $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo "unknown")
BUILD_DATE   ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
GO_VERSION   := $(shell go version 2>/dev/null | awk '{print $$3}' || echo "go-unknown")

LDFLAGS := -s -w \
	-X '$(PKG_VERSION).Version=$(VERSION)' \
	-X '$(PKG_VERSION).Commit=$(COMMIT)' \
	-X '$(PKG_VERSION).BuildDate=$(BUILD_DATE)' \
	-X '$(PKG_VERSION).GoVersion=$(GO_VERSION)'

BUILD_FLAGS  := -trimpath -ldflags "$(LDFLAGS)"
TEST_FLAGS   := -race -count=1 -timeout=5m
COVER_FLAGS  := -coverprofile=coverage.txt -covermode=atomic

BIN_DIR      := bin
DIST_DIR     := dist

# Cross-compile matrix (Linux amd64+arm64, Windows amd64)
CROSS_TARGETS := \
	linux/amd64 \
	linux/arm64 \
	windows/amd64

# ---- Tooling versions (kept in sync with .github/workflows/ci.yml) ----------

GOLANGCI_LINT_VERSION := v1.61.0
GOVULNCHECK_VERSION   := latest

# ---- Help -------------------------------------------------------------------

.PHONY: help
help: ## Print this help
	@awk 'BEGIN {FS = ":.*##"; printf "Crucible — make targets\n\n"} \
		/^[a-zA-Z0-9_.-]+:.*##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)

# ---- Build ------------------------------------------------------------------

.PHONY: build
build: ## Build for the current OS/arch into ./bin/
	@mkdir -p $(BIN_DIR)
	go build $(BUILD_FLAGS) -o $(BIN_DIR)/$(BINARY) ./cmd/crucible

.PHONY: install
install: ## Install the binary into $GOPATH/bin
	go install $(BUILD_FLAGS) ./cmd/crucible

.PHONY: cross
cross: ## Cross-compile linux/amd64, linux/arm64, windows/amd64 into ./dist/
	@mkdir -p $(DIST_DIR)
	@for target in $(CROSS_TARGETS); do \
		os=$${target%/*}; arch=$${target#*/}; \
		ext=""; if [ "$$os" = "windows" ]; then ext=".exe"; fi; \
		out=$(DIST_DIR)/$(BINARY)-$$os-$$arch$$ext; \
		echo ">> building $$out"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch \
			go build $(BUILD_FLAGS) -o $$out ./cmd/crucible || exit 1; \
	done
	@echo ">> generating SHA256SUMS"
	@cd $(DIST_DIR) && sha256sum $(BINARY)-* > SHA256SUMS

# ---- Test -------------------------------------------------------------------

.PHONY: test
test: ## Run unit tests with race detector
	go test $(TEST_FLAGS) ./...

.PHONY: test-short
test-short: ## Run unit tests without race detector (fast)
	go test -count=1 -timeout=2m -short ./...

.PHONY: test-integration
test-integration: ## Run integration tests (build tag: integration)
	go test $(TEST_FLAGS) -tags=integration ./...

.PHONY: coverage
coverage: ## Run tests with coverage profile
	go test $(TEST_FLAGS) $(COVER_FLAGS) ./...
	go tool cover -func=coverage.txt | tail -1

.PHONY: coverage-html
coverage-html: coverage ## Generate HTML coverage report
	go tool cover -html=coverage.txt -o coverage.html
	@echo ">> coverage.html written"

# ---- Lint / vet -------------------------------------------------------------

.PHONY: lint
lint: ## Run golangci-lint
	@command -v golangci-lint >/dev/null 2>&1 || { \
		echo "golangci-lint not installed; install $(GOLANGCI_LINT_VERSION) from https://golangci-lint.run/usage/install/"; exit 1; }
	golangci-lint run ./...

.PHONY: vet
vet: ## Run go vet
	go vet ./...

.PHONY: fmt
fmt: ## Run gofmt and goimports (write changes)
	gofmt -s -w .
	@command -v goimports >/dev/null 2>&1 && goimports -w -local $(MODULE) . || true

.PHONY: fmt-check
fmt-check: ## Check formatting without writing
	@out=$$(gofmt -s -l .); \
	if [ -n "$$out" ]; then echo "gofmt diff:"; echo "$$out"; exit 1; fi

.PHONY: tidy
tidy: ## Run go mod tidy
	go mod tidy

.PHONY: tidy-check
tidy-check: ## Verify go.mod/go.sum are tidy (CI gate)
	go mod tidy
	@if ! git diff --exit-code -- go.mod go.sum; then \
		echo "go.mod / go.sum out of date — run 'make tidy'"; exit 1; fi

# ---- Security ---------------------------------------------------------------

.PHONY: vuln
vuln: ## Run govulncheck
	@command -v govulncheck >/dev/null 2>&1 || \
		go install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)
	govulncheck ./...

# ---- License header check ---------------------------------------------------

.PHONY: license-check
license-check: ## Ensure every .go file carries the SPDX header
	@missing=0; \
	while IFS= read -r f; do \
		head -n1 "$$f" | grep -q "SPDX-License-Identifier: BUSL-1.1" || { \
			echo "missing SPDX header: $$f"; missing=$$((missing+1)); }; \
	done < <(find . -type f -name '*.go' -not -path './vendor/*' -not -path './.git/*'); \
	if [ $$missing -gt 0 ]; then \
		echo "$$missing file(s) missing SPDX header — copy from LICENSE-HEADER.txt"; exit 1; \
	fi

# ---- Combined gates ---------------------------------------------------------

.PHONY: check
check: tidy-check fmt-check vet lint license-check test ## Full pre-commit gate (no race-free shortcuts)

.PHONY: ci
ci: tidy-check fmt-check vet lint license-check test vuln cross ## What CI runs

# ---- Housekeeping -----------------------------------------------------------

.PHONY: clean
clean: ## Remove build / test / coverage artifacts
	rm -rf $(BIN_DIR) $(DIST_DIR) coverage.txt coverage.html *.pprof *.trace

.PHONY: version
version: ## Print the version metadata that would be stamped into a build
	@echo "Version:    $(VERSION)"
	@echo "Commit:     $(COMMIT)"
	@echo "BuildDate:  $(BUILD_DATE)"
	@echo "GoVersion:  $(GO_VERSION)"
