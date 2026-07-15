# Homebrew Tap Makefile
# Provides convenient commands for building and managing the tap documentation

.PHONY: help build serve parse clean test install dev setup check lint update sync

# Default target
.DEFAULT_GOAL := help

# Variables
RUBY := ruby
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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Examples:"
	@echo "  make build           # Build the documentation site"
	@echo "  make serve           # Start development server on port 4000"
	@echo "  make serve PORT=3000 # Start development server on port 3000"
	@echo "  make dev             # Full development setup (parse + build + serve)"

build: ## Build the static documentation site
	@echo "🏗️  Building homebrew tap documentation..."
	@if [ -f Gemfile ]; then \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		export PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH"; \
		bundle exec $(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb; \
		bundle exec $(RUBY) $(SCRIPTS_DIR)/build_site.rb; \
	else \
		$(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb; \
		$(RUBY) $(SCRIPTS_DIR)/build_site.rb; \
	fi
	@echo "✅ Build complete!"

sync: ## Generate/update formulae from the latest GitHub releases (needs gh)
	@command -v gh >/dev/null || (echo "❌ gh (GitHub CLI) not found. Install it first." && exit 1)
	@echo "🔄 Syncing formulae from upstream releases..."
	@$(RUBY) $(SCRIPTS_DIR)/sync_formulae.rb
	@echo "✅ Sync complete!"

serve: ## Start development server (default: localhost:4000)
	@echo "🚀 Starting development server on http://$(HOST):$(PORT)"
	@if [ -f Gemfile ]; then \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		export PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH"; \
		bundle exec $(RUBY) $(SCRIPTS_DIR)/serve.rb $(PORT) $(HOST); \
	else \
		$(RUBY) $(SCRIPTS_DIR)/serve.rb $(PORT) $(HOST); \
	fi

parse: ## Parse formulae and generate JSON data only
	@echo "📋 Parsing formulae..."
	@if [ -f Gemfile ]; then \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		export PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH"; \
		bundle exec $(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb; \
	else \
		$(RUBY) $(SCRIPTS_DIR)/parse_formulas.rb; \
	fi
	@echo "✅ Formulae parsing complete!"

clean: ## Clean all generated files
	@echo "🧹 Cleaning generated files..."
	@$(RUBY) $(SCRIPTS_DIR)/make.rb clean
	@echo "✅ Clean complete!"

dev: parse build serve ## Full development workflow: parse, build, and serve

