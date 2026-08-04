class CleanupExpiredItemsJob < ApplicationJob
  queue_as :default

  def perform
    scope = Item.expired
    count = scope.count

    # Destroy one at a time so dependent: :purge_later fires and the blobs go too.
    scope.find_each(&:destroy)

    Rails.logger.info("[cleanup] removed #{count} expired items") if count.positive?
  end
end
