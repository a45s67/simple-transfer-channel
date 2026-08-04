require "test_helper"

class ChannelTest < ActiveSupport::TestCase
  test "name 存入前正規化為小寫" do
    channel = create_channel("Lab1")

    assert_equal "lab1", channel.name
  end

  test "Lab1 和 lab1 視為同一個 channel" do
    create_channel("Lab1")
    duplicate = Channel.new(name: "lab1", password: DEFAULT_PASSWORD)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
    assert_equal 1, Channel.count
  end

  test "by_name 用正規化後的名稱查詢" do
    channel = create_channel("lab1")

    assert_equal channel, Channel.by_name("LAB1")
    assert_equal channel, Channel.by_name("  Lab1  ")
    assert_nil Channel.by_name("lab2")
  end

  test "name 格式不合會被拒絕" do
    # 大寫會先被正規化掉,所以這裡測的是正規化之後仍然不合法的形式
    [
      "a",                    # 太短
      "a" * 33,               # 太長
      "with space",           # 空白
      "with/slash",           # 路徑分隔符
      "-leading-dash",        # 不能以 - 開頭
      "_leading_underscore",  # 不能以 _ 開頭
      "with.dot",
      "with:colon",
      "中文名稱",
      ""
    ].each do |name|
      channel = Channel.new(name: name, password: DEFAULT_PASSWORD)

      assert_not channel.valid?, "#{name.inspect} 不應該通過驗證"
      assert_predicate channel.errors[:name], :any?
    end
  end

  test "合法的 name 會被接受" do
    [ "ab", "lab1", "a" * 32, "a-b_c9", "0abc" ].each do |name|
      channel = Channel.new(name: name, password: DEFAULT_PASSWORD)

      assert channel.valid?, "#{name.inspect} 應該通過驗證,錯誤:#{channel.errors.full_messages}"
    end
  end

  test "name 重複會被拒絕" do
    create_channel("lab1")
    duplicate = Channel.new(name: "lab1", password: DEFAULT_PASSWORD)

    assert_not duplicate.valid?
  end

  test "密碼少於 8 字元會被拒絕" do
    channel = Channel.new(name: "lab1", password: "1234567")

    assert_not channel.valid?
    assert_predicate channel.errors[:password], :any?
  end

  test "密碼剛好 8 字元可以" do
    channel = Channel.new(name: "lab1", password: "12345678")

    assert_predicate channel, :valid?
  end

  test "沒有密碼會被拒絕" do
    channel = Channel.new(name: "lab1")

    assert_not channel.valid?
  end

  test "authenticate 對正確密碼回傳 channel,錯誤密碼回傳 false" do
    channel = create_channel("lab1")

    assert_equal channel, channel.authenticate(DEFAULT_PASSWORD)
    assert_not channel.authenticate("wrong-password")
    assert_not channel.authenticate("")
  end

  test "刪除 channel 會連帶刪除底下所有 items" do
    channel = create_channel("lab1")
    create_text_item(channel)
    create_file_item(channel)

    assert_equal 2, channel.items.count

    assert_difference "Item.count", -2 do
      channel.destroy
    end
  end
end
