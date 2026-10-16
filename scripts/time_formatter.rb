# frozen_string_literal: true

require "time"

# Module for formatting timestamps and dates
module TimeFormatter
  def format_date(timestamp)
    return "" unless timestamp

    begin
      Time.parse(timestamp).strftime("%b %d, %Y")
    rescue
      ""
    end
  end

  # Absolute date + time in UTC, e.g. "Jul 24, 2026 at 14:32 UTC". Use for
  # build-anchored timestamps: relative time freezes into stale HTML on a
  # static site (a build always renders "just now").
  def format_datetime(timestamp)
    return "" unless timestamp

    begin
      Time.parse(timestamp).utc.strftime("%b %d, %Y at %H:%M UTC")
    rescue
      ""
    end
  end
end
