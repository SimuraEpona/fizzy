#!/usr/bin/env ruby

require_relative "../config/environment"

WEEKS_TO_BACKFILL = 3

ActiveRecord::Base.logger = Logger.new(File::NULL)

ApplicationRecord.with_each_tenant do |tenant|
  PeriodSummary.destroy_all
  WEEKS_TO_BACKFILL.times do |index|
    User.active.find_each do |user|
      user.generate_weekly_summary(Time.current - index.weeks)
    end
  end
end
