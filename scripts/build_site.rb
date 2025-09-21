#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "erb"
require "pathname"
require "time"

# Simple static site generator for homebrew tap documentation
class SiteBuilder
  include ERB::Util

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

    def get_binding
      binding
    end
  end
  DOCS_DIR = File.expand_path("../docs", __dir__)
  DATA_DIR = File.join(DOCS_DIR, "_data")
  OUTPUT_DIR = DOCS_DIR
  THEME_SOURCE_DIR = File.expand_path("../theme", __dir__)
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
    puts "🌐 Open #{File.join(OUTPUT_DIR, 'index.html')} in your browser"
  end

  def render_partial(name, locals = {})
    partial_path = File.join(TEMPLATES_DIR, "_#{name}.html.erb")
    raise ArgumentError, "Partial not found: #{partial_path}" unless File.exist?(partial_path)

    context = PartialContext.new(self, locals)
    ERB.new(File.read(partial_path)).result(context.get_binding)
  end

  def format_relative_time(timestamp)
    return "" unless timestamp

    begin
      time = Time.parse(timestamp)
      now = Time.now
      diff = now - time

      case diff
      when 0..59
        "just now"
      when 60..3599
        mins = (diff / 60).to_i
        "#{mins} minute#{'s' unless mins == 1} ago"
      when 3600..86_399
        hours = (diff / 3600).to_i
        "#{hours} hour#{'s' unless hours == 1} ago"
      when 86_400..604_799
        days = (diff / 86_400).to_i
        "#{days} day#{'s' unless days == 1} ago"
      when 604_800..2_419_199
        weeks = (diff / 604_800).to_i
        "#{weeks} week#{'s' unless weeks == 1} ago"
      when 2_419_200..31_535_999
        months = (diff / 2_419_200).to_i
        "#{months} month#{'s' unless months == 1} ago"
      else
        years = (diff / 31_536_000).to_i
        "#{years} year#{'s' unless years == 1} ago"
      end
    rescue StandardError
      ""
    end
  end

  def format_date(timestamp)
    return "" unless timestamp

    begin
      Time.parse(timestamp).strftime("%b %d, %Y")
    rescue StandardError
      ""
    end
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

  def copy_assets
    assets_source_dir = File.join(THEME_SOURCE_DIR, "assets")
    assets_output_dir = File.join(OUTPUT_DIR, "assets")

    # Create the output assets directory if it doesn"t exist
    FileUtils.mkdir_p(assets_output_dir)

    # Check if source assets directory exists
    if Dir.exist?(assets_source_dir)
      # Copy all files recursively, preserving directory structure
      Dir.glob(File.join(assets_source_dir, "**", "*")).each do |source_file|
        next if File.directory?(source_file)

        # Calculate relative path from source assets dir
        relative_path = Pathname.new(source_file).relative_path_from(Pathname.new(assets_source_dir))
        output_file = File.join(assets_output_dir, relative_path)

        # Create parent directories if needed
        FileUtils.mkdir_p(File.dirname(output_file))

        # Copy the file
        FileUtils.cp(source_file, output_file)
      end

      asset_count = Dir.glob(File.join(assets_source_dir, "**", "*")).reject { |f| File.directory?(f) }.size
      puts "📁 Copied #{asset_count} asset files to #{assets_output_dir}"
    else
      puts "⚠️  Assets source directory not found: #{assets_source_dir}"
    end
  end

  def generate_css
    css_source_path = File.join(THEME_SOURCE_DIR, "style.css")
    css_output_path = File.join(OUTPUT_DIR, "style.css")

    if File.exist?(css_source_path)
      css_content = File.read(css_source_path)
      minified_css = minify_css(css_content)
      File.write(css_output_path, minified_css)
      puts "📄 Generated and minified CSS (#{minified_css.length} bytes)"
    else
      puts "⚠️  CSS source file not found: #{css_source_path}"
    end
  end

  def minify_css(css)
    css
      .gsub(%r{/\*.*?\*/}m, "") # Remove comments
      .gsub(/\s+/, " ")       # Collapse whitespace
      .gsub(/\s*{\s*/, "{")   # Remove spaces around braces
      .gsub(/\s*}\s*/, "}")
      .gsub(/\s*:\s*/, ":")     # Remove spaces around colons
      .gsub(/\s*;\s*/, ";")     # Remove spaces around semicolons
      .gsub(/\s*,\s*/, ",")     # Remove spaces around commas
      .strip
  end

  def minify_js
    js_source_path = File.join(THEME_SOURCE_DIR, "main.js")
    js_output_path = File.join(OUTPUT_DIR, "main.js")

    if File.exist?(js_source_path)
      js_content = File.read(js_source_path)
      minified_js = minify_js_content(js_content)
      File.write(js_output_path, minified_js)
      puts "📄 Generated and minified JavaScript (#{minified_js.length} bytes)"
    else
      puts "⚠️  JavaScript source file not found: #{js_source_path}"
    end
  end

  def minify_js_content(js)
    # Simple minification that preserves string literals
    # This is a basic approach that handles most cases
    result = []
    in_string = false
    in_template = false
    string_char = nil
    i = 0

    while i < js.length
      char = js[i]
      prev_char = i.positive? ? js[i - 1] : nil

      # Handle string and template literal boundaries
      if !in_string && !in_template && ['"', "'", "`"].include?(char)
        in_string = true if char != "`"
        in_template = true if char == "`"
        string_char = char
        result << char
      elsif (in_string || in_template) && char == string_char && prev_char != "\\"
        in_string = false
        in_template = false
        string_char = nil
        result << char
      elsif in_string || in_template
        # Preserve everything inside strings and template literals
        result << char
      elsif char == "/" && i + 1 < js.length
        # Outside strings, apply minification
        next_char = js[i + 1]
        if next_char == "/"
          # Skip single-line comment
          i += 1 while i < js.length && js[i] != "\n"
          next
        elsif next_char == "*"
          # Skip multi-line comment
          i += 2
          while i < js.length - 1
            break if js[i] == "*" && js[i + 1] == "/"

            i += 1
          end
          i += 1 # Skip the closing /
          next
        else
          result << char
        end
      elsif char =~ /\s/
        # Only add space if needed between identifiers
        if result.last && result.last =~ /[a-zA-Z0-9_$]/ &&
           i + 1 < js.length && js[i + 1] =~ /[a-zA-Z0-9_$]/
          result << " "
        end
      else
        result << char
      end

      i += 1
    end

    result.join.strip
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
    File.write(File.join(formula_dir, "#{formula['name']}.html"), content)
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
      "tap_name" => "ivuorinen/homebrew-tap",
      "generated_at" => Time.now.strftime("%Y-%m-%dT%H:%M:%S%z"),
      "formulae_count" => 0,
      "formulae" => []
    }
  end
end

# Allow running this script directly
SiteBuilder.build if __FILE__ == $PROGRAM_NAME
