#!/usr/bin/env bash
set -euo pipefail

# Homebrew Tap Scaffold Script
# Creates a complete Homebrew tap with automated GitHub Pages documentation
# Repository: ivuorinen/homebrew-tap

REPO_OWNER="ivuorinen"
REPO_NAME="homebrew-tap"
RUBY_VERSION="3.4.5"

echo "🍺 Creating Homebrew tap: ${REPO_OWNER}/${REPO_NAME}"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p {Formula,docs/{_data,_includes,_layouts,assets/{css,js}},scripts,.github/workflows}

# Create Ruby version file
echo "📝 Creating .ruby-version..."
cat >.ruby-version <<EOF
${RUBY_VERSION}
EOF

# Create main Gemfile
echo "📝 Creating Gemfile..."
cat >Gemfile <<'EOF'
source "https://rubygems.org"

ruby "3.4.5"

gem "parser", "~> 3.3"
gem "json", "~> 2.7"

group :development, :test do
  gem "rubocop", "~> 1.69"
  gem "rubocop-rspec", "~> 3.6"
  gem "rubocop-performance", "~> 1.25"
  gem "rspec", "~> 3.13"
end
EOF

# Create formula parser script
echo "📝 Creating formula parser..."
cat >scripts/parse_formulas.rb <<'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'pathname'
require 'date'

# Parser class for extracting metadata from Homebrew formulae
class FormulaParser
  FORMULA_DIR = File.expand_path('../Formula', __dir__)
  OUTPUT_DIR = File.expand_path('../docs/_data', __dir__)
  OUTPUT_FILE = File.join(OUTPUT_DIR, 'formulae.json')

  # Regex patterns for safe extraction without code evaluation
  PATTERNS = {
    class_name: /^class\s+(\w+)\s+<\s+Formula/,
    desc: /^\s*desc\s+["']([^"']+)["']/,
    homepage: /^\s*homepage\s+["']([^"']+)["']/,
    url: /^\s*url\s+["']([^"']+)["']/,
    version: /^\s*version\s+["']([^"']+)["']/,
    sha256: /^\s*sha256\s+["']([a-f0-9]{64})["']/i,
    license: /^\s*license\s+["']([^"']+)["']/,
    depends_on: /^\s*depends_on\s+["']([^"']+)["']/
  }.freeze

  def self.run
    new.generate_documentation_data
  end

  def generate_documentation_data
    ensure_output_directory
    formulae = parse_all_formulae
    write_json_output(formulae)
    puts "✅ Successfully generated documentation for #{formulae.length} formulae"
  end

  private

  def ensure_output_directory
    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  def parse_all_formulae
    formula_files.map { |file| parse_formula(file) }.compact.sort_by { |f| f[:name] }
  end

  def formula_files
    Dir.glob(File.join(FORMULA_DIR, '**', '*.rb'))
  end

  def parse_formula(file_path)
    content = File.read(file_path)
    class_name = extract_value(content, :class_name)

    return nil unless class_name

    formula_name = convert_class_name_to_formula_name(class_name)

    return nil if formula_name.nil? || formula_name.empty?

    {
      name: formula_name,
      class_name: class_name,
      description: extract_value(content, :desc),
      homepage: extract_value(content, :homepage),
      url: extract_value(content, :url),
      version: extract_version(content),
      sha256: extract_value(content, :sha256),
      license: extract_value(content, :license),
      dependencies: extract_dependencies(content),
      file_path: Pathname.new(file_path).relative_path_from(Pathname.new(FORMULA_DIR)).to_s,
      last_modified: format_time_iso8601(File.mtime(file_path))
    }
  rescue StandardError => e
    warn "⚠️  Error parsing #{file_path}: #{e.message}"
    nil
  end

  def extract_value(content, pattern_key)
    match = content.match(PATTERNS[pattern_key])
    match&.[](1)
  end

  def extract_version(content)
    # Try explicit version first, then extract from URL
    explicit = extract_value(content, :version)
    return explicit if explicit

    url = extract_value(content, :url)
    return nil unless url

    # Common version patterns in URLs
    url.match(/v?(\d+(?:\.\d+)+)/)&.[](1)
  end

  def extract_dependencies(content)
    content.scan(PATTERNS[:depends_on]).flatten.uniq
  end

  def convert_class_name_to_formula_name(class_name)
    return nil unless class_name

    # Convert CamelCase to kebab-case
    class_name
      .gsub(/([a-z\d])([A-Z])/, '\1-\2')
      .downcase
  end

  def format_time_iso8601(time)
    # Format time manually for compatibility
    time.strftime('%Y-%m-%dT%H:%M:%S%z').gsub(/(\d{2})(\d{2})$/, '\1:\2')
  end

  def write_json_output(formulae)
    output = {
      tap_name: 'ivuorinen/homebrew-tap',
      generated_at: format_time_iso8601(Time.now),
      formulae_count: formulae.length,
      formulae: formulae
    }

    File.write(OUTPUT_FILE, JSON.pretty_generate(output))
  end
end

# Run if executed directly
FormulaParser.run if __FILE__ == $PROGRAM_NAME
EOF

chmod +x scripts/parse_formulas.rb

# Create GitHub Actions CI workflow
echo "📝 Creating CI workflow..."
cat >.github/workflows/ci.yml <<'EOF'
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write
  actions: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test-bot:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-22.04, macos-13, macos-14]
    runs-on: ${{ matrix.os }}

    steps:
      - name: Set up Homebrew
        id: set-up-homebrew
        uses: Homebrew/actions/setup-homebrew@master

      - name: Cache Homebrew Bundler RubyGems
        uses: actions/cache@v4
        with:
          path: ${{ steps.set-up-homebrew.outputs.gems-path }}
          key: ${{ runner.os }}-rubygems-${{ steps.set-up-homebrew.outputs.gems-hash }}
          restore-keys: ${{ runner.os }}-rubygems-

      - name: Install Homebrew Bundler RubyGems
        run: brew install-bundler-gems

      - name: Run brew test-bot (cleanup)
        run: brew test-bot --only-cleanup-before

      - name: Run brew test-bot (setup)
        run: brew test-bot --only-setup

      - name: Run brew test-bot (tap syntax)
        run: brew test-bot --only-tap-syntax

      - name: Run brew test-bot (formulae)
        if: github.event_name == 'pull_request'
        run: brew test-bot --only-formulae

      - name: Upload bottles as artifact
        if: always() && github.event_name == 'pull_request'
        uses: actions/upload-artifact@v4
        with:
          name: bottles_${{ matrix.os }}
          path: '*.bottle.*'
