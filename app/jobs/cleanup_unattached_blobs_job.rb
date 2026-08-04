# A direct upload creates the blob before the browser POSTs to items#create. If
# the tab is closed in between, or items#create rejects the item (0 bytes, over
# the size limit), the blob is orphaned on disk. Something has to sweep those up
# or the disk fills over time.
class CleanupUnattachedBlobsJob < ApplicationJob
  queue_as :default

  # Leave uploads in flight alone -- don't purge a file that is still being written.
  GRACE_PERIOD = 6.hours

  def perform
    scope = ActiveStorage::Blob.unattached.where(created_at: ..GRACE_PERIOD.ago)
    count = scope.count

    scope.find_each(&:purge_later)

    Rails.logger.info("[cleanup] purged #{count} unattached blobs") if count.positive?
  end
end
