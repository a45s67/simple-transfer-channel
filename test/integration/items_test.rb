require "test_helper"

class ItemsTest < ActionDispatch::IntegrationTest
  setup do
    @channel = create_channel("lab1")
    login_channel(@channel)
  end

  test "sending text creates a text item" do
    assert_difference "Item.count", 1 do
      post channel_items_path(name: "lab1"), params: { body: "line one\nline two" }
    end

    assert_response :created
    item = @channel.items.sole

    assert_predicate item, :text?
    assert_equal "line one\nline two", item.body
  end

  test "sending blank text gives a clear error, not a 500" do
    [ "", "   ", "\n" ].each do |body|
      assert_no_difference "Item.count" do
        post channel_items_path(name: "lab1"), params: { body: body }
      end

      assert_response :unprocessable_content
      assert_equal "Nothing to save", response.parsed_body["error"]
    end
  end

  test "sending nothing at all gives a clear error" do
    post channel_items_path(name: "lab1")

    assert_response :unprocessable_content
    assert_equal "Nothing to save", response.parsed_body["error"]
  end

  test "uploading a file creates a file item" do
    blob = create_blob(content: "binary", filename: "sample.bin")

    assert_difference "Item.count", 1 do
      post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
    end

    assert_response :created
    item = @channel.items.sole

    assert_predicate item, :file?
    assert_equal "sample.bin", item.file.filename.to_s
  end

  test "uploading a 0 byte file gives a clear error, not a 500" do
    blob = create_blob(content: "", filename: "empty.bin")

    assert_no_difference "Item.count" do
      post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
    end

    assert_response :unprocessable_content
    assert_match(/0 bytes/, response.parsed_body["error"])
  end

  test "uploading a file over MAX_UPLOAD_MB gives a clear error" do
    with_env("MAX_UPLOAD_MB" => "1") do
      blob = create_blob(content: "x" * 2.megabytes, filename: "big.bin")

      assert_no_difference "Item.count" do
        post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
      end

      assert_response :unprocessable_content
      assert_match(/exceeds/, response.parsed_body["error"])
    end
  end

  test "an invalid signed_id gives a clear error, not a 500" do
    assert_no_difference "Item.count" do
      post channel_items_path(name: "lab1"), params: { signed_id: "not-a-real-signed-id" }
    end

    assert_response :unprocessable_content
    assert_equal "Invalid upload token", response.parsed_body["error"]
  end

  test "a new item carries the expires_at derived from DEFAULT_TTL_DAYS" do
    with_env("DEFAULT_TTL_DAYS" => "3") do
      freeze_time do
        post channel_items_path(name: "lab1"), params: { body: "hi" }

        assert_in_delta 3.days.from_now.to_f, @channel.items.sole.expires_at.to_f, 1
      end
    end
  end

  test "with DEFAULT_TTL_DAYS=0 a new item never expires" do
    with_env("DEFAULT_TTL_DAYS" => "0") do
      post channel_items_path(name: "lab1"), params: { body: "hi" }

      assert_nil @channel.items.sole.expires_at
    end
  end

  test "an item in your own channel can be deleted" do
    item = create_text_item(@channel)

    assert_difference "Item.count", -1 do
      delete channel_item_path(name: "lab1", id: item.id)
    end

    assert_response :no_content
  end

  test "🔒 a text item containing a script tag is shown as plain text, never as HTML" do
    create_text_item(@channel, body: "<script>alert(1)</script>")

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
    assert_match "&lt;script&gt;alert(1)&lt;/script&gt;", response.body
  end

  test "🔒 a filename containing a script tag is escaped too" do
    create_file_item(@channel, filename: "<script>alert(1)</script>.bin")

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "the timeline shows only live items, newest first" do
    old = create_text_item(@channel, body: "the earlier one")
    travel 1.minute
    fresh = create_text_item(@channel, body: "the later one")
    create_text_item(@channel, body: "the expired one", expires_at: 1.hour.ago)

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "the expired one", response.body
    assert_operator response.body.index("the later one"), :<, response.body.index("the earlier one")
    assert_match "the earlier one", response.body
    assert_equal [ fresh.id, old.id ].sort, @channel.items.alive.pluck(:id).sort
  end

  test "an uppercase channel path does not match the route constraint" do
    get "/c/LAB1"

    assert_response :not_found
  end
end
