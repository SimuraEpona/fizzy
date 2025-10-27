class PeriodSummary::Period
  MIN_EVENTS_TO_BE_INTERESTING = 7

  attr_reader :collections, :starts_at, :duration

  def initialize(collections, starts_at:, duration:)
    @collections = collections
    @starts_at = normalize_anchor_date(starts_at)
    @duration = duration
  end

  def events
    @events ||= Event.where(collection: collections).where(created_at: window)
  end

  def has_enough_activity?
    events.count >= MIN_EVENTS_TO_BE_INTERESTING
  end

  def key
    @key ||= Digest::SHA256.hexdigest(events.ids.sort.join("-"))
  end

  private
    def window
      starts_at..starts_at + duration
    end

    def normalize_anchor_date(date)
      date.beginning_of_day
    end
end
