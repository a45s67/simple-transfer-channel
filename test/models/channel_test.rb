require "test_helper"

class ChannelTest < ActiveSupport::TestCase
  test "name is normalized to lowercase before it is stored" do
    channel = create_channel("Lab1")

    assert_equal "lab1", channel.name
  end

  test "Lab1 and lab1 are the same channel" do
    create_channel("Lab1")
    duplicate = Channel.new(name: "lab1", password: DEFAULT_PASSWORD)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_equal 1, Channel.count
  end

  test "by_name looks up with the normalized name" do
    channel = create_channel("lab1")

    assert_equal channel, Channel.by_name("LAB1")
    assert_equal channel, Channel.by_name("  Lab1  ")
    assert_nil Channel.by_name("lab2")
  end

  test "a malformed name is rejected" do
    # Uppercase is normalized away first, so these are the forms that are still
    # invalid after normalization.
    [
      "a",                    # too short
      "a" * 33,               # too long
      "with space",
      "with/slash",           # path separator
      "-leading-dash",        # may not start with -
      "_leading_underscore",  # may not start with _
      "with.dot",
      "with:colon",
      "中文名稱",           # non-ASCII
      ""
    ].each do |name|
      channel = Channel.new(name: name, password: DEFAULT_PASSWORD)

      assert_not channel.valid?, "#{name.inspect} should not be valid"
      assert_predicate channel.errors[:name], :any?
    end
  end

  test "a well-formed name is accepted" do
    [ "ab", "lab1", "a" * 32, "a-b_c9", "0abc" ].each do |name|
      channel = Channel.new(name: name, password: DEFAULT_PASSWORD)

      assert channel.valid?, "#{name.inspect} should be valid, got #{channel.errors.full_messages}"
    end
  end

  test "a duplicate name is rejected" do
    create_channel("lab1")
    duplicate = Channel.new(name: "lab1", password: DEFAULT_PASSWORD)

    assert_not duplicate.valid?
  end

  test "a password shorter than 8 characters is rejected" do
    channel = Channel.new(name: "lab1", password: "1234567")

    assert_not channel.valid?
    assert_predicate channel.errors[:password], :any?
  end

  test "a password of exactly 8 characters is accepted" do
    channel = Channel.new(name: "lab1", password: "12345678")

    assert_predicate channel, :valid?
  end

  test "a channel without a password is rejected" do
    channel = Channel.new(name: "lab1")

    assert_not channel.valid?
  end

  test "authenticate returns the channel for the right password and false otherwise" do
    channel = create_channel("lab1")

    assert_equal channel, channel.authenticate(DEFAULT_PASSWORD)
    assert_not channel.authenticate("wrong-password")
    assert_not channel.authenticate("")
  end

  test "an api token verifies back to the channel that minted it" do
    channel = create_channel("lab1")

    assert_equal channel, Channel.from_api_token(channel.api_token(Channel::API_UPLOAD), Channel::API_UPLOAD)
  end

  test "an api token only verifies for the direction it was minted for" do
    channel = create_channel("lab1")

    assert_nil Channel.from_api_token(channel.api_token(Channel::API_UPLOAD), Channel::API_DOWNLOAD)
    assert_nil Channel.from_api_token(channel.api_token(Channel::API_DOWNLOAD), Channel::API_UPLOAD)
  end

  test "an api token stops verifying after its lifetime" do
    channel = create_channel("lab1")
    token = channel.api_token(Channel::API_DOWNLOAD)

    travel Channel.api_token_ttl - 10.seconds do
      assert_equal channel, Channel.from_api_token(token, Channel::API_DOWNLOAD)
    end

    travel Channel.api_token_ttl + 10.seconds do
      assert_nil Channel.from_api_token(token, Channel::API_DOWNLOAD)
    end
  end

  test "an api token is a usable URL path segment" do
    token = create_channel("lab1").api_token(Channel::API_UPLOAD)

    # The default Base64 alphabet contains "/" and "+", which would be mangled
    # in a path. url_safe: true is what keeps this true.
    assert_match(/\A[\w\-]+\z/, token)
  end

  test "a token whose channel is gone verifies to nothing" do
    channel = create_channel("lab1")
    token = channel.api_token(Channel::API_UPLOAD)
    channel.destroy

    assert_nil Channel.from_api_token(token, Channel::API_UPLOAD)
  end

  test "junk is never mistaken for an api token" do
    [ "", "garbage", "a--b", nil ].each do |bad|
      assert_nil Channel.from_api_token(bad, Channel::API_UPLOAD), "#{bad.inspect} should not verify"
    end
  end

  test "destroying a channel destroys all of its items" do
    channel = create_channel("lab1")
    create_text_item(channel)
    create_file_item(channel)

    assert_equal 2, channel.items.count

    assert_difference "Item.count", -2 do
      channel.destroy
    end
  end
end
