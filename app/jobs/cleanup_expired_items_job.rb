class CleanupExpiredItemsJob < ApplicationJob
  queue_as :default

  def perform
    scope = Item.expired
    count = scope.count

    # 一筆一筆 destroy,才會觸發 dependent: :purge_later 清掉 blob
    scope.find_each(&:destroy)

    Rails.logger.info("[cleanup] removed #{count} expired items") if count.positive?
  end
end
