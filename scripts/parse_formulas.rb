#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "date"

# Parser class for extracting metadata from Homebrew formulae
class FormulaParser
  FORMULA_DIR = File.expand_path("../Formula", __dir__).freeze
  OUTPUT_DIR = File.expand_path("../docs/_data", __dir__).freeze
  OUTPUT_FILE = File.join(OUTPUT_DIR, "formulae.json").freeze

  # Regex patterns for safe extraction without code evaluation
  PATTERNS = {
    class_name: /^class\s+(\w+)\s+<\s+Formula/,
    desc:       /^\s*desc\s+["']([^"']+)["']/,
    homepage:   /^\s*homepage\s+["']([^"']+)["']/,
    url:        /^\s*url\s+["']([^"']+)["']/,
    version:    /^\s*version\s+["']([^"']+)["']/,
    sha256:     /^\s*sha256\s+["']([a-f0-9]{64})["']/i,
    license:    /^\s*license\s+["']([^"']+)["']/,
    depends_on: /^\s*depends_on\s+["']([^"']+)["']/,
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
    formula_files.filter_map { |file| parse_formula(file) }.sort_by { |f| f[:name] }
  end

  def formula_files
    Dir.glob(File.join(FORMULA_DIR, "**", "*.rb"))
  end

  def parse_formula(file_path)
    content = File.read(file_path)
    class_name = extract_value(content, :class_name)

    return unless class_name

    formula_name = convert_class_name_to_formula_name(class_name)

    return if formula_name.blank?

    build_formula_metadata(content, file_path, formula_name, class_name)
  rescue => e
    warn "⚠️  Error parsing #{file_path}: #{e.message}"
    nil
  end

  def build_formula_metadata(content, file_path, formula_name, class_name)
    {
      name:          formula_name,
      class_name:    class_name,
      description:   extract_value(content, :desc),
      homepage:      extract_value(content, :homepage),
      url:           extract_value(content, :url),
      version:       extract_version(content),
      sha256:        extract_value(content, :sha256),
      license:       extract_value(content, :license),
      dependencies:  extract_dependencies(content),
      file_path:     calculate_relative_path(file_path),
      last_modified: format_time_iso8601(File.mtime(file_path)),
    }
  end

  def calculate_relative_path(file_path)
    Pathname.new(file_path).relative_path_from(Pathname.new(FORMULA_DIR)).to_s
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
    return unless url

    # Common version patterns in URLs
    url.match(/v?(\d+(?:\.\d+)+)/)&.[](1)
  end

  def extract_dependencies(content)
    content.scan(PATTERNS[:depends_on]).flatten.uniq
  end

  def convert_class_name_to_formula_name(class_name)
    return unless class_name

    # Convert CamelCase to kebab-case
    class_name
      .gsub(/([a-z\d])([A-Z])/, "\1-\2")
      .downcase
  end

  def format_time_iso8601(time)
    # Format time manually for compatibility
    time.strftime("%Y-%m-%dT%H:%M:%S%z").gsub(/(\d{2})(\d{2})$/, "\1:\2")
  end

  def write_json_output(formulae)
    output = {
      tap_name:       "ivuorinen/tap",
      generated_at:   format_time_iso8601(Time.now),
      formulae_count: formulae.length,
      formulae:       formulae,
    }

    File.write(OUTPUT_FILE, JSON.pretty_generate(output))
  end
end

# Run if executed directly
FormulaParser.run if __FILE__ == $PROGRAM_NAME