EOF

# Create GitHub Pages workflow
echo "📝 Creating Pages workflow..."
cat >.github/workflows/pages-build.yml <<'EOF'
name: Build and Deploy Documentation
on:
  push:
    branches: [main]
    paths:
      - 'Formula/**'
      - 'docs/**'
      - 'scripts/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.4'
          bundler-cache: true

      - name: Parse Formulae and Generate Data
        run: |
          ruby scripts/parse_formulas.rb
          echo "Generated formulae.json with $(jq '.formulae | length' docs/_data/formulae.json) formulae"

      - name: Setup Pages
        id: pages
        uses: actions/configure-pages@v5

      - name: Build Jekyll Site
        run: |
          cd docs
          bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"
        env:
          JEKYLL_ENV: production

      - name: Upload Pages Artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs/_site

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
EOF

# Create Jekyll Gemfile
echo "📝 Creating Jekyll Gemfile..."
cat >docs/Gemfile <<'EOF'
source "https://rubygems.org"

ruby "3.4.5"

gem "jekyll", "~> 4.4"

group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.17"
  gem "jekyll-seo-tag", "~> 2.8"
  gem "jekyll-sitemap", "~> 1.4"
end

platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end

gem "wdm", "~> 0.2", platforms: [:mingw, :x64_mingw, :mswin]
gem "http_parser.rb", "~> 0.6.0", platforms: [:jruby]
EOF

# Create Jekyll configuration
echo "📝 Creating Jekyll config..."
cat >docs/_config.yml <<'EOF'
title: ivuorinen/homebrew-tap
email: your-email@example.com
description: >-
  Homebrew Tap containing custom formulae for various tools and utilities.
  Automatically updated documentation for all available formulae.
baseurl: "/homebrew-tap"
url: "https://ivuorinen.github.io"
repository: ivuorinen/homebrew-tap

markdown: kramdown
kramdown:
  input: GFM
  syntax_highlighter: rouge
  syntax_highlighter_opts:
    css_class: 'highlight'
    span:
      line_numbers: false
    block:
      line_numbers: true

plugins:
  - jekyll-feed
  - jekyll-seo-tag
  - jekyll-sitemap

collections:
  formulae:
    output: true
    permalink: /formula/:name/

defaults:
  - scope:
      path: ""
      type: "pages"
    values:
      layout: "default"
  - scope:
      path: ""
      type: "formulae"
    values:
      layout: "formula"

exclude:
  - Gemfile
  - Gemfile.lock
  - node_modules
  - vendor/bundle/
  - vendor/cache/
  - vendor/gems/
  - vendor/ruby/
  - scripts/
  - .sass-cache/
  - .jekyll-cache/
