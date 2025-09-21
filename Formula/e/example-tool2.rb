# frozen_string_literal: true

class ExampleTool2 < Formula
  desc "Second example tool to demonstrate the tap functionality"
  homepage "https://github.com/ivuorinen/example-tool2"
  url "https://github.com/ivuorinen/example-tool2/refs/tags/v2.0.0.tar.gz"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w")
  end

  test do
    assert_match "example-tool2 version 2.0.0", shell_output("#{bin}/example-tool2 --version")
  end
end
