# typed: strict
# frozen_string_literal: true

require "time"

# Module for formatting timestamps and dates
module TimeFormatter
  SECONDS_PER_MINUTE = 60
  SECONDS_PER_HOUR = 3600
  SECONDS_PER_DAY = 86_400
  SECONDS_PER_WEEK = 604_800
  SECONDS_PER_MONTH = 2_419_200
  SECONDS_PER_YEAR = 31_536_000

  def format_relative_time(timestamp)
    return "" unless timestamp

    begin
      diff = calculate_time_difference(timestamp)
      return "just now" if diff < SECONDS_PER_MINUTE

      format_time_by_category(diff)
    rescue
      ""
    end
  end

  def format_date(timestamp)
    return "" unless timestamp

    begin
      Time.parse(timestamp).strftime("%b %d, %Y")
    rescue
      ""
    end
  end

  private

  def calculate_time_difference(timestamp)
    time = Time.parse(timestamp)
    Time.now - time
  end

  def format_time_by_category(diff)
    case diff
    when SECONDS_PER_MINUTE...SECONDS_PER_HOUR
      format_time_unit(diff / SECONDS_PER_MINUTE, "minute")
    when SECONDS_PER_HOUR...SECONDS_PER_DAY
      format_time_unit(diff / SECONDS_PER_HOUR, "hour")
    when SECONDS_PER_DAY...SECONDS_PER_WEEK
      format_time_unit(diff / SECONDS_PER_DAY, "day")
    when SECONDS_PER_WEEK...SECONDS_PER_MONTH
      format_time_unit(diff / SECONDS_PER_WEEK, "week")
    when SECONDS_PER_MONTH...SECONDS_PER_YEAR
      format_time_unit(diff / SECONDS_PER_MONTH, "month")
    else
      format_time_unit(diff / SECONDS_PER_YEAR, "year")
    end
  end

  def format_time_unit(value, unit)
    count = value.to_i
    "#{count} #{unit}#{"s" if count != 1} ago"
  end
end
