class RenamePeriodHighlightsToPeriodSummaries < ActiveRecord::Migration[8.2]
  def change
    rename_table :period_highlights, :period_summaries
  end
end
