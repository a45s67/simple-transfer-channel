require "test_helper"

# 🔒 不變量 3:跨 channel 不可存取。
class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_channel("alpha")
    @b = create_channel("bravo")
    @b_text = create_text_item(@b, body: "bravo 的秘密")
    @b_file = create_file_item(@b, filename: "bravo.bin")
  end

  test "未登入時存取 channel 頁會被導回首頁" do
    get channel_path(name: "alpha")

    assert_redirected_to root_path
  end

  test "未登入時 download 會被導回首頁" do
    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_redirected_to root_path
  end

  test "未登入時 destroy 會被導回首頁,且項目仍存在" do
    delete channel_item_path(name: "bravo", id: @b_text.id)

    assert_redirected_to root_path
    assert Item.exists?(@b_text.id)
  end

  test "未登入時 create 會被導回首頁" do
    assert_no_difference "Item.count" do
      post channel_items_path(name: "bravo"), params: { body: "hi" }
    end

    assert_redirected_to root_path
  end

  test "登入 channel A 後存取 channel B 會被導回首頁(即使 B 存在)" do
    login_channel(@a)

    get channel_path(name: "bravo")

    assert_redirected_to root_path
  end

  test "登入 channel A 後,用 channel B 的 item id 呼叫 download 會得到 404" do
    login_channel(@a)

    get download_channel_item_path(name: "alpha", id: @b_file.id)

    assert_response :not_found
  end

  test "登入 channel A 後,用 channel B 的名稱呼叫 download 會被導回首頁" do
    login_channel(@a)

    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_redirected_to root_path
  end

  test "登入 channel A 後,用 channel B 的 item id 呼叫 destroy 會得到 404 且項目仍存在" do
    login_channel(@a)

    delete channel_item_path(name: "alpha", id: @b_text.id)

    assert_response :not_found
    assert Item.exists?(@b_text.id)
  end

  test "登入 channel A 後,用 channel B 的名稱呼叫 destroy 會被導回首頁且項目仍存在" do
    login_channel(@a)

    delete channel_item_path(name: "bravo", id: @b_text.id)

    assert_redirected_to root_path
    assert Item.exists?(@b_text.id)
  end

  test "登入 channel A 後,POST 到 channel B 不會在 B 建立項目" do
    login_channel(@a)

    assert_no_difference "@b.items.count" do
      post channel_items_path(name: "bravo"), params: { body: "hi" }
    end

    assert_redirected_to root_path
  end

  test "admin 登入不會取得任何 channel 的內容存取權" do
    login_admin

    assert_redirected_to admin_channels_path

    get channel_path(name: "bravo")

    assert_redirected_to root_path

    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_redirected_to root_path

    delete channel_item_path(name: "bravo", id: @b_text.id)

    assert_redirected_to root_path
    assert Item.exists?(@b_text.id)
  end

  test "channel 登入不會取得 admin 存取權" do
    login_channel(@a)

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "同時登入兩個 channel 後,兩邊都能正常存取" do
    login_channel(@a)
    login_channel(@b)

    get channel_path(name: "alpha")

    assert_response :success

    get channel_path(name: "bravo")

    assert_response :success
    assert_match "bravo 的秘密", response.body

    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_response :success
  end

  test "登出會失去所有 channel 的存取權" do
    login_channel(@a)
    login_channel(@b)

    delete logout_path

    get channel_path(name: "alpha")

    assert_redirected_to root_path

    get channel_path(name: "bravo")

    assert_redirected_to root_path
  end

  test "channel 被刪除後,原本登入的 session 失去存取權" do
    login_channel(@a)
    @a.destroy

    get channel_path(name: "alpha")

    assert_redirected_to root_path
  end

  test "ActiveStorage 自己的 blob 服務路由沒有被畫出來" do
    # 那些路由只認 blob 的 signed_id、完全不看 session,
    # 留著等於同時繞過不變量 1 與不變量 3。
    signed_id = @b_file.file.blob.signed_id

    [
      "/rails/active_storage/blobs/redirect/#{signed_id}/bravo.bin",
      "/rails/active_storage/blobs/proxy/#{signed_id}/bravo.bin",
      "/rails/active_storage/blobs/#{signed_id}/bravo.bin",
      "/rails/active_storage/disk/#{signed_id}/bravo.bin"
    ].each do |path|
      get path

      assert_response :not_found, "#{path} 不應該存在"
    end
  end
end
