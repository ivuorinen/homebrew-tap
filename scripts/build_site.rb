#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "erb"
require "pathname"
require "time"
require "terser"
require "cssminify2"
require_relative "array_extensions"
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

    def format_relative_time(timestamp)
      @builder.format_relative_time(timestamp)
    end

    def format_date(timestamp)
      @builder.format_date(timestamp)
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
    load_data
    generate_assets
    generate_pages

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
    return if templates_exist?

    puts "⚠️  Templates not found in #{TEMPLATES_DIR}. Please ensure theme/*.html.erb files exist."
    exit 1
  end

  def load_data
    formulae_file = File.join(DATA_DIR, "formulae.json")
    @data = File.exist?(formulae_file) ? JSON.parse(File.read(formulae_file)) : default_data
  end

  def generate_assets
    copy_assets
    generate_css
    minify_js
  end

  def generate_pages
    generate_index_page
    generate_formulae_pages
  end

  def generate_index_page
    template = load_template("index.html.erb")
    content = template.result(binding)
    File.write(File.join(OUTPUT_DIR, "index.html"), content)
  end

  def generate_formulae_pages
    @data["formulae"].each do |formula|
      generate_formula_page(formula)
    end

    # Generate formulae index
    template = load_template("formulae.html.erb")
    content = template.result(binding)
    File.write(File.join(OUTPUT_DIR, "formulae.html"), content)
  end

  def generate_formula_page(formula)
    @formula = formula
    template = load_template("formula.html.erb")
    content = template.result(binding)

    formula_dir = File.join(OUTPUT_DIR, "formula")
    FileUtils.mkdir_p(formula_dir)
    File.write(File.join(formula_dir, "#{formula["name"]}.html"), content)
  end

  def load_template(name)
    template_path = File.join(TEMPLATES_DIR, name)
    template_content = File.read(template_path)
    ERB.new(template_content)
  end

  def templates_exist?
    %w[index.html.erb formulae.html.erb formula.html.erb].all? do |template|
      File.exist?(File.join(TEMPLATES_DIR, template))
    end
  end

  def default_data
    {
      "tap_name"       => "ivuorinen/homebrew-tap",
      "generated_at"   => Time.now.strftime("%Y-%m-%dT%H:%M:%S%z"),
      "formulae_count" => 0,
      "formulae"       => [],
    }
  end
end

# Allow running this script directly
SiteBuilder.build if __FILE__ == $PROGRAM_NAME
