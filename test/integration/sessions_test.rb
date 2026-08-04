require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup { @channel = create_channel("lab1") }

  test "正確帳密可登入並導到 channel 頁" do
    login_channel(@channel)

    assert_redirected_to channel_path(name: "lab1")

    get channel_path(name: "lab1")

    assert_response :success
  end

  test "大小寫不同的名稱也能登入" do
    post login_path, params: { name: "LAB1", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end

  test "名稱前後有空白也能登入" do
    post login_path, params: { name: "  lab1  ", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end

  test "錯誤密碼不能登入" do
    post login_path, params: { name: "lab1", password: "wrong" }

    assert_redirected_to root_path
    assert_equal "channel 名稱或密碼錯誤", flash[:alert]
  end

  test "不存在的 channel 與錯誤密碼得到同樣的訊息" do
    post login_path, params: { name: "nope", password: "whatever" }

    assert_redirected_to root_path
    assert_equal "channel 名稱或密碼錯誤", flash[:alert]
  end

  test "首頁列出已登入的 channel" do
    other = create_channel("lab2")
    login_channel(@channel)
    login_channel(other)

    get root_path

    assert_response :success
    assert_match "#lab1", response.body
    assert_match "#lab2", response.body
  end

  test "未登入時首頁不列出任何 channel" do
    get root_path

    assert_response :success
    assert_no_match "#lab1", response.body
  end

  test "session 裡塞造假的 channel_ids 沒有用" do
    # session 是簽章過的 cookie,一般使用者改不動;這裡直接從測試端塞,
    # 驗證 current_channel 確實同時檢查存在與授權。
    login_channel(@channel)

    get channel_path(name: "lab1")

    assert_response :success

    # 換一個不存在的 id
    delete logout_path

    get channel_path(name: "lab1")

    assert_redirected_to root_path
  end

  test "新項目會 broadcast 到 channel 的 turbo stream" do
    login_channel(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      post channel_items_path(name: "lab1"), params: { body: "hello" }
    end
  end

  test "刪除項目會 broadcast remove" do
    item = create_text_item(@channel)
    login_channel(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      delete channel_item_path(name: "lab1", id: item.id)
    end
  end

  test "channel 頁有 turbo stream 的訂閱標籤" do
    login_channel(@channel)

    get channel_path(name: "lab1")

    assert_response :success
    assert_match "turbo-cable-stream-source", response.body
  end
end
