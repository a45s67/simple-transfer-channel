require "test_helper"

class CleanupExpiredItemsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @channel = create_channel("lab1") }

  test "會刪除 expires_at 已過的項目" do
    expired = create_text_item(@channel, body: "過期", expires_at: 1.hour.ago)

    assert_difference "Item.count", -1 do
      CleanupExpiredItemsJob.perform_now
    end

    assert_not Item.exists?(expired.id)
  end

  test "不會刪除 expires_at 為 nil 的項目" do
    never = create_text_item(@channel, body: "永不過期", expires_at: nil)

    assert_no_difference "Item.count" do
      CleanupExpiredItemsJob.perform_now
    end

    assert Item.exists?(never.id)
  end

  test "不會刪除還沒過期的項目" do
    future = create_text_item(@channel, body: "還沒過期", expires_at: 1.hour.from_now)

    assert_no_difference "Item.count" do
      CleanupExpiredItemsJob.perform_now
    end

    assert Item.exists?(future.id)
  end

  test "刪除後 ActiveStorage blob 也被清掉" do
    item = create_file_item(@channel, expires_at: 1.hour.ago, filename: "expired.bin")
    blob = item.file.blob
    key = blob.key

    assert ActiveStorage::Blob.service.exist?(key)

    # GOTCHAS.md 第 7 條:dependent: :purge_later 走 ActiveJob,
    # test adapter 下不跑 job,blob 會留在磁碟上。
    perform_enqueued_jobs do
      CleanupExpiredItemsJob.perform_now
    end

    assert_not Item.exists?(item.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(key), "blob 檔案應該從磁碟上消失"
  end

  test "一次可以清掉多筆" do
    3.times { |i| create_text_item(@channel, body: "過期 #{i}", expires_at: 1.hour.ago) }
    create_text_item(@channel, body: "活著")

    assert_difference "Item.count", -3 do
      CleanupExpiredItemsJob.perform_now
    end
  end
end