EOF

# Create default layout
echo "📝 Creating Jekyll layouts..."
cat >docs/_layouts/default.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ page.title | default: site.title }}</title>
  {% seo %}
  <link rel="stylesheet" href="{{ '/assets/css/style.css' | relative_url }}">
</head>
<body>
  <header class="site-header">
    <div class="wrapper">
      <h1><a href="{{ '/' | relative_url }}">{{ site.title }}</a></h1>
      <nav>
        <a href="{{ '/' | relative_url }}">Home</a>
        <a href="{{ '/formulae' | relative_url }}">Formulae</a>
        <a href="{{ site.repository | prepend: 'https://github.com/' }}">GitHub</a>
      </nav>
    </div>
  </header>

  <main class="page-content">
    <div class="wrapper">
      {{ content }}
    </div>
  </main>

  <footer class="site-footer">
    <div class="wrapper">
      <p>&copy; {{ 'now' | date: '%Y' }} {{ site.title }}. Built with Jekyll and GitHub Pages.</p>
    </div>
  </footer>
</body>
</html>
EOF

# Create formula layout
cat >docs/_layouts/formula.html <<'EOF'
---
layout: default
---

{% assign formula = site.data.formulae.formulae | where: "name", page.formula | first %}

<article class="formula-page">
  <header class="formula-header">
    <h1>{{ formula.name }}</h1>
    <div class="formula-meta">
      {% if formula.version %}<span class="version">v{{ formula.version }}</span>{% endif %}
      {% if formula.license %}<span class="license">{{ formula.license }}</span>{% endif %}
      {% if formula.homepage %}<a href="{{ formula.homepage }}" class="homepage">Homepage</a>{% endif %}
    </div>
  </header>

  {% if formula.description %}
  <section class="description">
    <p>{{ formula.description }}</p>
  </section>
  {% endif %}

  <section class="installation">
    <h2>Installation</h2>
    <div class="code-block">
      <pre><code>brew tap {{ site.repository }}
brew install {{ formula.name }}</code></pre>
    </div>
  </section>

  {% if formula.dependencies.size > 0 %}
  <section class="dependencies">
    <h2>Dependencies</h2>
    <ul class="dep-list">
      {% for dep in formula.dependencies %}
      <li>{{ dep }}</li>
      {% endfor %}
    </ul>
  </section>
  {% endif %}

  <section class="details">
    <h2>Formula Details</h2>
    <table class="formula-details">
      {% if formula.url %}
      <tr>
        <th>Source URL</th>
        <td><a href="{{ formula.url }}">{{ formula.url | truncate: 60 }}</a></td>
      </tr>
      {% endif %}
      {% if formula.sha256 %}
      <tr>
        <th>SHA256</th>
        <td><code>{{ formula.sha256 | truncate: 20 }}...</code></td>
      </tr>
      {% endif %}
      <tr>
        <th>Last Updated</th>
        <td>{{ formula.last_modified | date: "%B %d, %Y" }}</td>
      </tr>
    </table>
  </section>

  <section class="source">
    <h2>Formula Source</h2>
    <p><a href="{{ site.repository | prepend: 'https://github.com/' }}/blob/main/Formula/{{ formula.file_path }}">
      View {{ formula.name }}.rb on GitHub
    </a></p>
  </section>
</article>
EOF

# Create main stylesheet
echo "📝 Creating CSS..."
cat >docs/assets/css/style.css <<'EOF'
:root {
  --primary-color: #0366d6;
  --text-color: #24292e;
  --bg-color: #ffffff;
  --code-bg: #f6f8fa;
  --border-color: #e1e4e8;
  --success-color: #28a745;
  --warning-color: #ffc107;
}

* {
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  line-height: 1.6;
  color: var(--text-color);
  background: var(--bg-color);
  margin: 0;
  padding: 0;
}

.wrapper {
  max-width: 980px;
  margin: 0 auto;
  padding: 0 2rem;
}

.site-header {
  border-bottom: 1px solid var(--border-color);
  padding: 1rem 0;
}

.site-header h1 {
  margin: 0;
  display: inline-block;
}

.site-header a {
  text-decoration: none;
  color: var(--text-color);
}

.site-header nav {
  float: right;
  margin-top: 0.5rem;
}

.site-header nav a {
  margin-left: 1rem;
  color: var(--primary-color);
}

.page-content {
  min-height: 70vh;
  padding: 2rem 0;
}

.formula-page {
  max-width: 100%;
}

.formula-header {
  border-bottom: 1px solid var(--border-color);
  padding-bottom: 1rem;
  margin-bottom: 2rem;
}

