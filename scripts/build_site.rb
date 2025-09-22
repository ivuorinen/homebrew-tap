#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "erb"
require "pathname"
require "time"

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
  def copy_assets
    copy_asset_files
  end

  def generate_css
    css_path = File.join(THEME_SOURCE_DIR, "style.css")
    output_path = File.join(OUTPUT_DIR, "style.css")

    return unless File.exist?(css_path)

    css_content = File.read(css_path)
    minified_css = minify_css(css_content)
    File.write(output_path, minified_css)
    puts "📄 Generated CSS file: #{output_path}"
  end

  def minify_js
    js_path = File.join(THEME_SOURCE_DIR, "main.js")
    output_path = File.join(OUTPUT_DIR, "main.js")

    return unless File.exist?(js_path)

    js_content = File.read(js_path)
    minified_js = JavaScriptMinifier.minify(js_content)
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

  def minify_css(css)
    css.gsub(%r{/\*.*?\*/}m, "")
       .gsub(/\s+/, " ")
       .gsub(/;\s*}/, "}")
       .strip
  end
end

# Helper module for JavaScript character handling
module JavaScriptCharacters
  NEWLINE_CHARS = ["\n", "\r"].freeze
  WHITESPACE_CHARS = [" ", "\t"].freeze
  SPECIAL_CHARS = [";", "{", "}", "(", ")", ",", ":", "=", "+", "-", "*", "/", "%", "!", "&", "|", "^", "~", "<",
                   ">", "?"].freeze
end

# Helper module for JavaScript comment and string processing
module JavaScriptProcessor
  include JavaScriptCharacters

  private

  def skip_line_comment(index)
    index += 1 while index < javascript.length && javascript[index] != "\n"
    index
  end

  def skip_block_comment(index)
    index += 2
    while index < javascript.length - 1
      break if javascript[index] == "*" && javascript[index + 1] == "/"

      index += 1
    end
    index + 2
  end

  def process_string_content(result, quote_char, index)
    while index < javascript.length && javascript[index] != quote_char
      result += javascript[index]
      index += 1 if javascript[index] == "\\"
      index += 1
    end
    index
  end

  def append_closing_quote(result, index)
    result << javascript[index] if index < javascript.length
  end

  def skip_to_next_line(index)
    index += 1 while index < javascript.length && NEWLINE_CHARS.include?(javascript[index])
    index
  end

  def skip_whitespace(index)
    index += 1 while index < javascript.length && WHITESPACE_CHARS.include?(javascript[index])
    index
  end

  def preserve_space?(result)
    return false if result.empty?

    last_char = result[-1]
    [";", "{", "}", "(", ")", ",", ":", "=", "+", "-", "*", "/", "%", "!", "&", "|", "^", "~", "<", ">",
     "?"].exclude?(last_char)
  end

  attr_reader :javascript
end

# Module for JavaScript minification
module JavaScriptMinifier
  include JavaScriptProcessor

  def self.minify(javascript)
    new(javascript).minify
  end

  def initialize(javascript)
    @javascript = javascript
  end

  def minify
    remove_comments_and_whitespace
  end

  private

  def remove_comments_and_whitespace
    result = ""
    i = 0

    while i < javascript.length
      char = javascript[i]

      case char
      when "/"
        i = handle_slash(result, i)
      when '"', "'"
        i = handle_string_literal(result, char, i)
      when "\n", "\r"
        i = handle_newline(result, i)
      when " ", "\t"
        i = handle_whitespace(result, i)
      else
        result += char
        i += 1
      end
    end

    result
  end

  def handle_slash(_result, index)
    if index + 1 < javascript.length
      next_char = javascript[index + 1]
      case next_char
      when "/"
        skip_line_comment(index)
      when "*"
        skip_block_comment(index)
      else
        javascript[index]
        index + 1
      end
    else
      javascript[index]
      index + 1
    end
  end

  def handle_string_literal(result, quote_char, index)
    result += javascript[index]
    index += 1

    index = process_string_content(result, quote_char, index)
    append_closing_quote(result, index)
    index + 1
  end

  def handle_newline(result, index)
    result << " " if preserve_space?(result)
    skip_to_next_line(index)
  end

  def handle_whitespace(result, index)
    result << " " if preserve_space?(result)
    skip_whitespace(index)
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
