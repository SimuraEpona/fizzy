module User::Summaries
  extend ActiveSupport::Concern

  included do
    has_many :weekly_summaries, class_name: "User::WeeklySummary", dependent: :destroy
  end

  class_methods do
    def generate_all_weekly_summaries_later
      User::Summaries::GenerateAllJob.perform_later
    end

    def generate_all_weekly_summaries
      # We're not interested in parallelizing individual generation. Better for AI quota limits and, also,
      # most summaries will be reused for users accessing the same collections.
      active.find_each(&:generate_weekly_summary)
    end
  end

  def generate_weekly_summary(date = Time.current)
    in_time_zone do
      weekly_summary_for(date) || create_weekly_summary_for(date)
    end
  end

  def weekly_summary_for(date)
    in_time_zone do
      weekly_summaries.find_by(starts_at: summary_starts_at(date).to_date)&.period_summary
    end
  end

  private
    def create_weekly_summary_for(date)
      # Outside of transaction as generating summaries can be a slow operation
      PeriodSummary.create_or_find_for(collections, starts_at: summary_starts_at(date), duration: 1.week).tap do |period_summary|
        if period_summary
          weekly_summaries.create! period_summary: period_summary, starts_at: summary_starts_at(date).to_date
        end
      end
    end

    def summary_starts_at(date = Time.current)
      date = date.in_time_zone(timezone)
      date.beginning_of_week(:sunday) - 1.week
    end
end