.formula-meta {
  display: flex;
  gap: 1rem;
  margin-top: 0.5rem;
  font-size: 0.9rem;
  flex-wrap: wrap;
}

.version {
  background: var(--success-color);
  color: white;
  padding: 0.2rem 0.5rem;
  border-radius: 3px;
}

.license {
  background: var(--code-bg);
  border: 1px solid var(--border-color);
  padding: 0.2rem 0.5rem;
  border-radius: 3px;
}

.code-block {
  background: var(--code-bg);
  border: 1px solid var(--border-color);
  border-radius: 6px;
  padding: 1rem;
  margin: 1rem 0;
  overflow-x: auto;
}

.code-block pre {
  margin: 0;
}

.dep-list {
  list-style: none;
  padding: 0;
}

.dep-list li {
  padding: 0.5rem;
  border-left: 3px solid var(--primary-color);
  margin: 0.5rem 0;
  background: var(--code-bg);
}

.formula-details {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
}

.formula-details th,
.formula-details td {
  padding: 0.75rem;
  text-align: left;
  border-bottom: 1px solid var(--border-color);
}

.formula-details th {
  background: var(--code-bg);
  font-weight: 600;
  width: 25%;
}

.site-footer {
  border-top: 1px solid var(--border-color);
  padding: 2rem 0;
  text-align: center;
  color: #586069;
  font-size: 0.875rem;
}

@media (max-width: 768px) {
  .wrapper {
    padding: 0 1rem;
  }

  .site-header nav {
    float: none;
    margin-top: 1rem;
  }

  .formula-meta {
    flex-direction: column;
    gap: 0.5rem;
  }

  .formula-details th {
    width: 35%;
  }
}
EOF

# Create main index page
echo "📝 Creating index page..."
cat >docs/index.md <<'EOF'
---
layout: default
title: Home
---

# ivuorinen/homebrew-tap

Welcome to the documentation for ivuorinen's Homebrew tap. This tap contains custom formulae for various tools and utilities.

## Quick Start

```bash
brew tap ivuorinen/homebrew-tap
brew install <formula-name>
```

## Available Formulae

{% if site.data.formulae.formulae.size > 0 %}
<div class="formulae-grid">
{% for formula in site.data.formulae.formulae %}
  <div class="formula-card">
    <h3><a href="{{ '/formula/' | append: formula.name | relative_url }}">{{ formula.name }}</a></h3>
    {% if formula.description %}<p>{{ formula.description }}</p>{% endif %}
    <div class="formula-meta">
      {% if formula.version %}<span class="version">v{{ formula.version }}</span>{% endif %}
      {% if formula.license %}<span class="license">{{ formula.license }}</span>{% endif %}
    </div>
  </div>
{% endfor %}
</div>
{% else %}
<p>No formulae available yet. Add some formulae to the <code>Formula/</code> directory to get started.</p>
{% endif %}

## Repository

