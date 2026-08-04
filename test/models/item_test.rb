require "test_helper"

class ItemTest < ActiveSupport::TestCase
  setup { @channel = create_channel("lab1") }

  test "a text item with a blank body is invalid" do
    [ nil, "", "   ", "\n\t " ].each do |body|
      item = @channel.items.new(kind: "text", body: body)

      assert_not item.valid?, "body=#{body.inspect} should not be valid"
      assert_predicate item.errors[:body], :any?
    end
  end

  test "a text item with a body is valid" do
    assert_predicate @channel.items.new(kind: "text", body: "hi"), :valid?
  end

  test "a file item without an attached file is invalid" do
    item = @channel.items.new(kind: "file")

    assert_not item.valid?
    assert_predicate item.errors[:file], :any?
  end

  test "kind only accepts file or text" do
    item = @channel.items.new(kind: "video", body: "hi")

    assert_not item.valid?
    assert_predicate item.errors[:kind], :any?
  end

  test "the alive scope excludes expired items and includes ones with a nil expires_at" do
    never   = create_text_item(@channel, body: "never", expires_at: nil)
    future  = create_text_item(@channel, body: "future", expires_at: 1.hour.from_now)
    expired = create_text_item(@channel, body: "expired", expires_at: 1.hour.ago)

    alive = @channel.items.alive

    assert_includes alive, never
    assert_includes alive, future
    assert_not_includes alive, expired
  end

  test "the expired scope contains only expired items" do
    create_text_item(@channel, body: "never", expires_at: nil)
    create_text_item(@channel, body: "future", expires_at: 1.hour.from_now)
    expired = create_text_item(@channel, body: "expired", expires_at: 1.hour.ago)

    assert_equal [ expired ], Item.expired.to_a
  end

  test "DEFAULT_TTL_DAYS defaults to 7 days out" do
    with_env("DEFAULT_TTL_DAYS" => nil) do
      freeze_time do
        assert_in_delta 7.days.from_now.to_f, Item.default_expires_at.to_f, 1
      end
    end
  end

  test "DEFAULT_TTL_DAYS is configurable" do
    with_env("DEFAULT_TTL_DAYS" => "3") do
      freeze_time do
        assert_in_delta 3.days.from_now.to_f, Item.default_expires_at.to_f, 1
      end
    end
  end

  test "with DEFAULT_TTL_DAYS=0 a new item has a nil expires_at" do
    with_env("DEFAULT_TTL_DAYS" => "0") do
      assert_nil Item.default_expires_at

      item = @channel.items.create!(kind: "text", body: "hi", expires_at: Item.default_expires_at)

      assert_nil item.expires_at
    end
  end

  test "a 0 byte file is invalid" do
    item = @channel.items.new(kind: "file")
    item.file.attach(create_blob(content: "", filename: "empty.bin"))

    assert_not item.valid?
    assert_match(/0 bytes/, item.errors.full_messages.to_sentence)
  end

  test "a file over MAX_UPLOAD_MB is invalid" do
    with_env("MAX_UPLOAD_MB" => "1") do
      item = @channel.items.new(kind: "file")
      item.file.attach(create_blob(content: "x" * 2.megabytes, filename: "big.bin"))

      assert_not item.valid?
      assert_match(/exceeds/, item.errors.full_messages.to_sentence)
    end
  end

  test "a file exactly at MAX_UPLOAD_MB is valid" do
    with_env("MAX_UPLOAD_MB" => "1") do
      item = @channel.items.new(kind: "file")
      item.file.attach(create_blob(content: "x" * 1.megabyte, filename: "exact.bin"))

      assert_predicate item, :valid?
    end
  end

  test "creating an item broadcasts a prepend to its channel" do
    assert_turbo_stream_broadcasts @channel, count: 1 do
      create_text_item(@channel)
    end
  end

  test "destroying an item broadcasts a remove to its channel" do
    item = create_text_item(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      item.destroy
    end
  end

  test "the broadcast partial does not depend on controller context" do
    item = create_file_item(@channel, filename: "sample.bin")

    # Render with no request at all -- this is how a model-layer broadcast does it
    html = ApplicationController.render(partial: "items/item", locals: { item: item })

    assert_match "sample.bin", html
    assert_match "/c/lab1/items/#{item.id}/download", html
  end
end
