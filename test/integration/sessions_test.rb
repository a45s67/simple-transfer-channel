require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup { @channel = create_channel("lab1") }

  test "correct credentials sign you in and land you on the channel page" do
    login_channel(@channel)

    assert_redirected_to channel_path(name: "lab1")

    get channel_path(name: "lab1")

    assert_response :success
  end

  test "a differently cased name still signs in" do
    post login_path, params: { name: "LAB1", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end

  test "surrounding whitespace in the name still signs in" do
    post login_path, params: { name: "  lab1  ", password: DEFAULT_PASSWORD }

    assert_redirected_to channel_path(name: "lab1")
  end

  test "a wrong password does not sign you in" do
    post login_path, params: { name: "lab1", password: "wrong" }

    assert_redirected_to root_path
    assert_equal "Wrong channel name or password", flash[:alert]
  end

  test "an unknown channel and a wrong password give the same message" do
    post login_path, params: { name: "nope", password: "whatever" }

    assert_redirected_to root_path
    assert_equal "Wrong channel name or password", flash[:alert]
  end

  test "the home page lists the channels you are signed in to" do
    other = create_channel("lab2")
    login_channel(@channel)
    login_channel(other)

    get root_path

    assert_response :success
    assert_match "#lab1", response.body
    assert_match "#lab2", response.body
  end

  test "the home page lists nothing when you are signed out" do
    get root_path

    assert_response :success
    assert_no_match "#lab1", response.body
  end

  test "signing out drops the channel from the session" do
    login_channel(@channel)

    get channel_path(name: "lab1")

    assert_response :success

    delete logout_path

    get channel_path(name: "lab1")

    assert_redirected_to root_path
  end

  test "a new item is broadcast to the channel's turbo stream" do
    login_channel(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      post channel_items_path(name: "lab1"), params: { body: "hello" }
    end
  end

  test "deleting an item broadcasts a remove" do
    item = create_text_item(@channel)
    login_channel(@channel)

    assert_turbo_stream_broadcasts @channel, count: 1 do
      delete channel_item_path(name: "lab1", id: item.id)
    end
  end

  test "the channel page carries the turbo stream subscription tag" do
    login_channel(@channel)

    get channel_path(name: "lab1")

    assert_response :success
    assert_match "turbo-cable-stream-source", response.body
  end
end