View the source code and contribute on [GitHub](https://github.com/{{ site.repository }}).

---

*Documentation automatically generated from formula files.*
EOF

# Create formulae listing page
cat >docs/formulae.md <<'EOF'
---
layout: default
title: All Formulae
---

# All Formulae

{% if site.data.formulae.formulae.size > 0 %}
{% for formula in site.data.formulae.formulae %}
## [{{ formula.name }}]({{ '/formula/' | append: formula.name | relative_url }})

{% if formula.description %}{{ formula.description }}{% endif %}

**Installation:**
```bash
brew install {{ formula.name }}
```

{% if formula.dependencies.size > 0 %}
**Dependencies:** {{ formula.dependencies | join: ', ' }}
{% endif %}

---
{% endfor %}
{% else %}
No formulae available yet. Add some formulae to the `Formula/` directory to get started.
{% endif %}
EOF

# Create RuboCop configuration
echo "📝 Creating RuboCop config..."
cat >.rubocop.yml <<'EOF'
AllCops:
  TargetRubyVersion: 3.4
  NewCops: enable
  Exclude:
    - 'vendor/**/*'
    - 'docs/**/*'
    - '.bundle/**/*'

Layout/LineLength:
  Max: 120
  AllowedPatterns:
    - '^\s*#'
    - 'url "'

Layout/IndentationStyle:
  EnforcedStyle: spaces

Layout/IndentationWidth:
  Width: 2

Style/StringLiterals:
  EnforcedStyle: double_quotes

Style/FrozenStringLiteralComment:
  Enabled: true
  EnforcedStyle: always

Naming/FileName:
  Exclude:
    - 'Formula/**/*.rb'

Metrics/MethodLength:
  Max: 30

Metrics/ClassLength:
  Max: 150

Metrics/BlockLength:
  Exclude:
    - 'spec/**/*'
    - '*.gemspec'
EOF

# Create Dependabot configuration
echo "📝 Creating Dependabot config..."
cat >.github/dependabot.yml <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
    groups:
      github-actions:
        patterns:
          - "actions/*"
          - "ruby/setup-ruby"
          - "Homebrew/actions/*"
    commit-message:
      prefix: "ci"
      include: "scope"

  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
    groups:
      development-dependencies:
        dependency-type: "development"
        patterns:
          - "rubocop*"
          - "rspec*"
    commit-message:
      prefix: "deps"
      include: "scope"
EOF

# Create example formula
echo "📝 Creating example formula..."
mkdir -p Formula/e
cat >Formula/e/example-tool.rb <<'EOF'
class ExampleTool < Formula
  desc "An example tool to demonstrate the tap functionality"
  homepage "https://github.com/ivuorinen/example-tool"
  url "https://github.com/ivuorinen/example-tool/archive/v1.0.0.tar.gz"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w")
  end

  test do
    assert_match "example-tool version 1.0.0", shell_output("#{bin}/example-tool --version")
  end
end
EOF

# Create README
echo "📝 Creating README..."
cat >README.md <<'EOF'
# ivuorinen/homebrew-tap

A Homebrew tap for ivuorinen's custom formulae with automated documentation.

## Usage

```bash
# Add the tap
brew tap ivuorinen/homebrew-tap

# Install a formula
brew install <formula-name>

# List available formulae
brew search ivuorinen/homebrew-tap/
```

## Documentation

Visit [https://ivuorinen.github.io/homebrew-tap/](https://ivuorinen.github.io/homebrew-tap/) for complete documentation of all available formulae.

## Available Formulae

The documentation is automatically generated from the formula files and includes:
- Installation instructions
- Dependencies
- Version information
- Source links

## Contributing

1. Fork this repository
2. Create a new formula in the `Formula/` directory
3. Follow the [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
4. Submit a pull request

The CI will automatically validate your formula and update the documentation.

## Development

```bash
# Install dependencies
bundle install

# Parse formulae locally
ruby scripts/parse_formulas.rb

# Serve documentation locally
cd docs && bundle exec jekyll serve
```

## License

This tap is released under the MIT License. See LICENSE for details.
EOF

# Create .gitignore
echo "📝 Creating .gitignore..."
cat >.gitignore <<'EOF'
# Ruby
Gemfile.lock
.bundle/
vendor/bundle/

# Jekyll
docs/_site/
docs/.sass-cache/
docs/.jekyll-cache/
docs/.jekyll-metadata

# macOS
.DS_Store
.AppleDouble
.LSOverride

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log

# Generated files
docs/_data/formulae.json
EOF

# Create LICENSE
echo "📝 Creating LICENSE..."
cat >LICENSE <<'EOF'
MIT License

Copyright (c) 2025 Ismo Vuorinen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# Generate initial documentation
echo "🔄 Generating initial documentation..."
if command -v ruby >/dev/null 2>&1; then
    ruby scripts/parse_formulas.rb
    echo "✅ Initial documentation generated"
else
    echo "⚠️  Ruby not found. Documentation will be generated in CI."
fi

# Initialize git repository if not already initialized
if [ ! -d .git ]; then
    echo "🔄 Initializing git repository..."
    git init
    git add .
    git commit -m "Initial Homebrew tap setup with automated documentation

- Add formula parser with Ruby AST parsing
- Add GitHub Actions CI/CD workflows
- Add Jekyll-based documentation site
- Add RuboCop and Dependabot configuration
- Add example formula for demonstration"
    echo "✅ Git repository initialized"
else
    echo "ℹ️  Git repository already exists"
fi

# Final instructions
echo ""
echo "🎉 Homebrew tap scaffold complete!"
echo ""
echo "Next steps:"
echo "1. Push to GitHub: git remote add origin https://github.com/ivuorinen/homebrew-tap.git"
echo "2. Enable GitHub Pages in repository settings (Source: GitHub Actions)"
echo "3. Add your formulae to the Formula/ directory"
echo "4. The documentation will update automatically on each push"
echo ""
echo "Local development:"
echo "- Run 'bundle install' to install dependencies"
echo "- Run 'ruby scripts/parse_formulas.rb' to update documentation"
echo "- Run 'cd docs && bundle install && bundle exec jekyll serve' for local preview"
echo ""
echo "Documentation will be available at: https://ivuorinen.github.io/homebrew-tap/"
EOF
