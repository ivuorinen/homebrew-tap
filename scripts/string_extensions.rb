# typed: strict
# frozen_string_literal: true

# Simple polyfill for Homebrew extensions
class String
  def blank?
    # Polyfill implementation to avoid external dependencies
    nil? || empty? # rubocop:disable Homebrew/Blank, Lint/RedundantCopDisableDirective
  end
end
