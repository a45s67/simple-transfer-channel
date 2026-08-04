require "test_helper"

class ItemsTest < ActionDispatch::IntegrationTest
  setup do
    @channel = create_channel("lab1")
    login_channel(@channel)
  end

  test "送出文字會建立 text 項目" do
    assert_difference "Item.count", 1 do
      post channel_items_path(name: "lab1"), params: { body: "多行\n文字" }
    end

    assert_response :created
    item = @channel.items.sole

    assert_predicate item, :text?
    assert_equal "多行\n文字", item.body
  end

  test "送出空白文字會得到明確錯誤,不是 500" do
    [ "", "   ", "\n" ].each do |body|
      assert_no_difference "Item.count" do
        post channel_items_path(name: "lab1"), params: { body: body }
      end

      assert_response :unprocessable_content
      assert_equal "沒有內容", response.parsed_body["error"]
    end
  end

  test "什麼都不送會得到明確錯誤" do
    post channel_items_path(name: "lab1")

    assert_response :unprocessable_content
    assert_equal "沒有內容", response.parsed_body["error"]
  end

  test "上傳檔案會建立 file 項目" do
    blob = create_blob(content: "binary", filename: "sample.bin")

    assert_difference "Item.count", 1 do
      post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
    end

    assert_response :created
    item = @channel.items.sole

    assert_predicate item, :file?
    assert_equal "sample.bin", item.file.filename.to_s
  end

  test "上傳 0 bytes 的檔案得到明確錯誤訊息,不是 500" do
    blob = create_blob(content: "", filename: "empty.bin")

    assert_no_difference "Item.count" do
      post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
    end

    assert_response :unprocessable_content
    assert_match(/0 bytes/, response.parsed_body["error"])
  end

  test "上傳超過 MAX_UPLOAD_MB 的檔案得到明確錯誤訊息" do
    with_env("MAX_UPLOAD_MB" => "1") do
      blob = create_blob(content: "x" * 2.megabytes, filename: "big.bin")

      assert_no_difference "Item.count" do
        post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }
      end

      assert_response :unprocessable_content
      assert_match(/超過上限/, response.parsed_body["error"])
    end
  end

  test "無效的 signed_id 得到明確錯誤,不是 500" do
    assert_no_difference "Item.count" do
      post channel_items_path(name: "lab1"), params: { signed_id: "not-a-real-signed-id" }
    end

    assert_response :unprocessable_content
    assert_equal "上傳憑證無效", response.parsed_body["error"]
  end

  test "建立的項目帶上 DEFAULT_TTL_DAYS 算出的 expires_at" do
    with_env("DEFAULT_TTL_DAYS" => "3") do
      freeze_time do
        post channel_items_path(name: "lab1"), params: { body: "hi" }

        assert_in_delta 3.days.from_now.to_f, @channel.items.sole.expires_at.to_f, 1
      end
    end
  end

  test "DEFAULT_TTL_DAYS=0 時建立的項目不會過期" do
    with_env("DEFAULT_TTL_DAYS" => "0") do
      post channel_items_path(name: "lab1"), params: { body: "hi" }

      assert_nil @channel.items.sole.expires_at
    end
  end

  test "可以刪除自己 channel 的項目" do
    item = create_text_item(@channel)

    assert_difference "Item.count", -1 do
      delete channel_item_path(name: "lab1", id: item.id)
    end

    assert_response :no_content
  end

  test "🔒 文字項目含 script 標籤時顯示為純文字,不會被當成 HTML" do
    create_text_item(@channel, body: "<script>alert(1)</script>")

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
    assert_match "&lt;script&gt;alert(1)&lt;/script&gt;", response.body
  end

  test "🔒 檔名含 script 標籤時也會被 escape" do
    create_file_item(@channel, filename: "<script>alert(1)</script>.bin")

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "時間軸只顯示還活著的項目,新的在上面" do
    old = create_text_item(@channel, body: "較早的")
    travel 1.minute
    fresh = create_text_item(@channel, body: "較晚的")
    create_text_item(@channel, body: "已過期的", expires_at: 1.hour.ago)

    get channel_path(name: "lab1")

    assert_response :success
    assert_no_match "已過期的", response.body
    assert_operator response.body.index("較晚的"), :<, response.body.index("較早的")
    assert_match "較早的", response.body
    assert_equal [ fresh.id, old.id ].sort, @channel.items.alive.pluck(:id).sort
  end

  test "大寫的 channel 路徑不匹配 route constraint" do
    get "/c/LAB1"

    assert_response :not_found
  end
end
