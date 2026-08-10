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

    # The synchronous broadcast_prepend_to / broadcast_remove_to can be asserted directly
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

    # ENV is read at call time, so tests can override it in place
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
  # rate_limit keys on IP, so counts accumulate across tests. Clear before and after.
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

  # The curl API's URLs are built by hand rather than by a route helper, for the
  # same reason the app builds them by hand: the trailing slash on an upload URL
  # is load-bearing (curl -T appends the filename to it).
  OCTET_STREAM = { "CONTENT_TYPE" => "application/octet-stream" }.freeze

  def api_upload_path(channel, filename = nil, token: channel.api_token(Channel::API_UPLOAD))
    "/api/c/#{channel.name}/u/#{token}/#{filename}"
  end

  def api_download_path(channel, item, token: channel.api_token(Channel::API_DOWNLOAD))
    name = item.file.attached? ? ERB::Util.url_encode(item.file.filename.sanitized.to_s) : "x"
    "/api/c/#{channel.name}/d/#{token}/#{item.id}/#{name}"
  end

  def api_upload(channel, filename, content, **options)
    put api_upload_path(channel, filename, **options), params: content, headers: OCTET_STREAM
  end
end
