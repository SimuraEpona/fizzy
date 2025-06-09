class Public::CollectionsController < ApplicationController
  allow_unauthenticated_access only: :show

  before_action :set_collection

  layout "public"

  PAGE_SIZE = 50

  def show
    @considering = set_page_and_extract_portion_from @collection.cards.considering.latest, per_page: PAGE_SIZE
    @doing = set_page_and_extract_portion_from @collection.cards.doing.latest, per_page: PAGE_SIZE
    @closed = set_page_and_extract_portion_from @collection.cards.closed.recently_closed_first, per_page: PAGE_SIZE
  end

  private
    def set_collection
      @collection = Collection.find_by_published_key(params[:id])
    end
end
