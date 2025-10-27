require "test_helper"

class PeriodSummaryTest < ActiveSupport::TestCase
  include VcrTestHelper

  setup do
    @user = users(:david)
  end

  test "generate period summary" do
    period_summary = assert_difference -> { PeriodSummary.count }, 1 do
      PeriodSummary.create_or_find_for(@user.collections, starts_at: 1.month.ago, duration: 2.months)
    end

    assert_match /logo/i, period_summary.to_html
  end

  test "don't generate summary for existing periods" do
    new_period_summary = PeriodSummary.create_or_find_for(@user.collections, starts_at: 1.month.ago, duration: 2.months)

    existing_period_summary = assert_no_difference -> { PeriodSummary.count } do
      PeriodSummary.create_or_find_for(@user.collections, starts_at: 1.month.ago, duration: 2.months)
    end

    assert_equal new_period_summary, existing_period_summary
  end
end
