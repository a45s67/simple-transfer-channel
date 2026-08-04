require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "ADMIN_USER 為空字串時任何登入嘗試都失敗" do
    with_env("ADMIN_USER" => "", "ADMIN_PASSWORD" => ADMIN_PASSWORD) do
      post admin_login_path, params: { user: "", password: ADMIN_PASSWORD }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "ADMIN_PASSWORD 為空字串時任何登入嘗試都失敗" do
    with_env("ADMIN_USER" => ADMIN_USER, "ADMIN_PASSWORD" => "") do
      post admin_login_path, params: { user: ADMIN_USER, password: "" }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "兩個 ENV 都沒設時任何登入嘗試都失敗" do
    with_env("ADMIN_USER" => nil, "ADMIN_PASSWORD" => nil) do
      post admin_login_path, params: { user: "admin", password: "admin" }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "正確帳密可登入" do
    login_admin

    assert_redirected_to admin_channels_path

    get admin_channels_path

    assert_response :success
  end

  test "錯誤密碼不能登入" do
    login_admin(password: "wrong")

    assert_redirected_to admin_root_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "錯誤帳號不能登入" do
    login_admin(user: "someone-else")

    assert_redirected_to admin_root_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "未登入 admin 時存取 /admin/channels 會被導向 admin 登入頁" do
    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "登出後失去 admin 存取權" do
    login_admin
    delete admin_logout_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "admin 可以建立 channel" do
    login_admin

    assert_difference "Channel.count", 1 do
      post admin_channels_path, params: { channel: { name: "New-Lab", password: "password123" } }
    end

    assert_redirected_to admin_channels_path
    assert_equal "new-lab", Channel.last.name
  end

  test "建立 channel 失敗時回到列表頁並顯示錯誤" do
    login_admin

    assert_no_difference "Channel.count" do
      post admin_channels_path, params: { channel: { name: "x", password: "short" } }
    end

    assert_response :unprocessable_content
    assert_match "Password", response.body
  end

  test "admin 可以刪除 channel,底下的項目一併消失" do
    channel = create_channel("lab1")
    create_text_item(channel)
    create_file_item(channel)
    login_admin

    assert_difference "Channel.count", -1 do
      assert_difference "Item.count", -2 do
        delete admin_channel_path(channel)
      end
    end

    assert_redirected_to admin_channels_path
  end

  test "channel 列表顯示 alive 的項目數" do
    channel = create_channel("lab1")
    create_text_item(channel)
    create_text_item(channel, expires_at: 1.hour.from_now)
    create_text_item(channel, expires_at: 1.hour.ago)
    login_admin

    get admin_channels_path

    assert_response :success
    assert_match "2 個項目", response.body
  end

  test "已登入 admin 時進 /admin 會直接導到 channel 列表" do
    login_admin

    get admin_root_path

    assert_redirected_to admin_channels_path
  end
end
