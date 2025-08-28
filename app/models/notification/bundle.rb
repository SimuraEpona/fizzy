class Notification::Bundle < ApplicationRecord
  belongs_to :user

  enum :status, %i[ pending processing delivered ]

  scope :due, -> { pending.where("ends_at <= ?", Time.current) }
  scope :containing, ->(notification) { where("starts_at <= ? AND ends_at > ?", notification.created_at, notification.created_at) }
  scope :overlapping_with, ->(other_bundle) do
    where(
      "(starts_at <= ? AND ends_at >= ?) OR (starts_at <= ? AND ends_at >= ?) OR (starts_at >= ? AND ends_at <= ?)",
      other_bundle.starts_at, other_bundle.starts_at,
      other_bundle.ends_at, other_bundle.ends_at,
      other_bundle.starts_at, other_bundle.ends_at
    )
  end

  before_create :set_default_window

  validate :validate_no_overlapping

  class << self
    def deliver_all
      due.in_batches do |batch|
        jobs = batch.collect { DeliverJob.new(it) }
        ActiveJob.perform_all_later jobs
      end
    end

    def deliver_all_later
      DeliverAllJob.perform_later
    end
  end

  def notifications
    user.notifications.where(created_at: window).unread
  end

  def deliver
    processing!

    BundleMailer.notification(self).deliver if notifications.any?

    delivered!
  end

  def deliver_later
    DeliverJob.perform_later(self)
  end

  private
    def set_default_window
      self.starts_at ||= Time.current
      self.ends_at ||= user.settings.bundle_aggregation_period.from_now
    end

    def window
      starts_at..ends_at
    end

    def validate_no_overlapping
      if overlapping_bundles.exists?
        errors.add(:base, "Bundle window overlaps with an existing pending bundle")
      end
    end

    def overlapping_bundles
      user.notification_bundles.where.not(id: id).overlapping_with(self)
    end
end
