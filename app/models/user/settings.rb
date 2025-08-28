class User::Settings < ApplicationRecord
  belongs_to :user

  enum :bundle_email_frequency, %i[ never every_few_hours daily weekly ],
    default: :never, prefix: :bundle_email

  after_update :review_pending_bundles, if: :saved_change_to_bundle_email_frequency?

  def bundle_aggregation_period
    case bundle_email_frequency
    when "every_few_hours"
      4.hours
    when "daily"
      1.day
    when "weekly"
      1.week
    else
      1.day
    end
  end

  private
    def review_pending_bundles
      if bundle_email_never?
        cancel_pending_bundles
      else
        reschedule_pending_bundles
      end
    end

    def cancel_pending_bundles
      user.notification_bundles.pending.find_each do |bundle|
        bundle.destroy
      end
    end

    def reschedule_pending_bundles
      user.notification_bundles.pending.find_each do |bundle|
        bundle.deliver_later
      end
    end
end
