module Bubble::Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, dependent: :destroy
    has_many :tags, through: :taggings

    scope :tagged_with, ->(tags) { joins(:taggings).where(taggings: { tag: tags }) }
  end

  def toggle_tag(tag)
    tagged_with?(tag) ? untag(tag) : tag(tag)
  end

  def tagged_with?(tag)
    tags.include? tag
  end

  private
    def tag(tag)
      taggings.create! tag: tag
    rescue ActiveRecord::RecordNotUnique
      # Already tagged
    end

    def untag(tag)
      taggings.destroy_by tag: tag
    end
end
