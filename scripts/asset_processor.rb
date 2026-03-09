# typed: strict
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "terser"
require "cssminify2"

# Module for processing and copying assets
module AssetProcessor
  DOCS_DIR = File.expand_path("../docs", __dir__).freeze
  OUTPUT_DIR = DOCS_DIR
  THEME_SOURCE_DIR = File.expand_path("../theme", __dir__).freeze

  def copy_assets
    copy_asset_files
  end

  def generate_css
    css_path = File.join(THEME_SOURCE_DIR, "style.css")
    output_path = File.join(OUTPUT_DIR, "style.css")

    return unless File.exist?(css_path)

    css_content = File.read(css_path)
    minified_css = CSSminify2.compress(css_content)
    File.write(output_path, minified_css)
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
end
