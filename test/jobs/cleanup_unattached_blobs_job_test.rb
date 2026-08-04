require "test_helper"

# 上傳中關掉分頁、或 items#create 驗證失敗,都會留下沒有 attach 的孤兒 blob。
class CleanupUnattachedBlobsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "會清掉超過寬限期的孤兒 blob" do
    blob = create_blob(filename: "orphan.bin")
    blob.update!(created_at: 7.hours.ago)
    key = blob.key

    perform_enqueued_jobs do
      CleanupUnattachedBlobsJob.perform_now
    end

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(key)
  end

  test "不會清掉還在寬限期內的 blob(可能正在上傳)" do
    blob = create_blob(filename: "in-flight.bin")

    perform_enqueued_jobs do
      CleanupUnattachedBlobsJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(blob.id)
  end

  test "不會碰已經 attach 的 blob" do
    channel = create_channel("lab1")
    item = create_file_item(channel, filename: "kept.bin")
    blob = item.file.blob
    blob.update!(created_at: 7.hours.ago)

    perform_enqueued_jobs do
      CleanupUnattachedBlobsJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(blob.id)
    assert ActiveStorage::Blob.service.exist?(blob.key)
  end
end
