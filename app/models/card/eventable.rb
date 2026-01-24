module Card::Eventable
  extend ActiveSupport::Concern

  include ::Eventable

  included do
    before_create { self.last_active_at ||= created_at || Time.current }

    after_save :track_title_change, if: :saved_change_to_title?
    after_save :track_started_on_change, if: :saved_change_to_started_on?
    after_save :track_due_on_change, if: :saved_change_to_due_on?
  end

  def event_was_created(event)
    transaction do
      create_system_comment_for(event)
      touch_last_active_at unless was_just_published?
    end
  end

  def touch_last_active_at
    # Not using touch so that we can detect attribute change on callbacks
    update!(last_active_at: Time.current)
  end

  private
    def should_track_event?
      published?
    end

    def track_title_change
      if title_before_last_save.present?
        track_event "title_changed", particulars: { old_title: title_before_last_save, new_title: title }
      end
    end

    def track_started_on_change
      track_event "started_on_changed", particulars: {
        old_started_on: started_on_before_last_save&.to_s,
        new_started_on: started_on&.to_s
      }
    end

    def track_due_on_change
      track_event "due_on_changed", particulars: {
        old_due_on: due_on_before_last_save&.to_s,
        new_due_on: due_on&.to_s
      }
    end

    def create_system_comment_for(event)
      SystemCommenter.new(self, event).comment
    end
end