setup: ## Initial project setup and dependency check
	@echo "🔧 Setting up homebrew tap development environment..."
	@which $(RUBY) > /dev/null || (echo "❌ Ruby not found. Please install Ruby first." && exit 1)
	@echo "✅ Ruby found: $$($(RUBY) --version)"
	@test -d $(FORMULA_DIR) || (echo "❌ Formula directory not found" && exit 1)
	@test -d $(THEME_DIR) || (echo "❌ Theme directory not found" && exit 1)
	@test -f $(THEME_DIR)/index.html.erb || (echo "❌ Theme templates not found" && exit 1)
	@echo "📦 Installing Ruby dependencies..."
	@if ! command -v bundle >/dev/null 2>&1; then \
		echo "📥 Installing bundler..."; \
		gem install bundler --user-install; \
	fi
	@if [ -f Gemfile ]; then \
		echo "🔄 Running bundle install..."; \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		(export PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH" && \
		 bundle config set path 'vendor/bundle' && \
		 bundle install); \
		echo "✅ Ruby dependencies installed!"; \
	else \
		echo "ℹ️  No Gemfile found, skipping dependency installation"; \
	fi
	@echo "✅ Environment setup complete!"

check: ## Check if all required files and directories exist
	@echo "🔍 Checking project structure..."
	@test -d $(SCRIPTS_DIR) && echo "✅ Scripts directory exists" || echo "❌ Scripts directory missing"
	@test -d $(THEME_DIR) && echo "✅ Theme directory exists" || echo "❌ Theme directory missing"
	@test -d $(FORMULA_DIR) && echo "✅ Formula directory exists" || echo "❌ Formula directory missing"
	@test -f $(THEME_DIR)/index.html.erb && echo "✅ Index template exists" || echo "❌ Index template missing"
	@test -f $(THEME_DIR)/formulae.html.erb && echo "✅ Formulae template exists" || echo "❌ Formulae template missing"
	@test -f $(THEME_DIR)/formula.html.erb && echo "✅ Formula template exists" || echo "❌ Formula template missing"
	@test -f $(THEME_DIR)/style.css && echo "✅ CSS file exists" || echo "❌ CSS file missing"
	@test -f $(THEME_DIR)/main.js && echo "✅ JavaScript file exists" || echo "❌ JavaScript file missing"

test: check ## Run tests and validation
	@echo "🧪 Running validation tests..."
	@$(RUBY) -c $(SCRIPTS_DIR)/parse_formulas.rb && echo "✅ parse_formulas.rb syntax OK" || echo "❌ parse_formulas.rb syntax error"
	@$(RUBY) -c $(SCRIPTS_DIR)/build_site.rb && echo "✅ build_site.rb syntax OK" || echo "❌ build_site.rb syntax error"
	@$(RUBY) -c $(SCRIPTS_DIR)/serve.rb && echo "✅ serve.rb syntax OK" || echo "❌ serve.rb syntax error"
	@$(RUBY) -c $(SCRIPTS_DIR)/make.rb && echo "✅ make.rb syntax OK" || echo "❌ make.rb syntax error"
	@$(RUBY) -c $(SCRIPTS_DIR)/sync_formulae.rb && echo "✅ sync_formulae.rb syntax OK" || echo "❌ sync_formulae.rb syntax error"
	@$(RUBY) $(SCRIPTS_DIR)/test_sync_formulae.rb
	@echo "✅ All tests passed!"

install: ## Install development dependencies (if Gemfile exists)
	@if [ -f Gemfile ]; then \
		echo "📦 Installing Ruby dependencies..."; \
		if ! command -v bundle >/dev/null 2>&1; then \
			echo "📥 Installing bundler..."; \
			gem install bundler --user-install; \
		fi; \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		(export PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH" && \
		 bundle config set path 'vendor/bundle' && \
		 bundle install); \
		echo "✅ Dependencies installed!"; \
	else \
		echo "ℹ️  No Gemfile found, skipping dependency installation"; \
	fi

update: ## Update all gems to their latest versions (respecting Gemfile constraints)
	@if [ -f Gemfile ]; then \
		echo "🔄 Updating Ruby dependencies..."; \
		echo "📦 Running bundle update..."; \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH" bundle update; \
		echo "✅ All gems updated to latest versions!"; \
		echo ""; \
		echo "💡 Current gem versions:"; \
		PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH" bundle list | grep -E "^\s*\*" | head -10; \
	else \
		echo "❌ No Gemfile found"; \
		exit 1; \
	fi

update-bundler: ## Update bundler itself to the latest version
	@echo "🔄 Updating Bundler..."
	@gem update bundler
	@echo "✅ Bundler updated!"
	@echo "Current version: $$(bundle --version)"

outdated: ## Show outdated gems
	@if [ -f Gemfile ]; then \
		echo "📋 Checking for outdated gems..."; \
		RUBY_ABI_VERSION=$$($(RUBY) -e 'puts "#{RUBY_VERSION.split(".")[0]}.#{RUBY_VERSION.split(".")[1]}.0"'); \
		PATH="$$HOME/.local/share/gem/ruby/$$RUBY_ABI_VERSION/bin:$$PATH" bundle outdated || true; \
	else \
		echo "❌ No Gemfile found"; \
		exit 1; \
	fi

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
tap-test: ## Test the tap installation locally
	@echo "🍺 Testing tap installation..."
	@brew tap-new ivuorinen/homebrew-tap --no-git 2>/dev/null || true
	@brew audit --strict $(FORMULA_DIR)/*.rb || echo "⚠️  Some formulae may have audit issues"

tap-install: ## Install this tap locally for testing
	@echo "🍺 Installing tap locally..."
	@brew tap $$(pwd)

lint: ## Lint all Ruby scripts
	@echo "🔍 Linting Ruby scripts..."
	@brew style --fix --reset-cache .

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
		echo "Generated formulae: $$(cat $(DOCS_DIR)/_data/formulae.json | grep -o '"formulae_count":[0-9]*' | cut -d: -f2)"; \
	fi

version: ## Show version information
	@echo "Homebrew Tap Builder"
	@echo "Ruby: $$($(RUBY) --version)"
	@echo "Make: $$(make --version | head -1)"
	@echo "Git: $$(git --version 2>/dev/null || echo 'not available')"

# Legacy support (for backward compatibility with scripts/make.rb)
ruby-build: ## Legacy: use Ruby make script for build
	@$(RUBY) $(SCRIPTS_DIR)/make.rb build

ruby-serve: ## Legacy: use Ruby make script for serve
	@$(RUBY) $(SCRIPTS_DIR)/make.rb serve

ruby-clean: ## Legacy: use Ruby make script for clean
	@$(RUBY) $(SCRIPTS_DIR)/make.rb clean

ruby-parse: ## Legacy: use Ruby make script for parse
	@$(RUBY) $(SCRIPTS_DIR)/make.rb parse
