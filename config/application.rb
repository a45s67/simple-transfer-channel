require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SimpleChannel
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.time_zone = ENV.fetch("TZ", "UTC")

    # --- ActiveStorage 的安全設定 ---------------------------------------
    #
    # 1. 不對上傳物做任何解析。使用者會傳惡意樣本進來,image/video parser
    #    是最常見的 RCE 面。SPEC 也明確排除預覽、縮圖、變體。
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.active_storage.variant_processor = :disabled

    # 2. 不畫 ActiveStorage 自己的 blob 服務路由。
    #
    #    預設的 /rails/active_storage/blobs/... 只認 blob 的 signed_id,
    #    完全不看 session,等於繞過不變量 3(跨 channel 不可存取)——
    #    拿到任何一個 signed_id 就能取得該檔案,不管你登入的是哪個 channel。
    #    它也用 blob 記錄的 content_type 回應,繞過不變量 1。
    #
    #    我們只手動保留 direct upload 需要的兩條路由(見 config/routes.rb),
    #    下載一律走 items#download,從 current_channel 出發查詢。
    config.active_storage.draw_routes = false
  end
end
