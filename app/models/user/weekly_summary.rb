# This acts as a join table between users and period_summaries so that we can reuse the
# same summaries for different users.
class User::WeeklySummary < ApplicationRecord
  belongs_to :user
  belongs_to :period_summary
end
