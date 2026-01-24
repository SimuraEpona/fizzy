class Board::Timeline
  attr_reader :board, :filter

  def initialize(board, filter)
    @board = board
    @filter = filter
  end

  def scheduled_cards
    @scheduled_cards ||= filtered_cards.scheduled.timeline_sorted.preloaded
  end

  def partially_scheduled_cards
    @partially_scheduled_cards ||= filtered_cards.partially_scheduled.timeline_sorted.preloaded
  end

  def unscheduled_cards
    @unscheduled_cards ||= filtered_cards.unscheduled.latest.preloaded
  end

  def date_range
    return default_date_range if scheduled_cards.empty?

    min_date = scheduled_cards.minimum(:started_on)
    max_date = scheduled_cards.maximum(:due_on)

    # Extend range to include partial cards
    if partially_scheduled_cards.any?
      partial_min = partially_scheduled_cards.minimum(:started_on)
      partial_max = partially_scheduled_cards.maximum(:due_on)
      min_date = [ min_date, partial_min ].compact.min
      max_date = [ max_date, partial_max ].compact.max
    end

    # Add padding (1 week before and after)
    start_date = (min_date - 7.days).beginning_of_week
    end_date = (max_date + 7.days).end_of_week

    start_date..end_date
  end

  def weeks
    @weeks ||= begin
      range = date_range
      current = range.begin.beginning_of_week
      result = []

      while current <= range.end
        result << current
        current += 1.week
      end

      result
    end
  end

  def months
    @months ||= weeks.group_by { |week| [ week.year, week.month ] }.map do |(year, month), weeks_in_month|
      {
        date: Date.new(year, month, 1),
        name: Date::MONTHNAMES[month],
        weeks: weeks_in_month.size
      }
    end
  end

  def card_grid_position(card)
    return nil unless card.started_on && card.due_on

    start_week = weeks.index { |w| card.started_on >= w && card.started_on < w + 1.week }
    end_week = weeks.index { |w| card.due_on >= w && card.due_on < w + 1.week }

    return nil unless start_week && end_week

    {
      column_start: start_week + 1,
      column_end: end_week + 2,
      offset_start: day_offset_in_week(card.started_on),
      offset_end: day_offset_in_week(card.due_on)
    }
  end

  def total_weeks
    weeks.size
  end

  private
    def filtered_cards
      filter.cards(board.cards.active)
    end

    def default_date_range
      today = Date.current
      start_date = today.beginning_of_week - 1.week
      end_date = today.end_of_week + 4.weeks
      start_date..end_date
    end

    def day_offset_in_week(date)
      # Returns 0-6 for Mon-Sun positioning within a week cell
      (date.wday - 1) % 7
    end
end
