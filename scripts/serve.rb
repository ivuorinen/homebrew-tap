#!/usr/bin/env ruby
# frozen_string_literal: true

require "webrick"
require "fileutils"
require_relative "parse_formulas"
require_relative "build_site"

# Simple development server for the homebrew tap documentation
class DevServer
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
      Port: @port,
      Host: @host,
      DocumentRoot: @site_dir,
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO),
      AccessLog: [[
        $stderr,
        WEBrick::AccessLog::COMBINED_LOG_FORMAT
      ]]
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

  def start_file_watcher
    Thread.new do
      last_mtime = get_max_mtime
      rebuild_pending = false
      watched_files = get_watched_files_count

      puts "👀 Watching #{watched_files} files for changes..."

      loop do
        sleep 1
        current_mtime = get_max_mtime

        next unless current_mtime > last_mtime && !rebuild_pending

        rebuild_pending = true
        changed_file = find_changed_file(last_mtime)
        puts "📝 Changed: #{changed_file}" if changed_file
        puts "🔄 Rebuilding in 1 second..."

        # Debounce: wait for additional changes
        sleep 1

        # Check if more changes occurred during debounce period
        final_mtime = get_max_mtime

        puts "🔨 Building site..."
        build_site
        last_mtime = final_mtime
        rebuild_pending = false
        puts "✅ Rebuild complete"
      end
    end
  end

  def get_watched_files_count
    files = get_all_watched_files
    files.select { |f| File.exist?(f) && !File.directory?(f) }.count
  end

  def find_changed_file(since_time)
    files = get_all_watched_files
    files.select { |f| File.exist?(f) && !File.directory?(f) }
         .find { |f| File.mtime(f) > since_time }
         &.sub("#{File.expand_path('..', __dir__)}/", "")
  end

  def get_all_watched_files
    [
      # Watch Formula files for changes
      Dir.glob(File.expand_path("../Formula/**/*.rb", __dir__)),
      # Watch all theme files including partials
      Dir.glob(File.expand_path("../theme/**/*", __dir__)),
      # Specifically watch for erb templates and partials
      Dir.glob(File.expand_path("../theme/*.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/_*.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/*.html.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/_*.html.erb", __dir__)),
      # Watch CSS and JS
      Dir.glob(File.expand_path("../theme/*.css", __dir__)),
      Dir.glob(File.expand_path("../theme/*.js", __dir__)),
      # Watch assets directory
      Dir.glob(File.expand_path("../theme/assets/**/*", __dir__)),
      # Watch build scripts for changes
      [File.expand_path("../scripts/parse_formulas.rb", __dir__)],
      [File.expand_path("../scripts/build_site.rb", __dir__)],
      # Watch Makefile
      [File.expand_path("../Makefile", __dir__)]
    ].flatten.compact.uniq
  end

  def get_max_mtime
    files_to_watch = get_all_watched_files

    # Filter out non-existent files and directories, get modification times
    existing_files = files_to_watch.select { |f| File.exist?(f) && !File.directory?(f) }

    if existing_files.empty?
      Time.at(0)
    else
      existing_files.map { |f| File.mtime(f) }.max
    end
  end
end

# Command line interface
if __FILE__ == $PROGRAM_NAME
  # Check for --list-watched flag
  if ARGV.include?("--list-watched")
    server = DevServer.new
    files = server.send(:get_all_watched_files).select { |f| File.exist?(f) && !File.directory?(f) }
    puts "📋 Watching #{files.count} files:"
    files.sort.each { |f| puts "  - #{f.sub("#{File.expand_path('..', __dir__)}/", '')}" }
    exit 0
  end

  port = ARGV[0]&.to_i || 4000
  host = ARGV[1] || "localhost"

  DevServer.serve(port: port, host: host)
end
