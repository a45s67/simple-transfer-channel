require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "a blank ADMIN_USER makes every login attempt fail" do
    with_env("ADMIN_USER" => "", "ADMIN_PASSWORD" => ADMIN_PASSWORD) do
      post admin_login_path, params: { user: "", password: ADMIN_PASSWORD }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "a blank ADMIN_PASSWORD makes every login attempt fail" do
    with_env("ADMIN_USER" => ADMIN_USER, "ADMIN_PASSWORD" => "") do
      post admin_login_path, params: { user: ADMIN_USER, password: "" }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "with neither ENV var set every login attempt fails" do
    with_env("ADMIN_USER" => nil, "ADMIN_PASSWORD" => nil) do
      post admin_login_path, params: { user: "admin", password: "admin" }

      assert_redirected_to admin_root_path

      get admin_channels_path

      assert_redirected_to admin_root_path
    end
  end

  test "correct credentials sign the admin in" do
    login_admin

    assert_redirected_to admin_channels_path

    get admin_channels_path

    assert_response :success
  end

  test "a wrong password does not sign the admin in" do
    login_admin(password: "wrong")

    assert_redirected_to admin_root_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "a wrong username does not sign the admin in" do
    login_admin(user: "someone-else")

    assert_redirected_to admin_root_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "a signed-out admin is redirected from /admin/channels to the login page" do
    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "signing out drops admin access" do
    login_admin
    delete admin_logout_path

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "an admin can create a channel" do
    login_admin

    assert_difference "Channel.count", 1 do
      post admin_channels_path, params: { channel: { name: "New-Lab", password: "password123" } }
    end

    assert_redirected_to admin_channels_path
    assert_equal "new-lab", Channel.last.name
  end

  test "a failed create re-renders the list with the error" do
    login_admin

    assert_no_difference "Channel.count" do
      post admin_channels_path, params: { channel: { name: "x", password: "short" } }
    end

    assert_response :unprocessable_content
    assert_match "Password", response.body
  end

  test "an admin can delete a channel and its items go with it" do
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

  test "the channel list counts only live items" do
    channel = create_channel("lab1")
    create_text_item(channel)
    create_text_item(channel, expires_at: 1.hour.from_now)
    create_text_item(channel, expires_at: 1.hour.ago)
    login_admin

    get admin_channels_path

    assert_response :success
    assert_match "2 items", response.body
  end

  test "a signed-in admin visiting /admin goes straight to the channel list" do
    login_admin

    get admin_root_path

    assert_redirected_to admin_channels_path
  end
end
