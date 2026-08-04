require "test_helper"

# Closing the tab mid-upload, or a rejected items#create, both leave an orphaned
# blob behind.
class CleanupUnattachedBlobsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "it purges orphaned blobs past the grace period" do
    blob = create_blob(filename: "orphan.bin")
    blob.update!(created_at: 7.hours.ago)
    key = blob.key

    perform_enqueued_jobs do
      CleanupUnattachedBlobsJob.perform_now
    end

    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(key)
  end

  test "it leaves blobs inside the grace period alone (they may still be uploading)" do
    blob = create_blob(filename: "in-flight.bin")

    perform_enqueued_jobs do
      CleanupUnattachedBlobsJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(blob.id)
  end

  test "it never touches a blob that is already attached" do
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
