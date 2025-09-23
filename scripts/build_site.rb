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

# Simple polyfill for Homebrew extensions
class Array
  def exclude?(item)
    !include?(item)
  end
end

# Simple static site generator for homebrew tap documentation
# Module for formatting timestamps and dates
module TimeFormatter
  SECONDS_PER_MINUTE = 60
  SECONDS_PER_HOUR = 3600
  SECONDS_PER_DAY = 86_400
  SECONDS_PER_WEEK = 604_800
  SECONDS_PER_MONTH = 2_419_200
  SECONDS_PER_YEAR = 31_536_000

  def format_relative_time(timestamp)
    return "" unless timestamp

    begin
      diff = calculate_time_difference(timestamp)
      return "just now" if diff < SECONDS_PER_MINUTE

      format_time_by_category(diff)
    rescue
      ""
    end
  end

  def format_date(timestamp)
    return "" unless timestamp

    begin
      Time.parse(timestamp).strftime("%b %d, %Y")
    rescue
      ""
    end
  end

  private

  def calculate_time_difference(timestamp)
    time = Time.parse(timestamp)
    Time.now - time
  end

  def format_time_by_category(diff)
    case diff
    when SECONDS_PER_MINUTE...SECONDS_PER_HOUR
      format_time_unit(diff / SECONDS_PER_MINUTE, "minute")
    when SECONDS_PER_HOUR...SECONDS_PER_DAY
      format_time_unit(diff / SECONDS_PER_HOUR, "hour")
    when SECONDS_PER_DAY...SECONDS_PER_WEEK
      format_time_unit(diff / SECONDS_PER_DAY, "day")
    when SECONDS_PER_WEEK...SECONDS_PER_MONTH
      format_time_unit(diff / SECONDS_PER_WEEK, "week")
    when SECONDS_PER_MONTH...SECONDS_PER_YEAR
      format_time_unit(diff / SECONDS_PER_MONTH, "month")
    else
      format_time_unit(diff / SECONDS_PER_YEAR, "year")
    end
  end

  def format_time_unit(value, unit)
    count = value.to_i
    "#{count} #{unit}#{"s" if count != 1} ago"
  end
end

# Module for processing and copying assets
module AssetProcessor
  DOCS_DIR = File.expand_path("../docs", __dir__).freeze
  OUTPUT_DIR = DOCS_DIR
  THEME_SOURCE_DIR = File.expand_path("../theme", __dir__).freeze

  def copy_assets
    copy_asset_files
  end

  def generate_css
    css_path = File.join(THEME_SOURCE_DIR, "style.css")
    output_path = File.join(OUTPUT_DIR, "style.css")

    return unless File.exist?(css_path)

    css_content = File.read(css_path)
    minified_css = CSSminify2.compress(css_content)
    File.write(output_path, minified_css)
    puts "📄 Generated CSS file: #{output_path}"
  end

  def minify_js
    js_path = File.join(THEME_SOURCE_DIR, "main.js")
    output_path = File.join(OUTPUT_DIR, "main.js")

    return unless File.exist?(js_path)

    js_content = File.read(js_path)
    minified_js = Terser.new.compile(js_content)
    File.write(output_path, minified_js)
    puts "🔧 Generated JS file: #{output_path}"
  end

  private

  def copy_asset_files
    assets_source_dir = File.join(THEME_SOURCE_DIR, "assets")
    assets_output_dir = File.join(OUTPUT_DIR, "assets")

    FileUtils.mkdir_p(assets_output_dir)

    return handle_missing_assets(assets_source_dir) unless Dir.exist?(assets_source_dir)

    copy_files_recursively(assets_source_dir, assets_output_dir)
  end

  def handle_missing_assets(assets_source_dir)
    puts "⚠️  Assets source directory not found: #{assets_source_dir}"
  end

  def copy_files_recursively(source_dir, output_dir)
    asset_files = Dir.glob(File.join(source_dir, "**", "*")).reject { |f| File.directory?(f) }

    asset_files.each do |source_file|
      copy_single_asset(source_file, source_dir, output_dir)
    end

    puts "📁 Copied #{asset_files.count} asset files to #{output_dir}"
  end

  def copy_single_asset(source_file, source_dir, output_dir)
    relative_path = Pathname.new(source_file).relative_path_from(Pathname.new(source_dir))
    output_file = File.join(output_dir, relative_path)

    FileUtils.mkdir_p(File.dirname(output_file))
    FileUtils.cp(source_file, output_file)
  end
end

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
