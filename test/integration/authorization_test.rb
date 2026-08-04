require "test_helper"

# 🔒 Invariant 3: no cross-channel access.
class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_channel("alpha")
    @b = create_channel("bravo")
    @b_text = create_text_item(@b, body: "bravo private note")
    @b_file = create_file_item(@b, filename: "bravo.bin")
  end

  test "a signed-out visitor is redirected away from a channel page" do
    get channel_path(name: "alpha")

    assert_redirected_to root_path
  end

  test "a signed-out visitor is redirected away from download" do
    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_redirected_to root_path
  end

  test "a signed-out visitor is redirected away from destroy and the item survives" do
    delete channel_item_path(name: "bravo", id: @b_text.id)

    assert_redirected_to root_path
    assert Item.exists?(@b_text.id)
  end

  test "a signed-out visitor is redirected away from create" do
    assert_no_difference "Item.count" do
      post channel_items_path(name: "bravo"), params: { body: "hi" }
    end

    assert_redirected_to root_path
  end

  test "signed in to channel A, channel B is off limits even though it exists" do
    login_channel(@a)

    get channel_path(name: "bravo")

    assert_redirected_to root_path
  end

  test "signed in to channel A, downloading channel B's item id returns 404" do
    login_channel(@a)

    get download_channel_item_path(name: "alpha", id: @b_file.id)

    assert_response :not_found
  end

  test "signed in to channel A, downloading under channel B's name redirects away" do
    login_channel(@a)

    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_redirected_to root_path
  end

  test "signed in to channel A, destroying channel B's item id returns 404 and the item survives" do
    login_channel(@a)

    delete channel_item_path(name: "alpha", id: @b_text.id)

    assert_response :not_found
    assert Item.exists?(@b_text.id)
  end

  test "signed in to channel A, destroying under channel B's name redirects away and the item survives" do
    login_channel(@a)

    delete channel_item_path(name: "bravo", id: @b_text.id)

    assert_redirected_to root_path
    assert Item.exists?(@b_text.id)
  end

  test "signed in to channel A, posting to channel B creates nothing in B" do
    login_channel(@a)

    assert_no_difference "@b.items.count" do
      post channel_items_path(name: "bravo"), params: { body: "hi" }
    end

    assert_redirected_to root_path
  end

  test "being admin grants no access to any channel's contents" do
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

  test "being signed in to a channel grants no admin access" do
    login_channel(@a)

    get admin_channels_path

    assert_redirected_to admin_root_path
  end

  test "signed in to two channels at once, both stay reachable" do
    login_channel(@a)
    login_channel(@b)

    get channel_path(name: "alpha")

    assert_response :success

    get channel_path(name: "bravo")

    assert_response :success
    assert_match "bravo private note", response.body

    get download_channel_item_path(name: "bravo", id: @b_file.id)

    assert_response :success
  end

  test "signing out drops access to every channel" do
    login_channel(@a)
    login_channel(@b)

    delete logout_path

    get channel_path(name: "alpha")

    assert_redirected_to root_path

    get channel_path(name: "bravo")

    assert_redirected_to root_path
  end

  test "once a channel is destroyed its signed-in sessions lose access" do
    login_channel(@a)
    @a.destroy

    get channel_path(name: "alpha")

    assert_redirected_to root_path
  end

  test "ActiveStorage's own blob-serving routes are not drawn" do
    # They authenticate a signed_id and ignore the session entirely, so leaving
    # them in place would bypass invariants 1 and 3 at once.
    signed_id = @b_file.file.blob.signed_id

    [
      "/rails/active_storage/blobs/redirect/#{signed_id}/bravo.bin",
      "/rails/active_storage/blobs/proxy/#{signed_id}/bravo.bin",
      "/rails/active_storage/blobs/#{signed_id}/bravo.bin",
      "/rails/active_storage/disk/#{signed_id}/bravo.bin"
    ].each do |path|
      get path

      assert_response :not_found, "#{path} should not exist"
    end
  end
end
