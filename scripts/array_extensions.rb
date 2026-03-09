# typed: strict
# frozen_string_literal: true

# Simple polyfill for Homebrew extensions
class Array
  def exclude?(item)
    !include?(item)
  end
end
