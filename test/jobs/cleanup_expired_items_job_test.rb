require "test_helper"

class CleanupExpiredItemsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @channel = create_channel("lab1") }

  test "it deletes items whose expires_at has passed" do
    expired = create_text_item(@channel, body: "expired", expires_at: 1.hour.ago)

    assert_difference "Item.count", -1 do
      CleanupExpiredItemsJob.perform_now
    end

    assert_not Item.exists?(expired.id)
  end

  test "it leaves items with a nil expires_at alone" do
    never = create_text_item(@channel, body: "never expires", expires_at: nil)

    assert_no_difference "Item.count" do
      CleanupExpiredItemsJob.perform_now
    end

    assert Item.exists?(never.id)
  end

  test "it leaves items that have not expired yet alone" do
    future = create_text_item(@channel, body: "not yet", expires_at: 1.hour.from_now)

    assert_no_difference "Item.count" do
      CleanupExpiredItemsJob.perform_now
    end

    assert Item.exists?(future.id)
  end

  test "the ActiveStorage blob is purged along with the item" do
    item = create_file_item(@channel, expires_at: 1.hour.ago, filename: "expired.bin")
    blob = item.file.blob
    key = blob.key

    assert ActiveStorage::Blob.service.exist?(key)

    # dependent: :purge_later goes through ActiveJob, and the test adapter does
    # not run jobs -- without this the blob stays on disk and the test lies.
    perform_enqueued_jobs do
      CleanupExpiredItemsJob.perform_now
    end

    assert_not Item.exists?(item.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(key), "the blob file should be gone from disk"
  end

  test "it clears several items in one run" do
    3.times { |i| create_text_item(@channel, body: "expired #{i}", expires_at: 1.hour.ago) }
    create_text_item(@channel, body: "alive")

    assert_difference "Item.count", -3 do
      CleanupExpiredItemsJob.perform_now
    end
  end
end
