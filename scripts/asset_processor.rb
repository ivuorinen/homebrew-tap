# frozen_string_literal: true

require "fileutils"
require "terser"
require "tailwindcss/ruby"

# Module for processing and copying assets
module AssetProcessor
  DOCS_DIR = File.expand_path("../docs", __dir__).freeze
  OUTPUT_DIR = DOCS_DIR
  THEME_SOURCE_DIR = File.expand_path("../theme", __dir__).freeze

  def copy_assets
    assets_source_dir = File.join(THEME_SOURCE_DIR, "assets")
    assets_output_dir = File.join(OUTPUT_DIR, "assets")

    FileUtils.mkdir_p(assets_output_dir)

    unless Dir.exist?(assets_source_dir)
      puts "⚠️  Assets source directory not found: #{assets_source_dir}"
      return
    end

    asset_files = Dir.glob(File.join(assets_source_dir, "**", "*")).reject { |f| File.directory?(f) }

    asset_files.each do |source_file|
      relative_path = Pathname.new(source_file).relative_path_from(Pathname.new(assets_source_dir))
      output_file = File.join(assets_output_dir, relative_path)

      FileUtils.mkdir_p(File.dirname(output_file))
      FileUtils.cp(source_file, output_file)
    end

    puts "📁 Copied #{asset_files.count} asset files to #{assets_output_dir}"
  end

  # Compile Tailwind at build time so the pages ship a static, versioned
  # stylesheet instead of loading the Play CDN, which Tailwind documents as
  # development-only and which ran unpinned third-party script on every page.
  def generate_css
    css_path = File.join(THEME_SOURCE_DIR, "style.css")
    output_path = File.join(OUTPUT_DIR, "style.css")

    return unless File.exist?(css_path)

    system(Tailwindcss::Ruby.executable, "--input", css_path, "--output", output_path,
           "--minify", "--silent", exception: true)
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
end
