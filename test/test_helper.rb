ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "turbo/broadcastable/test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # 同步版的 broadcast_prepend_to / broadcast_remove_to 可以直接斷言
    include Turbo::Broadcastable::TestHelper

    DEFAULT_PASSWORD = "password123".freeze

    def create_channel(name, password: DEFAULT_PASSWORD)
      Channel.create!(name: name, password: password)
    end

    def create_blob(content: "hello", filename: "hello.txt", content_type: "text/plain")
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content), filename: filename, content_type: content_type
      )
    end

    def create_file_item(channel, expires_at: nil, **blob_options)
      item = channel.items.new(kind: "file", expires_at: expires_at)
      item.file.attach(create_blob(**blob_options))
      item.save!
      item
    end

    def create_text_item(channel, body: "hi", expires_at: nil)
      channel.items.create!(kind: "text", body: body, expires_at: expires_at)
    end

    # ENV 在呼叫當下才被讀,所以測試可以就地覆蓋
    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end
end

class ActionDispatch::IntegrationTest
  # GOTCHAS.md 第 6 條 / reference/test/README:rate_limit 用 IP 當 key,
  # 測試之間會互相累積。每個測試前後都清掉。
  setup { Rails.cache.clear }
  teardown { Rails.cache.clear }

  ADMIN_USER = "admin".freeze
  ADMIN_PASSWORD = "admin-password".freeze

  def login_channel(channel, password: DEFAULT_PASSWORD)
    post login_path, params: { name: channel.name, password: password }
  end

  def with_admin_env(user: ADMIN_USER, password: ADMIN_PASSWORD, &block)
    with_env("ADMIN_USER" => user, "ADMIN_PASSWORD" => password, &block)
  end

  def login_admin(user: ADMIN_USER, password: ADMIN_PASSWORD)
    with_admin_env { post admin_login_path, params: { user: user, password: password } }
  end
end
