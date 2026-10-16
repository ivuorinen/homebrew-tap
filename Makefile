# Homebrew Tap Makefile
# Provides convenient commands for building and managing the tap documentation

.PHONY: help build sync serve parse clean dev setup check test install update \
        update-bundler outdated watch serve-all serve-3000 serve-8080 build-production \
        tap-test tap-install lint lint-fix lint-update-config formula-new info version

# Default target
.DEFAULT_GOAL := help

# Every recipe line stops at its first failing command, including inside
# pipelines, so a failed parse/build/test fails the make target too.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# Variables
RUBY := ruby
BUNDLE := bundle exec
PORT := 4000
HOST := localhost
SCRIPTS_DIR := scripts
THEME_DIR := theme
DOCS_DIR := docs
FORMULA_DIR := Formula

help: ## Show this help message
	@echo "Homebrew Tap Documentation Builder"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Examples:"
	@echo "  make build           # Build the documentation site"
	@echo "  make serve           # Start development server on port 4000"
	@echo "  make serve PORT=3000 # Start development server on port 3000"
	@echo "  make dev             # Full development setup (parse + build + serve)"

build: ## Build the static documentation site
	@echo "🏗️  Building homebrew tap documentation..."
	@$(BUNDLE) $(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb
	@$(BUNDLE) $(RUBY) $(SCRIPTS_DIR)/build_site.rb
	@echo "✅ Build complete!"

sync: ## Generate/update formulae from the latest GitHub releases (needs gh)
	@command -v gh >/dev/null || { echo "❌ gh (GitHub CLI) not found. Install it first."; exit 1; }
	@echo "🔄 Syncing formulae from upstream releases..."
	@$(RUBY) $(SCRIPTS_DIR)/sync_formulae.rb
	@echo "✅ Sync complete!"

serve: ## Start development server (default: localhost:4000)
	@echo "🚀 Starting development server on http://$(HOST):$(PORT)"
	@$(BUNDLE) $(RUBY) $(SCRIPTS_DIR)/serve.rb $(PORT) $(HOST)

parse: ## Parse formulae and generate JSON data only
	@echo "📋 Parsing formulae..."
	@$(BUNDLE) $(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb
	@echo "✅ Formulae parsing complete!"

clean: ## Clean all generated files
	@echo "🧹 Cleaning generated files..."
	@rm -rf $(DOCS_DIR)/index.html $(DOCS_DIR)/formulae.html $(DOCS_DIR)/formula \
	        $(DOCS_DIR)/_data/formulae.json $(DOCS_DIR)/style.css $(DOCS_DIR)/main.js
	@if [ -d $(DOCS_DIR)/assets ]; then find $(DOCS_DIR)/assets -type f ! -name .gitkeep -delete; fi
	@echo "✅ Clean complete!"

dev: parse build serve ## Full development workflow: parse, build, and serve

setup: check install ## Initial project setup and dependency check
	@echo "✅ Environment setup complete!"

check: ## Check if all required files and directories exist
	@echo "🔍 Checking project structure..."
	@command -v $(RUBY) >/dev/null || { echo "❌ Ruby not found. Please install Ruby first."; exit 1; }
	@for d in $(SCRIPTS_DIR) $(THEME_DIR) $(FORMULA_DIR); do \
		test -d "$$d" || { echo "❌ Directory missing: $$d"; exit 1; }; \
	done
	@for f in index.html.erb formulae.html.erb formula.html.erb style.css main.js; do \
		test -f "$(THEME_DIR)/$$f" || { echo "❌ Theme file missing: $(THEME_DIR)/$$f"; exit 1; }; \
	done
	@echo "✅ Project structure OK"

test: check ## Run tests and validation
	@echo "🧪 Running validation tests..."
	@for f in $(SCRIPTS_DIR)/*.rb; do $(RUBY) -c "$$f" >/dev/null; done
	@$(BUNDLE) $(RUBY) $(SCRIPTS_DIR)/test_sync_formulae.rb
	@echo "✅ All tests passed!"

install: ## Install development dependencies
	@echo "📦 Installing Ruby dependencies..."
	@bundle config set path 'vendor/bundle'
	@bundle install
	@echo "✅ Dependencies installed!"

update: ## Update all gems to their latest versions (respecting Gemfile constraints)
	@echo "🔄 Updating Ruby dependencies..."
	@bundle update
	@echo "✅ All gems updated to latest versions!"

update-bundler: ## Update bundler itself to the latest version
	@echo "🔄 Updating Bundler..."
	@gem update bundler
	@echo "✅ Bundler updated!"
	@echo "Current version: $$(bundle --version)"

outdated: ## Show outdated gems
	@echo "📋 Checking for outdated gems..."
	@# bundle outdated exits 1 when anything is outdated; that is a report, not an error.
	@bundle outdated || true

watch: ## Watch for file changes and auto-rebuild (alias for serve)
	@$(MAKE) serve

# Advanced targets
serve-all: ## Start server accessible from all interfaces (0.0.0.0)
	@$(MAKE) serve HOST=0.0.0.0

serve-3000: ## Start server on port 3000
	@$(MAKE) serve PORT=3000

serve-8080: ## Start server on port 8080
	@$(MAKE) serve PORT=8080

build-production: ## Build for production deployment
	@echo "🏭 Building for production..."
	@$(MAKE) clean
	@$(MAKE) build
	@echo "✅ Production build complete!"

# Homebrew-specific targets
tap-test: ## Audit this tap's formulae locally, as CI does (needs brew)
	@echo "🍺 Auditing tap..."
	@brew tap ivuorinen/tap "$$(pwd)"
	@brew test-bot --only-tap-syntax --tap=ivuorinen/tap

tap-install: ## Install this tap locally for testing
	@echo "🍺 Installing tap locally..."
	@brew tap ivuorinen/tap "$$(pwd)"

lint: ## Lint Ruby (RuboCop, no brew needed). Formula audit still runs in CI via brew.
	@echo "🔍 Linting Ruby with RuboCop..."
	@$(BUNDLE) rubocop

lint-fix: ## Auto-correct safe RuboCop offenses
	@echo "🔧 Auto-correcting RuboCop offenses..."
	@$(BUNDLE) rubocop -A

lint-update-config: ## Refresh vendored Homebrew RuboCop config from homebrew-core
	@echo "⬇️  Updating .rubocop_homebrew.yml from Homebrew/homebrew-core..."
	@curl -fsSL https://raw.githubusercontent.com/Homebrew/homebrew-core/main/.rubocop.yml -o .rubocop_homebrew.yml
	@echo "✅ Updated. Run 'make lint' to check for new offenses."

formula-new: ## Create a new formula template (usage: make formula-new NAME=myformula)
	@if [ -z "$(NAME)" ]; then \
		echo "❌ Please provide a formula name: make formula-new NAME=myformula"; \
		exit 1; \
	fi
	@echo "📝 Creating new formula: $(NAME)"
	@FIRST_CHAR=$$(echo $(NAME) | cut -c1); \
	CLASS_NAME=$$($(RUBY) -e "puts '$(NAME)'.split('-').map(&:capitalize).join"); \
	mkdir -p $(FORMULA_DIR)/$$FIRST_CHAR; \
	echo "class $$CLASS_NAME < Formula" > $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  desc "Description of $(NAME)"' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  homepage "https://github.com/ivuorinen/$(NAME)"' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  url "https://github.com/ivuorinen/$(NAME)/archive/v1.0.0.tar.gz"' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  sha256 "REPLACE_WITH_ACTUAL_SHA256"' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  license "MIT"' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  def install' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '    # Installation steps here' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  end' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  test do' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '    # Test steps here' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo '  end' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb; \
	echo 'end' >> $(FORMULA_DIR)/$$FIRST_CHAR/$(NAME).rb
	@echo "✅ Formula template created at $(FORMULA_DIR)/$$(echo $(NAME) | cut -c1)/$(NAME).rb"
	@echo "📝 Remember to update the URL, SHA256, and implementation!"

# Information targets
info: ## Show project information
	@echo "📋 Homebrew Tap Information"
	@echo "=========================="
	@echo "Ruby version: $$($(RUBY) --version)"
	@echo "Project root: $$(pwd)"
	@echo "Scripts: $$(ls -1 $(SCRIPTS_DIR)/*.rb | wc -l | tr -d ' ') files"
	@echo "Formulae: $$(find $(FORMULA_DIR) -name '*.rb' | wc -l | tr -d ' ') files"
	@echo "Theme files: $$(ls -1 $(THEME_DIR)/* | wc -l | tr -d ' ') files"
	@if [ -f $(DOCS_DIR)/_data/formulae.json ]; then \
		echo "Generated formulae: $$($(RUBY) -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["formulae_count"]' $(DOCS_DIR)/_data/formulae.json)"; \
	fi

version: ## Show version information
	@echo "Homebrew Tap Builder"
	@echo "Ruby: $$($(RUBY) --version)"
	@echo "Make: $$($(MAKE) --version | head -1)"
	@echo "Git: $$(git --version 2>/dev/null || echo 'not available')"
