require "test_helper"

# 🔒 Invariant 2: channel names are enumerable, so the login endpoints must be rate limited.
class RateLimitTest < ActionDispatch::IntegrationTest
  setup { @channel = create_channel("lab1") }

  test "the 11th wrong password on /login is rate limited, not just rejected" do
    10.times do |i|
      post login_path, params: { name: "lab1", password: "wrong" }

      assert_redirected_to root_path
      assert_equal "Wrong channel name or password", flash[:alert], "attempt #{i + 1} should not be limited"
    end

    post login_path, params: { name: "lab1", password: "wrong" }

    assert_redirected_to root_path
    assert_equal "Too many attempts, try again later", flash[:alert]
  end

  test "the limit blocks the correct password too, not only wrong ones" do
    10.times { post login_path, params: { name: "lab1", password: "wrong" } }

    post login_path, params: { name: "lab1", password: DEFAULT_PASSWORD }

    assert_redirected_to root_path
    assert_equal "Too many attempts, try again later", flash[:alert]

    get channel_path(name: "lab1")

    assert_redirected_to root_path
  end

  # With the wrong cache store the limit fails silently -- no error, it just
  # doesn't block. This watches the counter directly so the cause is obvious.
  test "the rate limit counter actually reaches the cache" do
    key = "rate-limit:sessions:127.0.0.1"

    assert_nil Rails.cache.read(key, raw: true)

    post login_path, params: { name: "lab1", password: "wrong" }

    assert_equal 1, Rails.cache.read(key, raw: true).to_i
  end

  test "the 11th wrong password on /admin/login is rate limited" do
    10.times do |i|
      login_admin(password: "wrong")

      assert_redirected_to admin_root_path
      assert_equal "Wrong username or password", flash[:alert], "attempt #{i + 1} should not be limited"
    end

    login_admin(password: "wrong")

    assert_redirected_to admin_root_path
    assert_equal "Too many attempts, try again later", flash[:alert]
  end

  test "the admin limit and the channel limit are scoped separately" do
    10.times { login_admin(password: "wrong") }

    post login_path, params: { name: "lab1", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end
end
