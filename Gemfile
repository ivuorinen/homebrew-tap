# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 4.0"

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
