#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "date"

# Parser class for extracting metadata from Homebrew formulae
class FormulaParser
  FORMULA_DIR = File.expand_path("../Formula", __dir__).freeze
  OUTPUT_DIR = File.expand_path("../docs/_data", __dir__).freeze
  OUTPUT_FILE = File.join(OUTPUT_DIR, "formulae.json").freeze
  # The one definition of the tap's name; the site reads it from formulae.json.
  TAP_NAME = "ivuorinen/tap"

  # Raised for a formula file whose metadata cannot be extracted.
  class ParseError < StandardError; end

  # A Ruby string literal, double- or single-quoted, with backslash escapes.
  # sync_formulae.rb writes values with String#inspect, so a desc can contain
  # `\"`; the old `[^"']+` stopped at the first quote and truncated it.
  QUOTED = /(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')/

  # Regex patterns for safe extraction without code evaluation
  PATTERNS = {
    class_name:  /^class\s+(\w+)\s+<\s+Formula/,
    desc:        /^\s*desc\s+#{QUOTED}/,
    homepage:    /^\s*homepage\s+#{QUOTED}/,
    url:         /^\s*url\s+#{QUOTED}/,
    version:     /^\s*version\s+#{QUOTED}/,
    sha256:      /^\s*sha256\s+["']([a-f0-9]{64})["']/i,
    license:     /^\s*license\s+#{QUOTED}/,
    depends_on:  /^\s*depends_on\s+#{QUOTED}/,
    released_at: /^#\s*released:\s*(\S+)/,
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

  # Every formula file must parse. A failure aborts the run after listing all
  # of them: dropping the file instead made the formula vanish from the site
  # while the build reported success.
  def parse_all_formulae
    failures = []
    formulae = formula_files.filter_map do |file|
      parse_formula(file)
    rescue => e
      failures << "#{file}: #{e.message}"
      nil
    end
    abort "❌ Could not parse:\n#{failures.map { |f| "  #{f}" }.join("\n")}" unless failures.empty?

    formulae.sort_by { |f| f[:name] }
  end

  def formula_files
    Dir.glob(File.join(FORMULA_DIR, "**", "*.rb"))
  end

  def parse_formula(file_path)
    content = File.read(file_path)
    class_name = extract_value(content, :class_name)
    raise ParseError, "no `class <Name> < Formula` line" unless class_name

    # The filename IS the Homebrew formula name (incl. "@version" for versioned
    # formulae). Deriving it from the class name can't round-trip the versioned
    # "AT<digits>" mangling, so use the basename directly.
    formula_name = File.basename(file_path, ".rb")

    build_formula_metadata(content, file_path, formula_name, class_name)
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
      released_at:   extract_value(content, :released_at),
      last_modified: format_time_iso8601(File.mtime(file_path)),
    }
  end

  def calculate_relative_path(file_path)
    Pathname.new(file_path).relative_path_from(Pathname.new(FORMULA_DIR)).to_s
  end

  # The first match's literal text, with backslash escapes removed.
  def extract_value(content, pattern_key)
    match = content.match(PATTERNS[pattern_key])
    match && unescape(match.captures.compact.first)
  end

  # Undo the escapes String#inspect writes for `"`, `\` and `#`. A generated
  # desc never holds \n or \t: sanitize_desc collapses whitespace first.
  def unescape(str)
    str.gsub(/\\(.)/, '\1')
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
    content.scan(PATTERNS[:depends_on]).map { |groups| unescape(groups.compact.first) }.uniq
  end

  def format_time_iso8601(time)
    # Format time manually for compatibility
    time.strftime("%Y-%m-%dT%H:%M:%S%z").gsub(/(\d{2})(\d{2})$/, '\1:\2')
  end

  def write_json_output(formulae)
    output = {
      tap_name:       TAP_NAME,
      generated_at:   format_time_iso8601(Time.now),
      formulae_count: formulae.length,
      formulae:       formulae,
    }

    File.write(OUTPUT_FILE, JSON.pretty_generate(output))
  end
end

# Run if executed directly
FormulaParser.run if __FILE__ == $PROGRAM_NAME
