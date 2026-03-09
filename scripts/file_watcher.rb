# typed: strict
# frozen_string_literal: true

# Module for handling file watching and change detection.
# Classes including this module must define a `build_site` method.
module FileWatcher
  def start_file_watcher
    Thread.new do
      last_mtime = max_mtime
      rebuild_pending = false
      watched_files = watched_files_count

      puts "👀 Watching #{watched_files} files for changes..."

      loop do
        sleep 1
        current_mtime = max_mtime

        next if should_skip_rebuild?(current_mtime, last_mtime, rebuild_pending)

        rebuild_pending = true
        handle_file_change(last_mtime)
        last_mtime = perform_rebuild_with_debounce
        rebuild_pending = false
        puts "✅ Rebuild complete"
      rescue => e
        puts "⚠️  File watcher error: #{e.message}"
        puts "📍 Backtrace: #{e.backtrace.first(3).join(", ")}"
        rebuild_pending = false
        sleep 2
        puts "🔄 File watcher continuing..."
      end
    end
  end

  def watched_files_count
    all_watched_files.count { |file| !File.directory?(file) }
  end

  def find_changed_file(since_mtime)
    all_watched_files.find do |file|
      File.exist?(file) && !File.directory?(file) && File.mtime(file) > since_mtime
    end
  end

  def all_watched_files
    [
      formula_files,
      theme_files,
      template_files,
      style_and_script_files,
      asset_files,
      build_script_files,
      config_files,
    ].flatten.compact.uniq
  end

  def max_mtime
    all_watched_files
      .select { |file| File.exist?(file) && !File.directory?(file) }
      .map { |file| File.mtime(file) }
      .max || Time.at(0)
  end

  private

  def should_skip_rebuild?(current_mtime, last_mtime, rebuild_pending)
    current_mtime <= last_mtime || rebuild_pending
  end

  def handle_file_change(last_mtime)
    changed_file = find_changed_file(last_mtime)
    puts "📝 Changed: #{changed_file}" if changed_file
    puts "🔄 Rebuilding in 1 second..."
  end

  def perform_rebuild_with_debounce
    sleep 1 # Debounce: wait for additional changes
    final_mtime = max_mtime
    puts "🔨 Building site..."
    build_site
    final_mtime
  end

  def formula_files
    Dir.glob(File.expand_path("../Formula/**/*.rb", __dir__))
  end

  def theme_files
    Dir.glob(File.expand_path("../theme/**/*", __dir__))
  end

  def template_files
    [
      Dir.glob(File.expand_path("../theme/*.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/_*.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/*.html.erb", __dir__)),
      Dir.glob(File.expand_path("../theme/_*.html.erb", __dir__)),
    ].flatten
  end

  def style_and_script_files
    [
      Dir.glob(File.expand_path("../theme/*.css", __dir__)),
      Dir.glob(File.expand_path("../theme/*.js", __dir__)),
    ].flatten
  end

  def asset_files
    Dir.glob(File.expand_path("../theme/assets/**/*", __dir__))
  end

  def build_script_files
    [
      File.expand_path("../scripts/parse_formulas.rb", __dir__),
      File.expand_path("../scripts/build_site.rb", __dir__),
    ]
  end

  def config_files
    [File.expand_path("../Makefile", __dir__)]
  end
end
