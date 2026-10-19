#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline unit check for the pure functions in sync_formulae.rb, and for the
# stage contracts downstream of it: formula file -> FormulaParser, and
# formulae.json -> SiteBuilder#group_formulae.
# No network: feeds recorded asset lists from the four seed repos.
# Run: bundle exec ruby scripts/test_sync_formulae.rb

require "prism"
require "tmpdir"
require_relative "sync_formulae"
require_relative "parse_formulas"
require_relative "build_site"

# Offline checks for SyncFormulae's pure functions using recorded asset fixtures.
class TestSyncFormulae
  FAKE = "sha256:#{"a" * 64}".freeze

  # Seed repo names reused across fixtures and checks.
  ACTION_README = "gh-action-readme"
  HISTORY       = "gh-history"
  CALVER        = "gh-calver"

  def self.asset(name)
    { "name" => name, "browser_download_url" => "https://example/#{name}", "digest" => FAKE }
  end

  # Recorded asset-name shapes (the divergent conventions we must handle).
  FIXTURES = {
    "a"           => %w[
      a_1.0.0_darwin_amd64 a_1.0.0_darwin_amd64.tar.gz a_1.0.0_darwin_amd64.tar.gz.sbom.json
      a_1.0.0_darwin_arm64 a_1.0.0_darwin_arm64.tar.gz
      a_1.0.0_linux_386 a_1.0.0_linux_386.tar.gz a_1.0.0_linux_amd64 a_1.0.0_linux_amd64.deb
      a_1.0.0_linux_amd64.tar.gz a_1.0.0_linux_arm64 a_1.0.0_linux_arm64.tar.gz
      a_1.0.0_freebsd_amd64.tar.gz a_1.0.0_windows_amd64.zip
    ].map { |n| asset(n) },
    ACTION_README => %w[
      checksums.txt gh-action-readme_Darwin_arm64.tar.gz gh-action-readme_Darwin_arm64.tar.gz.sbom.json
      gh-action-readme_Darwin_x86_64.tar.gz gh-action-readme_Linux_arm64.tar.gz
      gh-action-readme_Linux_i386.tar.gz gh-action-readme_Linux_x86_64.tar.gz
      gh-action-readme_Windows_x86_64.zip
    ].map { |n| asset(n) },
    HISTORY       => %w[
      gh-history_2026.03.0_checksums.txt gh-history_2026.03.0_checksums.txt.bundle
      gh-history_darwin-amd64 gh-history_darwin-arm64 gh-history_linux-amd64 gh-history_linux-arm64
      gh-history_windows-amd64.exe
    ].map { |n| asset(n) },
  }.freeze

  EXPECTED = {
    "a"           => {
      archive: true,
      picks:   {
        %w[macos arm]   => "a_1.0.0_darwin_arm64.tar.gz",
        %w[macos intel] => "a_1.0.0_darwin_amd64.tar.gz",
        %w[linux arm]   => "a_1.0.0_linux_arm64.tar.gz",
        %w[linux intel] => "a_1.0.0_linux_amd64.tar.gz",
      },
    },
    ACTION_README => {
      archive: true,
      picks:   {
        %w[macos arm]   => "gh-action-readme_Darwin_arm64.tar.gz",
        %w[macos intel] => "gh-action-readme_Darwin_x86_64.tar.gz",
        %w[linux arm]   => "gh-action-readme_Linux_arm64.tar.gz",
        %w[linux intel] => "gh-action-readme_Linux_x86_64.tar.gz",
      },
    },
    HISTORY       => {
      archive: false,
      picks:   {
        %w[macos arm]   => "gh-history_darwin-arm64",
        %w[macos intel] => "gh-history_darwin-amd64",
        %w[linux arm]   => "gh-history_linux-arm64",
        %w[linux intel] => "gh-history_linux-amd64",
      },
    },
  }.freeze

  def self.run
    new.run_all
  end

  def initialize
    @failures = 0
  end

  def run_all
    check_class_name_round_trips
    check_sanitize_desc
    check_match_asset
    check_never_selects_junk
    check_formula_body
    check_formula_body_escapes_api_strings
    check_latest_release_selection
    check_group_formulae

    puts "\n#{@failures.zero? ? "ALL PASS" : "#{@failures} FAILURE(S)"}"
    exit(@failures.zero? ? 0 : 1)
  end

  private

  # CamelCase -> kebab-case, to assert class_name() stays reversible for
  # unversioned names (versioned "AT<digits>" names key off the filename instead).
  def class_to_formula(cls)
    cls.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase
  end

  def check(desc)
    ok = yield
    @failures += 1 unless ok
    puts "#{ok ? "ok  " : "FAIL"} #{desc}"
  end

  def check_class_name_round_trips
    ["a", ACTION_README, HISTORY, CALVER].each do |name|
      cls = SyncFormulae.class_name(name)
      check("class_name(#{name}) -> #{cls} round-trips") { class_to_formula(cls) == name }
    end
    check("class_name(a) == A") { SyncFormulae.class_name("a") == "A" }
    check("class_name(gh-action-readme) == GhActionReadme") do
      SyncFormulae.class_name(ACTION_README) == "GhActionReadme"
    end
  end

  def check_sanitize_desc
    long = "A small CLI that encrypts and decrypts files with your SSH keys using the age format"
    d = SyncFormulae.sanitize_desc(long)
    check("sanitize_desc drops leading article") { !d.match?(/\A(a|an|the)\s/i) }
    check("sanitize_desc <= 80 chars (#{d.length})") { d.length <= 80 }
    check("sanitize_desc no trailing period") { !d.end_with?(".") }

    overlong = "Transform your GitHub Actions into professional documentation with multiple " \
               "themes, output formats, and enterprise-grade features."
    d2 = SyncFormulae.sanitize_desc(overlong)
    check("sanitize_desc truncates 130-char desc to <= 80 (#{d2.length})") { d2.length <= 80 }
    check("sanitize_desc truncates at a word boundary") do
      !overlong.start_with?(d2) || overlong[d2.length].nil? || overlong[d2.length] == " "
    end
  end

  def check_match_asset
    EXPECTED.each do |repo, exp|
      assets = FIXTURES[repo]
      SyncFormulae::PLATFORMS.each do |p|
        got = SyncFormulae.match_asset(assets, p)
        key = [p[:os], p[:arch]]
        want = exp[:picks][key]
        check("#{repo} #{key.join("/")} -> #{want}") { got && got[:name] == want }
        check("#{repo} #{key.join("/")} archive=#{exp[:archive]}") { got && got[:archive] == exp[:archive] }
        check("#{repo} #{key.join("/")} sha256 is 64-hex") { got && got[:sha256].match?(/\A[a-f0-9]{64}\z/) }
      end
    end
  end

  def check_never_selects_junk
    all_picked = EXPECTED.flat_map do |repo, _exp|
      SyncFormulae::PLATFORMS.map { |p| SyncFormulae.match_asset(FIXTURES[repo], p)&.dig(:name) }
    end.compact
    check("never selects .sbom.json") { all_picked.none? { |n| n.include?("sbom") } }
    check("never selects .deb/.zip/.exe/.txt") { all_picked.none? { |n| n.match?(/\.(deb|zip|exe|txt)\z/) } }
    check("never selects 386/i386") { all_picked.none? { |n| n.include?("386") } }
    check("never selects windows/freebsd") { all_picked.none? { |n| n.match?(/windows|freebsd/i) } }
  end

  def base_meta(keg_only:, formula_name:, klass:)
    SyncFormulae.instance_eval do
      {
        name: CALVER, formula_name: formula_name, class: klass, keg_only: keg_only,
        desc: "GitHub CLI calver command", homepage: "https://github.com/ivuorinen/gh-calver",
        version: "2026.03.4", released_at: "2026-03-04T12:00:00Z", license: "MIT", bin: CALVER,
        test: 'system bin/"gh-calver", "--help"', archive: false,
        # Real release-asset URL shape: the tag in the path is now the only
        # carrier of the version, so the fixture must not elide it.
        platforms: [{ os: "macos", arch: "arm",
                      url: "https://github.com/ivuorinen/gh-calver/releases/download/2026.03.4/gh-calver_darwin-arm64",
                      sha256: "a" * 64 }]
      }
    end
  end

  def check_formula_body
    body = SyncFormulae.formula_body(base_meta(keg_only: false, formula_name: CALVER, klass: "GhCalver"))
    # `brew audit` rejects an explicit version when the URL already yields it.
    check("formula_body omits explicit version (brew audit rejects it)") do
      body.match?(/^\s*version\s/).!
    end
    check("formula_body raw install uses stable.url basename") { body.include?("File.basename(stable.url)") }
    check("formula_body nests on_macos/on_arm") { body.include?("on_macos do") && body.include?("on_arm do") }
    check("formula_body omits keg_only when not versioned") { body["keg_only"].nil? }

    # The real parser must recover what formula_body emits: the version from
    # the asset URL (how both Homebrew and the docs site get it) and the date.
    parsed = parse_with_formula_parser(body)
    check("FormulaParser recovers the version from the asset URL") { parsed[:version] == "2026.03.4" }
    check("FormulaParser recovers the release date") { parsed[:released_at] == "2026-03-04T12:00:00Z" }

    # Versioned formula: brew's "@<digit>" -> "AT<digit>" class mangling + keg_only.
    vclass = SyncFormulae.class_name("gh-calver@2026.03.4")
    check("class_name mangles versioned name") { vclass == "GhCalverAT2026034" }
    vbody = SyncFormulae.formula_body(base_meta(keg_only: true, formula_name: "gh-calver@2026.03.4", klass: vclass))
    check("versioned formula_body has keg_only :versioned_formula") { vbody.include?("keg_only :versioned_formula") }
    check("versioned formula_body class is the mangled name") { vbody.include?("class GhCalverAT2026034 < Formula") }
    check("versioned formula_body header uses the @ name") { vbody.include?("# gh-calver@2026.03.4 —") }
  end

  # A repo description is API text: a `"` must not end the literal and a
  # `#{...}` must not become interpolation in the generated Ruby.
  def check_formula_body_escapes_api_strings
    # Built from parts so no linter autocorrect can turn the fixture itself into
    # live interpolation; the payload raises rather than doing anything if run.
    hostile = ["Tool with a \"quoted\" word and #", '{raise "interpolated"} in it'].join
    meta = base_meta(keg_only: false, formula_name: CALVER, klass: "GhCalver").merge(desc: hostile)
    body = SyncFormulae.formula_body(meta)
    result = Prism.parse(body)
    check("formula_body with quotes and \#{} in desc parses as Ruby") { result.success? }

    desc_call = find_call(result.value, :desc)
    desc_arg = desc_call.arguments.arguments.first if desc_call&.arguments
    check("desc is a plain string literal, not interpolation") { desc_arg.is_a?(Prism::StringNode) }
    check("desc literal holds the exact API text") do
      desc_arg.respond_to?(:unescaped) && desc_arg.unescaped == hostile
    end
    check("FormulaParser round-trips the escaped desc") { parse_with_formula_parser(body)[:description] == hostile }
  end

  # The unversioned formula follows GitHub's releases/latest, never the first
  # row of the release list, which can be a prerelease or a later backport.
  def check_latest_release_selection
    release = lambda do |tag, prerelease: false|
      { "tag_name" => tag, "draft" => false, "prerelease" => prerelease, "published_at" => "2026-01-01T00:00:00Z",
        "assets" => ["#{tag}_darwin_arm64.tar.gz"].map { |n| self.class.asset(n) } }
    end
    rows = [release.call("3.0.0-rc1", prerelease: true), release.call("1.9.9"), release.call("2.0.0")]
    responses = {
      "repos/o/tool"                       => { "description" => "Tool", "license" => nil },
      "repos/o/tool/releases/latest"       => { "tag_name" => "2.0.0" },
      "repos/o/tool/releases?per_page=100" => rows,
    }
    metas, latest_tag = with_stubbed_gh(responses) { SyncFormulae.build_metas({ "repo" => "o/tool" }) }

    check("latest tag comes from releases/latest") { latest_tag == "2.0.0" }
    check("prereleases are excluded") { metas.none? { |m| m[:tag] == "3.0.0-rc1" } }
    check("a backport listed first is not latest") { metas.first[:tag] == "1.9.9" && latest_tag != metas.first[:tag] }

    broken = rows.map { |r| (r["tag_name"] == "2.0.0") ? r.merge("assets" => []) : r }
    raised = begin
      with_stubbed_gh(responses.merge("repos/o/tool/releases?per_page=100" => broken)) do
        SyncFormulae.build_metas({ "repo" => "o/tool" })
      end
      false
    rescue SyncFormulae::Error
      true
    end
    check("latest release without binaries fails the repo") { raised }
  end

  def check_group_formulae
    builder = SiteBuilder.new
    builder.instance_variable_set(:@data, {
      "formulae" => [
        { "name" => "x", "version" => "2.0" },
        { "name" => "x@1.10", "version" => "1.10" },
        { "name" => "x@1.9", "version" => "1.9" },
        { "name" => "x@garbage", "version" => "garbage" },
        { "name" => "y@1.0", "version" => "1.0" },
      ],
    })
    builder.send(:group_formulae)
    data = builder.instance_variable_get(:@data)
    by_name = data["formulae"].to_h { |f| [f["name"], f] }

    check("group_formulae keeps one entry per tool") { by_name.keys == %w[x y] && data["formulae_count"] == 2 }
    check("group_formulae sorts versions newest first, unparseable last") do
      by_name["x"]["versions"].map { |v| v["version"] } == %w[1.10 1.9 garbage]
    end
    check("group_formulae synthesizes a main for an orphan x@ver") do
      by_name["y"]["version"] == "1.0" && by_name["y"]["versions"].map { |v| v["name"] } == ["y@1.0"]
    end
  end

  # Writes body to a temp formula file and parses it with the real parser.
  def parse_with_formula_parser(body)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "#{CALVER}.rb")
      File.write(path, body)
      FormulaParser.new.send(:parse_formula, path)
    end
  end

  # Depth-first search for the first method call named `name`.
  def find_call(node, name)
    return node if node.is_a?(Prism::CallNode) && node.name == name

    node.compact_child_nodes.each do |child|
      found = find_call(child, name)
      return found if found
    end
    nil
  end

  # Replaces SyncFormulae.gh_json with canned responses for the block, so
  # build_metas runs without the network; an unknown path is a test bug.
  def with_stubbed_gh(responses)
    original = SyncFormulae.method(:gh_json)
    SyncFormulae.define_singleton_method(:gh_json) { |*path| responses.fetch(path.join(" ")) }
    yield
  ensure
    SyncFormulae.define_singleton_method(:gh_json, original)
  end
end

TestSyncFormulae.run if __FILE__ == $PROGRAM_NAME
