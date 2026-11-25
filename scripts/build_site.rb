#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "erb"
require "time"
require_relative "time_formatter"
require_relative "asset_processor"

# Static site generator for homebrew tap documentation
class SiteBuilder
  include ERB::Util
  include TimeFormatter
  include AssetProcessor

  # Context class for rendering ERB partials with access to builder methods and local variables
  class PartialContext
    include ERB::Util

    def initialize(builder, locals)
      @builder = builder
      locals.each do |key, value|
        define_singleton_method(key) { value }
      end
    end

    def render_partial(name, locals = {})
      @builder.render_partial(name, locals)
    end

    def format_date(timestamp)
      @builder.format_date(timestamp)
    end

    def format_datetime(timestamp)
      @builder.format_datetime(timestamp)
    end

    def binding_context
      binding
    end
  end
  DOCS_DIR = File.expand_path("../docs", __dir__).freeze
  DATA_DIR = File.join(DOCS_DIR, "_data").freeze
  OUTPUT_DIR = DOCS_DIR
  THEME_SOURCE_DIR = File.expand_path("../theme", __dir__).freeze
  TEMPLATES_DIR = THEME_SOURCE_DIR

  def self.build
    new.generate_site
  end

  def generate_site
    puts "🏗️  Building static site..."

    setup_directories

    # formulae.json is the parse stage's output and the only source of the data,
    # tap_name included. A missing file is a usage error, not an empty tap: the
    # former fallback rendered a zero-formula site under a second, wrong tap name.
    formulae_file = File.join(DATA_DIR, "formulae.json")
    abort "❌ #{formulae_file} not found; run scripts/parse_formulas.rb first" unless File.exist?(formulae_file)

    @data = JSON.parse(File.read(formulae_file))
    group_formulae

    copy_assets
    generate_css
    minify_js

    File.write(File.join(OUTPUT_DIR, "index.html"), load_template("index.html.erb").result(binding))

    # setup_directories created OUTPUT_DIR/formula.
    @data["formulae"].each do |formula|
      @formula = formula
      content = load_template("formula.html.erb").result(binding)
      File.write(File.join(OUTPUT_DIR, "formula", "#{formula["name"]}.html"), content)
    end

    File.write(File.join(OUTPUT_DIR, "formulae.html"), load_template("formulae.html.erb").result(binding))

    puts "✅ Site built successfully in #{OUTPUT_DIR}"
    puts "🌐 Open #{File.join(OUTPUT_DIR, "index.html")} in your browser"
  end

  def render_partial(name, locals = {})
    partial_path = File.join(TEMPLATES_DIR, "_#{name}.html.erb")
    raise ArgumentError, "Partial not found: #{partial_path}" unless File.exist?(partial_path)

    context = PartialContext.new(self, locals)
    ERB.new(File.read(partial_path)).result(context.binding_context)
  end

  private

  def setup_directories
    FileUtils.mkdir_p(File.join(OUTPUT_DIR, "formula"))
    templates = %w[index.html.erb formulae.html.erb formula.html.erb]
    return if templates.all? { |template| File.exist?(File.join(TEMPLATES_DIR, template)) }

    puts "⚠️  Templates not found in #{TEMPLATES_DIR}. Please ensure theme/*.html.erb files exist."
    exit 1
  end

  # Collapse the flat formulae list (main + "name@version" entries) so the site
  # shows one card/page per tool, with every version listed under its main
  # formula. Templates keep reading @data["formulae"]/["formulae_count"], so only
  # this transform and the versions section on the formula page need to know.
  def group_formulae
    all = Array(@data["formulae"]).grep(Hash)
    # Positive predicate on purpose: brew's Homebrew/NegateInclude cop rejects
    # `!include?`, and its suggested `exclude?` only exists inside brew's Ruby —
    # these scripts also run standalone under plain `ruby`. Swap the sides instead.
    versioned, mains = all.partition { |f| f["name"].to_s.include?("@") }
    by_base = versioned.group_by { |f| f["name"].to_s.split("@", 2).first }

    mains.each { |m| m["versions"] = sort_versions(by_base.delete(m["name"].to_s) || []) }

    # Versioned formulae with no plain main: synthesize a main from the newest.
    by_base.each do |base, vers|
      sorted = sort_versions(vers)
      mains << sorted.first.merge("name" => base, "versions" => sorted)
    end

    @data["formulae"] = mains.sort_by { |m| m["name"].to_s.downcase }
    @data["formulae_count"] = mains.length
  end

  # ponytail: Gem::Version handles both semver and calver; unparseable → 0.
  def sort_versions(list)
    list.sort_by do |f|
      Gem::Version.new(f["version"].to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end.reverse
  end

  def load_template(name)
    template_path = File.join(TEMPLATES_DIR, name)
    template_content = File.read(template_path)
    ERB.new(template_content)
  end
end

# Allow running this script directly
SiteBuilder.build if __FILE__ == $PROGRAM_NAME
