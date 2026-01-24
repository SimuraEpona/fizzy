module Card::Schedulable
  extend ActiveSupport::Concern

  included do
    validate :started_on_before_due_on

    scope :scheduled, -> { where.not(started_on: nil).where.not(due_on: nil) }
    scope :partially_scheduled, -> { where(started_on: nil).where.not(due_on: nil).or(where.not(started_on: nil).where(due_on: nil)) }
    scope :unscheduled, -> { where(started_on: nil, due_on: nil) }
    scope :timeline_sorted, -> { order(started_on: :asc, due_on: :asc) }
  end

  def scheduled?
    started_on.present? && due_on.present?
  end

  def partially_scheduled?
    (started_on.present? && due_on.blank?) || (started_on.blank? && due_on.present?)
  end

  def unscheduled?
    started_on.blank? && due_on.blank?
  end

  def schedule_status
    if scheduled?
      :scheduled
    elsif partially_scheduled?
      :partial
    else
      :unscheduled
    end
  end

  def timeline_range
    return nil unless scheduled?
    started_on..due_on
  end

  private
    def started_on_before_due_on
      if started_on.present? && due_on.present? && started_on > due_on
        errors.add(:started_on, "must be before or equal to the due date")
      end
    end
end
