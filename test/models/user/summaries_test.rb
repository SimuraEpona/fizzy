require "test_helper"

class User::SummariesTest < ActiveSupport::TestCase
  include VcrTestHelper

  setup do
    @user = users(:david)
    travel_to [ Time.current, 1.day.ago ].find { |d| !d.sunday? }
    Current.session = sessions(:david)
  end

  test "generate weekly summary" do
    stub_const(PeriodSummary::Period, :MIN_EVENTS_TO_BE_INTERESTING, 3) do
      period_summary = assert_difference -> { PeriodSummary.count }, 1 do
        @user.generate_weekly_summary
      end

      assert_match /logo/i, period_summary.to_html
    end
  end

  test "don't generate summary for existing periods" do
    stub_const(PeriodSummary::Period, :MIN_EVENTS_TO_BE_INTERESTING, 3) do
      new_period_summary = @user.generate_weekly_summary
      assert_not_nil new_period_summary

      existing_period_summary = assert_no_difference -> { PeriodSummary.count } do
        @user.generate_weekly_summary
      end

      assert_equal new_period_summary, existing_period_summary
    end
  end

  test "periods respect user timezone for week boundaries" do
    @user.settings.update!(timezone_name: "America/New_York")

    # Sunday Jan 7, 2024 at 2am EST (7am UTC) - this is Sunday in NYC
    sunday_in_nyc = Time.zone.parse("2024-01-07 07:00:00 UTC")

    # Saturday Jan 6, 2024 at 11pm EST (Jan 7 4am UTC) - still Saturday in NYC but Sunday in UTC
    saturday_in_nyc = Time.zone.parse("2024-01-07 04:00:00 UTC")

    # Event on Saturday evening in NYC (but Sunday in UTC)
    saturday_event = travel_to(saturday_in_nyc) { cards(:logo).track_event("Saturday event") }

    # Events throughout the week starting Sunday in NYC
    7.times do |i|
      travel_to(sunday_in_nyc + i.days) { cards(:logo).track_event("Event #{i}") }
    end

    wednesday = sunday_in_nyc + 3.days

    # The period should start at Sunday in NYC timezone
    period_start = wednesday.in_time_zone("America/New_York").beginning_of_week(:sunday)
    period = PeriodSummary::Period.new(@user.collections, starts_at: period_start, duration: 1.week)

    # The Saturday event should NOT be included (it's in the previous week in NYC time)
    assert_not_includes period.events, saturday_event

    # Should include 7 events from the current week
    assert_equal 7, period.events.count
  end
end
