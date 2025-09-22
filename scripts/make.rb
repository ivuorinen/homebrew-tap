#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "fileutils"

# Simple make-style command runner for homebrew tap
class Make
  COMMANDS = {
    "build" => "Build the static site",
    "serve" => "Start development server",
    "parse" => "Parse formulae and generate JSON data",
    "clean" => "Clean generated files",
    "help" => "Show this help message"
  }.freeze

  def self.run(command = nil)
    new.execute(command || ARGV[0])
  end

  def execute(command)
    case command&.downcase
    when "build"
      build
    when "serve"
      serve
    when "parse"
      parse
    when "clean"
      clean
    when "help", nil
      help
    else
      puts "❌ Unknown command: #{command}"
      help
      exit 1
    end
  end

  private

  def build
    puts "🏗️  Building homebrew tap documentation..."

    success = system("ruby", script_path("parse_formulas.rb"))
    exit 1 unless success

    success = system("ruby", script_path("build_site.rb"))
    exit 1 unless success

    puts "✅ Build complete!"
  end

  def serve
    port = ARGV[1]&.to_i || 4000
    host = ARGV[2] || "localhost"

    puts "🚀 Starting development server on http://#{host}:#{port}"

    exec("ruby", script_path("serve.rb"), port.to_s, host)
  end

  def parse
    puts "📋 Parsing formulae..."

    success = system("ruby", script_path("parse_formulas.rb"))
    exit 1 unless success

    puts "✅ Formulae parsing complete!"
  end

  def clean
    puts "🧹 Cleaning generated files..."

    files_to_clean = [
      docs_path("index.html"),
      docs_path("formulae.html"),
      docs_path("formula"),
      docs_path("_templates"),
      docs_path("_data", "formulae.json"),
      docs_path("style.css"),
      docs_path("main.js")
    ]

    files_to_clean.each do |path|
      if File.exist?(path)
        FileUtils.rm_rf(path)
        puts "  🗑️  Removed #{path}"
      end
    end

    puts "✅ Clean complete!"
  end

  def help
    puts "Homebrew Tap Documentation Builder"
    puts
    puts "Usage: ruby scripts/make.rb <command>"
    puts
    puts "Commands:"
    COMMANDS.each do |cmd, desc|
      puts "  #{cmd.ljust(10)} #{desc}"
    end
    puts
    puts "Examples:"
    puts "  ruby scripts/make.rb build           # Build the site"
    puts "  ruby scripts/make.rb serve           # Start server on port 4000"
    puts "  ruby scripts/make.rb serve 3000      # Start server on port 3000"
    puts "  ruby scripts/make.rb serve 3000 0.0.0.0  # Start server on all interfaces"
  end

  def script_path(filename)
    File.join(__dir__, filename)
  end

  def docs_path(*parts)
    File.join(__dir__, "..", "docs", *parts)
  end
end

# Run if executed directly
Make.run if __FILE__ == $PROGRAM_NAME
