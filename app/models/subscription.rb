class Subscription < ApplicationRecord
  belongs_to :user

  delegated_type :subscribable, types: Subscribable::TYPES, inverse_of: :subscription
end
