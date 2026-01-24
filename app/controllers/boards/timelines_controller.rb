class Boards::TimelinesController < ApplicationController
  include BoardScoped
  include FilterScoped

  def show
    @timeline = Board::Timeline.new(@board, @filter)
  end
end
