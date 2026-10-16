# frozen_string_literal: true

# Module for handling file watching and change detection.
# Classes including this module must define a `build_site` method.
module FileWatcher
  # One thread polls and rebuilds sequentially, so a rebuild can never overlap
  # another; no pending flag is needed.
  def start_file_watcher
    Thread.new do
      last_mtime = max_mtime
      watched_files = watched_files_count

      puts "👀 Watching #{watched_files} files for changes..."

      loop do
        sleep 1
        current_mtime = max_mtime

        next if current_mtime <= last_mtime

        handle_file_change(last_mtime)
        last_mtime = perform_rebuild_with_debounce
        puts "✅ Rebuild complete"
      rescue => e
        puts "⚠️  File watcher error: #{e.message}"
        puts "📍 Backtrace: #{e.backtrace.first(3).join(", ")}"
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

  # Templates, CSS, JS and assets: everything under theme/.
  def theme_files
    Dir.glob(File.expand_path("../theme/**/*", __dir__))
  end

  # Reloaded on each rebuild, since DevServer#build_site runs them as child
  # processes.
  def build_script_files
    %w[parse_formulas build_site asset_processor time_formatter].map do |name|
      File.expand_path("../scripts/#{name}.rb", __dir__)
    end
  end

  def config_files
    [File.expand_path("../Makefile", __dir__)]
  end
end
