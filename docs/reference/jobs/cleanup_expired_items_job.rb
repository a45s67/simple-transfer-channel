# 參考實作 — 未執行過,以 SPEC.md 為準
class CleanupExpiredItemsJob < ApplicationJob
  queue_as :default

  def perform
    scope = Item.where.not(expires_at: nil).where(expires_at: ..Time.current)
    count = scope.count

    scope.find_each(&:destroy)

    Rails.logger.info("[cleanup] removed #{count} expired items") if count.positive?
  end
end
