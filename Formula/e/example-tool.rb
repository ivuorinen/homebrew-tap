# frozen_string_literal: true

# Homebrew formula for ExampleTool - a demonstration tool for this tap
class ExampleTool < Formula
  desc "Imaginery tool to demonstrate the tap functionality"
  homepage "https://github.com/ivuorinen/example-tool"
  url "https://github.com/ivuorinen/example-tool/refs/tags/v1.0.0.tar.gz"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w")
  end

  test do
    assert_match "example-tool version 1.0.0", shell_output("#{bin}/example-tool --version")
  end
end
