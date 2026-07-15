#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline unit check for the pure functions in sync_formulae.rb.
# No network: feeds recorded asset lists from the four seed repos.
# Run: ruby scripts/test_sync_formulae.rb

require_relative "sync_formulae"

FAKE = "sha256:#{'a' * 64}"

def asset(name)
  { "name" => name, "browser_download_url" => "https://example/#{name}", "digest" => FAKE }
end

# Recorded asset-name shapes (the divergent conventions we must handle).
FIXTURES = {
  "a" => %w[
    a_1.0.0_darwin_amd64 a_1.0.0_darwin_amd64.tar.gz a_1.0.0_darwin_amd64.tar.gz.sbom.json
    a_1.0.0_darwin_arm64 a_1.0.0_darwin_arm64.tar.gz
    a_1.0.0_linux_386 a_1.0.0_linux_386.tar.gz a_1.0.0_linux_amd64 a_1.0.0_linux_amd64.deb
    a_1.0.0_linux_amd64.tar.gz a_1.0.0_linux_arm64 a_1.0.0_linux_arm64.tar.gz
    a_1.0.0_freebsd_amd64.tar.gz a_1.0.0_windows_amd64.zip
  ].map { |n| asset(n) },
  "gh-action-readme" => %w[
    checksums.txt gh-action-readme_Darwin_arm64.tar.gz gh-action-readme_Darwin_arm64.tar.gz.sbom.json
    gh-action-readme_Darwin_x86_64.tar.gz gh-action-readme_Linux_arm64.tar.gz
    gh-action-readme_Linux_i386.tar.gz gh-action-readme_Linux_x86_64.tar.gz
    gh-action-readme_Windows_x86_64.zip
  ].map { |n| asset(n) },
  "gh-history" => %w[
    gh-history_2026.03.0_checksums.txt gh-history_2026.03.0_checksums.txt.bundle
    gh-history_darwin-amd64 gh-history_darwin-arm64 gh-history_linux-amd64 gh-history_linux-arm64
    gh-history_windows-amd64.exe
  ].map { |n| asset(n) },
}.freeze

EXPECTED = {
  "a" => {
    archive: true,
    picks: {
      %w[macos arm] => "a_1.0.0_darwin_arm64.tar.gz",
      %w[macos intel] => "a_1.0.0_darwin_amd64.tar.gz",
      %w[linux arm] => "a_1.0.0_linux_arm64.tar.gz",
      %w[linux intel] => "a_1.0.0_linux_amd64.tar.gz",
    },
  },
  "gh-action-readme" => {
    archive: true,
    picks: {
      %w[macos arm] => "gh-action-readme_Darwin_arm64.tar.gz",
      %w[macos intel] => "gh-action-readme_Darwin_x86_64.tar.gz",
      %w[linux arm] => "gh-action-readme_Linux_arm64.tar.gz",
      %w[linux intel] => "gh-action-readme_Linux_x86_64.tar.gz",
    },
  },
  "gh-history" => {
    archive: false,
    picks: {
      %w[macos arm] => "gh-history_darwin-arm64",
      %w[macos intel] => "gh-history_darwin-amd64",
      %w[linux arm] => "gh-history_linux-arm64",
      %w[linux intel] => "gh-history_linux-amd64",
    },
  },
}.freeze

# Reverse of the docs parser (parse_formulas.rb#convert_class_name_to_formula_name).
def class_to_formula(cls)
  cls.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase
end

$failures = 0
def check(desc)
  ok = yield
  $failures += 1 unless ok
  puts "#{ok ? 'ok  ' : 'FAIL'} #{desc}"
end

# --- class_name round-trips through the docs parser --------------------------
%w[a gh-action-readme gh-history gh-calver].each do |name|
  cls = SyncFormulae.class_name(name)
  check("class_name(#{name}) -> #{cls} round-trips") { class_to_formula(cls) == name }
end
check("class_name(a) == A") { SyncFormulae.class_name("a") == "A" }
check("class_name(gh-action-readme) == GhActionReadme") { SyncFormulae.class_name("gh-action-readme") == "GhActionReadme" }

# --- sanitize_desc -----------------------------------------------------------
long = "A small CLI that encrypts and decrypts files with your SSH keys using the age format"
d = SyncFormulae.sanitize_desc(long)
check("sanitize_desc drops leading article") { !d.match?(/\A(a|an|the)\s/i) }
check("sanitize_desc <= 80 chars (#{d.length})") { d.length <= 80 }
check("sanitize_desc no trailing period") { !d.end_with?(".") }

overlong = "Transform your GitHub Actions into professional documentation with multiple themes, output formats, and enterprise-grade features."
d2 = SyncFormulae.sanitize_desc(overlong)
check("sanitize_desc truncates 130-char desc to <= 80 (#{d2.length})") { d2.length <= 80 }
check("sanitize_desc truncates at a word boundary") { !overlong.start_with?(d2) || overlong[d2.length].nil? || overlong[d2.length] == " " }

# --- match_asset -------------------------------------------------------------
EXPECTED.each do |repo, exp|
  assets = FIXTURES[repo]
  SyncFormulae::PLATFORMS.each do |p|
    got = SyncFormulae.match_asset(assets, p)
    key = [p[:os], p[:arch]]
    want = exp[:picks][key]
    check("#{repo} #{key.join('/')} -> #{want}") { got && got[:name] == want }
    check("#{repo} #{key.join('/')} archive=#{exp[:archive]}") { got && got[:archive] == exp[:archive] }
    check("#{repo} #{key.join('/')} sha256 is 64-hex") { got && got[:sha256].match?(/\A[a-f0-9]{64}\z/) }
  end
end

# --- never select junk / out-of-scope platforms -----------------------------
all_picked = EXPECTED.flat_map do |repo, exp|
  SyncFormulae::PLATFORMS.map { |p| SyncFormulae.match_asset(FIXTURES[repo], p)&.dig(:name) }
end.compact
check("never selects .sbom.json") { all_picked.none? { |n| n.include?("sbom") } }
check("never selects .deb/.zip/.exe/.txt") { all_picked.none? { |n| n.match?(/\.(deb|zip|exe|txt)\z/) } }
check("never selects 386/i386") { all_picked.none? { |n| n.match?(/386/) } }
check("never selects windows/freebsd") { all_picked.none? { |n| n.match?(/windows|freebsd/i) } }

# --- formula_body renders a loadable-looking formula ------------------------
meta = SyncFormulae.instance_eval do
  {
    name: "gh-calver", class: class_name("gh-calver"), desc: "GitHub CLI calver command",
    homepage: "https://github.com/ivuorinen/gh-calver", version: "2026.03.4", license: "MIT",
    bin: "gh-calver", test: %(system bin/"gh-calver", "--help"), archive: false,
    platforms: [{ os: "macos", arch: "arm", url: "https://x/gh-calver_darwin-arm64", sha256: "a" * 64 }],
  }
end
body = SyncFormulae.formula_body(meta)
check("formula_body has explicit version (docs parser needs it)") { body.include?('version "2026.03.4"') }
check("formula_body raw install uses stable.url basename") { body.include?("File.basename(stable.url)") }
check("formula_body nests on_macos/on_arm") { body.include?("on_macos do") && body.include?("on_arm do") }

puts "\n#{$failures.zero? ? 'ALL PASS' : "#{$failures} FAILURE(S)"}"
exit($failures.zero? ? 0 : 1)
