require "test_helper"

# 🔒 不變量 2:channel 名稱可枚舉,登入端點必須限流。
class RateLimitTest < ActionDispatch::IntegrationTest
  setup { @channel = create_channel("lab1") }

  test "對 /login 連續送 11 次錯誤密碼,第 11 次得到限流回應而非密碼錯誤" do
    10.times do |i|
      post login_path, params: { name: "lab1", password: "wrong" }

      assert_redirected_to root_path
      assert_equal "channel 名稱或密碼錯誤", flash[:alert], "第 #{i + 1} 次不該被限流"
    end

    post login_path, params: { name: "lab1", password: "wrong" }

    assert_redirected_to root_path
    assert_equal "嘗試次數過多,請稍後再試", flash[:alert]
  end

  test "限流會擋掉正確密碼的登入,不只是錯誤密碼" do
    10.times { post login_path, params: { name: "lab1", password: "wrong" } }

    post login_path, params: { name: "lab1", password: DEFAULT_PASSWORD }

    assert_redirected_to root_path
    assert_equal "嘗試次數過多,請稍後再試", flash[:alert]

    get channel_path(name: "lab1")

    assert_redirected_to root_path
  end

  # GOTCHAS.md 第 6 條:cache store 不對的話限流會「靜默失效」——
  # 不報錯,就是不擋。這個測試直接盯著計數器,讓失效原因一眼看得出來。
  test "限流計數確實寫進 cache" do
    key = "rate-limit:sessions:127.0.0.1"

    assert_nil Rails.cache.read(key, raw: true)

    post login_path, params: { name: "lab1", password: "wrong" }

    assert_equal 1, Rails.cache.read(key, raw: true).to_i
  end

  test "對 /admin/login 連續送 11 次錯誤密碼,第 11 次得到限流回應" do
    10.times do |i|
      login_admin(password: "wrong")

      assert_redirected_to admin_root_path
      assert_equal "帳號或密碼錯誤", flash[:alert], "第 #{i + 1} 次不該被限流"
    end

    login_admin(password: "wrong")

    assert_redirected_to admin_root_path
    assert_equal "嘗試次數過多,請稍後再試", flash[:alert]
  end

  test "admin 的限流不會影響 channel 的限流,兩者 scope 分開" do
    10.times { login_admin(password: "wrong") }

    post login_path, params: { name: "lab1", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end
end
