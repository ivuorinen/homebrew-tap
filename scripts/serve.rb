#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "webrick"
require "fileutils"
require_relative "parse_formulas"
require_relative "build_site"
require_relative "file_watcher"

# Development server with file watching for homebrew tap documentation
class DevServer
  include FileWatcher

  def self.serve(port: 4000, host: "localhost")
    new(port: port, host: host).start
  end

  def initialize(port: 4000, host: "localhost")
    @port = port
    @host = host
    @site_dir = File.expand_path("../docs", __dir__)
    @docs_dir = File.expand_path("../docs", __dir__)
  end

  def start
    puts "🔄 Building site..."
    build_site

    puts "🚀 Starting development server..."
    puts "📍 Server address: http://#{@host}:#{@port}"
    puts "📁 Serving from: #{@site_dir}"
    puts "💡 Press Ctrl+C to stop"

    start_server
  end

  private

  def build_site
    # Generate formulae data
    FormulaParser.run

    # Build static site
    SiteBuilder.build
  end

  def start_server
    server = WEBrick::HTTPServer.new(
      Port:         @port,
      Host:         @host,
      DocumentRoot: @site_dir,
      Logger:       WEBrick::Log.new($stderr, WEBrick::Log::INFO),
      AccessLog:    [[
        $stderr,
        WEBrick::AccessLog::COMBINED_LOG_FORMAT,
      ]],
    )

    # Handle Ctrl+C gracefully
    trap("INT") do
      puts "\n👋 Stopping server..."
      server.shutdown
    end

    # Add custom mime types if needed
    server.config[:MimeTypes]["json"] = "application/json"

    # Add auto-rebuild on file changes (simple polling)
    start_file_watcher

    server.start
  end
end

# Command line interface
if __FILE__ == $PROGRAM_NAME
  # Check for --list-watched flag
  if ARGV.include?("--list-watched")
    server = DevServer.new
    files = server.all_watched_files.select { |f| File.exist?(f) && !File.directory?(f) }
    puts "📋 Watching #{files.count} files:"
    files.sort.each { |f| puts "  - #{f.sub("#{File.expand_path("..", __dir__)}/", "")}" }
    exit 0
  end

  port = ARGV[0]&.to_i || 4000
  host = ARGV[1] || "localhost"

  DevServer.serve(port: port, host: host)
end
