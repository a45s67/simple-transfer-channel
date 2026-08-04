# direct upload 會先建立 blob、之後才 POST 給 items#create。中間如果分頁被關掉、
# 或 items#create 驗證失敗(0 bytes、超過上限),blob 就變成孤兒留在磁碟上。
# VERIFY.md 的邊界情況要求至少有 job 會清掉它們。
class CleanupUnattachedBlobsJob < ApplicationJob
  queue_as :default

  # 給還在上傳中的 blob 足夠的寬限時間,不要清掉正在寫入的檔案
  GRACE_PERIOD = 6.hours

  def perform
    scope = ActiveStorage::Blob.unattached.where(created_at: ..GRACE_PERIOD.ago)
    count = scope.count

    scope.find_each(&:purge_later)

    Rails.logger.info("[cleanup] purged #{count} unattached blobs") if count.positive?
  end
end
