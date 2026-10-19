# frozen_string_literal: true

source "https://rubygems.org"

# Floor is brew's own Ruby: on the macOS test bot, `make setup` runs under it.
ruby ">= 3.3"

gem "json", "~> 3.0"
# Standalone Tailwind CLI: compiles theme/style.css at build time, replacing
# the development-only Play CDN script the pages used to load.
gem "tailwindcss-ruby", "~> 4.3"
gem "terser", "~> 1.2"

# dev dependencies
group :development do
  gem "rubocop", "~> 1.81", require: false
  gem "webrick", "~> 1.9"
end
