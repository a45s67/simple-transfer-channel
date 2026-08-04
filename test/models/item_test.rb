require "test_helper"

class ItemTest < ActiveSupport::TestCase
  setup { @channel = create_channel("lab1") }

  test "kind text 且 body 空白時無效" do
    [ nil, "", "   ", "\n\t " ].each do |body|
      item = @channel.items.new(kind: "text", body: body)

      assert_not item.valid?, "body=#{body.inspect} 不應該通過驗證"
      assert_predicate item.errors[:body], :any?
    end
  end

  test "kind text 且有 body 時有效" do
    assert_predicate @channel.items.new(kind: "text", body: "hi"), :valid?
  end

  test "kind file 且沒有 attached file 時無效" do
    item = @channel.items.new(kind: "file")

    assert_not item.valid?
    assert_predicate item.errors[:file], :any?
  end

  test "kind 只接受 file 或 text" do
    item = @channel.items.new(kind: "video", body: "hi")

    assert_not item.valid?
    assert_predicate item.errors[:kind], :any?
  end

  test "alive scope 排除已過期的項目、包含 expires_at 為 nil 的項目" do
    never    = create_text_item(@channel, body: "never", expires_at: nil)
    future   = create_text_item(@channel, body: "future", expires_at: 1.hour.from_now)
    expired  = create_text_item(@channel, body: "expired", expires_at: 1.hour.ago)

    alive = @channel.items.alive

    assert_includes alive, never
    assert_includes alive, future
    assert_not_includes alive, expired
  end

  test "expired scope 只包含已過期的項目" do
    create_text_item(@channel, body: "never", expires_at: nil)
    create_text_item(@channel, body: "future", expires_at: 1.hour.from_now)
    expired = create_text_item(@channel, body: "expired", expires_at: 1.hour.ago)

    assert_equal [ expired ], Item.expired.to_a
  end

  test "DEFAULT_TTL_DAYS 預設為 7 天後" do
    with_env("DEFAULT_TTL_DAYS" => nil) do
      freeze_time do
        assert_in_delta 7.days.from_now.to_f, Item.default_expires_at.to_f, 1
      end
    end
  end

  test "DEFAULT_TTL_DAYS 可以調整" do
    with_env("DEFAULT_TTL_DAYS" => "3") do
      freeze_time do
        assert_in_delta 3.days.from_now.to_f, Item.default_expires_at.to_f, 1
      end
    end
  end

  test "DEFAULT_TTL_DAYS=0 時建立的項目 expires_at 為 nil" do
    with_env("DEFAULT_TTL_DAYS" => "0") do
      assert_nil Item.default_expires_at

      item = @channel.items.create!(kind: "text", body: "hi", expires_at: Item.default_expires_at)

      assert_nil item.expires_at
    end
  end

  test "0 bytes 的檔案無效" do
    item = @channel.items.new(kind: "file")
    item.file.attach(create_blob(content: "", filename: "empty.bin"))

    assert_not item.valid?
    assert_match(/0 bytes/, item.errors.full_messages.to_sentence)
  end

  test "超過 MAX_UPLOAD_MB 的檔案無效" do
    with_env("MAX_UPLOAD_MB" => "1") do
      item = @channel.items.new(kind: "file")
      item.file.attach(create_blob(content: "x" * 2.megabytes, filename: "big.bin"))

      assert_not item.valid?
      assert_match(/超過上限/, item.errors.full_messages.to_sentence)
    end
  end

  test "剛好在 MAX_UPLOAD_MB 以內的檔案有效" do
    with_env("MAX_UPLOAD_MB" => "1") do
      item = @channel.items.new(kind: "file")
      item.file.attach(create_blob(content: "x" * 1.megabyte, filename: "exact.bin"))

      assert_predicate item, :valid?
    end
  end

  test "建立項目會 broadcast prepend 到所屬 channel" do
    assert_turbo_stream_broadcasts @channel, count: 1 do
      create_text_item(@channel)
    end
  end

  test "刪除項目會 broadcast remove 到所屬 channel" do
    item = create_text_item(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      item.destroy
    end
  end

  test "廣播用的 partial 不依賴 controller context" do
    item = create_file_item(@channel, filename: "sample.bin")

    # 直接在沒有請求的情況下渲染,GOTCHAS.md 第 5 條
    html = ApplicationController.render(partial: "items/item", locals: { item: item })

    assert_match "sample.bin", html
    assert_match "/c/lab1/items/#{item.id}/download", html
  end
end
