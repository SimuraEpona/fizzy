class RenameUserWeeklyHighlightsToUserWeeklySummaries < ActiveRecord::Migration[8.2]
  def change
    rename_table :user_weekly_highlights, :user_weekly_summaries
    rename_column :user_weekly_summaries, :period_highlights_id, :period_summary_id
  end
end
