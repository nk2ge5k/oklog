REPO      = oklog
ROOT_DIR  = $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
VENDOR   ?= $(shell whoami)

GO ?= $(shell which go)

GOLANGCI_LINT_FORMAT ?= "colored-line-number"
BUF_LINT_FORMAT ?= "text"

GIT := /usr/bin/git

DATE     := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
HEAD     := $(shell $(GIT) rev-parse --short HEAD)
REVISION ?= $(HEAD)$(shell $(GIT) diff --quiet || echo '-dirty')
TAG      := v$(shell date -u +%Y%m%d%H%M)
REGISTRY ?= ""
IMAGE    ?= $(REGISTRY)$(VENDOR)/$(REPO):$(REVISION)

OS = $(shell uname -s)

ifeq ($(OS),Linux)
	GOOS   ?= linux
	GOARCH ?= amd64
	GOFLAGS ?= -a -trimpath -ldflags "-X 'main.version=$(REVISION)' -extldflags=-static"
endif
ifeq ($(OS),Darwin)
	GOOS   ?= darwin
	GOARCH ?= $(shell uname -m)
	GOFLAGS ?= -a -trimpath -ldflags "-X 'main.version=$(REVISION)'"
endif

include Makefile.tools

HASH       := $(HEAD)$(shell git ls-files -o --exclude-standard -m | sort | xargs cat | md5sum | cut -d ' ' -f 1)
BUILD_HASH := $(HASH)
GO_HASH    := $(shell find $(ROOT_DIR) -type f -name '*.go' | sort | xargs cat | md5sum | cut -d ' ' -f 1)
BUILD_DIR  := $(ROOT_DIR)/build
_BUILD_DIR := $(BUILD_DIR)/1
BUILD      := $(BUILD_DIR)/build-$(BUILD_HASH)
GEN        := $(BUILD_DIR)/codegen-$(GO_HASH)
GEN_GO     := $(BUILD_DIR)/gen-go-$(GO_HASH)
DOCKER     := $(BUILD_DIR)/docker-$(HASH)

$(_BUILD_DIR):
	@mkdir -p $(BUILD_DIR) && touch $(_BUILD_DIR)

build: $(BUILD) ## Build for production
.PHONY: build

$(BUILD): $(GEN)
	@echo "Building for production..."
	@echo "Go version:                $(shell $(GO) version)"
	@echo "OS:                        $(GOOS)"
	@echo "Arch:                      $(GOARCH)"
	@echo "Binary output:             $(BUILD_DIR)/$(REPO).$(GOOS).$(GOARCH)"
	@echo "Version:                   $(TAG)"
	@echo "MD5:                       $(BUILD_HASH)"
	@echo ""

	@rm -f $(BUILD_DIR)/build-*
	@GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 $(GO) build $(GOFLAGS) \
		-o $(BUILD_DIR)/$(REPO).$(GOOS).$(GOARCH) $(ROOT_DIR)/cmd/oklog
	@ln -f $(BUILD_DIR)/$(REPO).$(GOOS).$(GOARCH) $(BUILD_DIR)/$(REPO)
	@touch $(BUILD)

#################################### DOCKER ####################################

docker-build: $(DOCKER) ## Build docker image
.PHONY: docker-build

$(DOCKER): $(_BUILD_DIR)
	@echo "Building docker image"
	@echo "Image:                     $(IMAGE)"
	@echo "MD5:                       $(HASH)"
	@echo ""
	@rm -f $(BUILD_DIR)/docker-*
	@docker build --tag=$(IMAGE) $(ROOT_DIR) && touch $(DOCKER)

docker-push: $(DOCKER) ## Push docker image to the repository
	@echo "Pushing docker image to the repository"
	@echo "Image:                     $(IMAGE)"
	@echo ""
	@docker push $(IMAGE)
.PHONY: docker-push

##################################### TEST #####################################

test: test-go ## Run all tests
.PHONY: test

test-go: $(GEN) ## Run all unit tests
	@$(GO) test -v -race ./...
.PHONY: test-go

################################### GENERATE ###################################

gen: $(GEN) ## Run code generation
.PHONY: gen

$(GEN): $(_BUILD_DIR) $(GEN_GO)
	@rm -f $(BUILD_DIR)/codegen-*
	@touch $(GEN)

$(GEN_GO):
	@echo "Generating go code..."
	@echo "MD5:                       $(GO_HASH)"
	@echo ""
	@rm -f $(BUILD_DIR)/gen-go-*
	@$(GO) generate ./... && touch $(GEN_GO)

#################################### FORMAT ####################################

format: format-yaml format-go ## Format service files
.PHONY: format

format-go: $(GOIMPORTS) ## Format service Go files
	@$(TMP_BIN)/goimports -local=$(REPO) -w \
		$(shell ls -d $(ROOT_DIR)/*/ | grep -v -e vendor -e .tmp -e .venv) \
		$(shell ls $(ROOT_DIR) | grep .go)
.PHONY: format-go

format-yaml: $(YAMLFMT) ## Format YAML files
	@$(TMP_BIN)/yamlfmt -conf $(ROOT_DIR)/.yamlfmt .
.PHONY: format-yaml

##################################### LINT #####################################

lint: lint-go ## Run every available linter
.PHONY: lint

lint-go: $(GOLANGCI_LINT) gen ## Run linting on Go files
	@$(TMP_BIN)/golangci-lint run \
		-c $(ROOT_DIR)/.golangci.yaml \
		--out-format=$(GOLANGCI_LINT_FORMAT)
.PHONY: lint-go

##################################### HELP #####################################

help: ## Show this help
	@echo "\nSpecify a command. The choices are:\n"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-20s\033[m %s\n", $$1, $$2}'
	@echo ""
.PHONY: help

clean: ## Clean temporary files and directories
	git clean -xdf
	find . -type d -name __pycache__ -print | xargs rm -rf
	find . -type d -name '.pytest_cache' -print | xargs rm -rf
.PHONY: clean

.DEFAULT_GOAL := help
