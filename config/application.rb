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

    # --- ActiveStorage hardening -----------------------------------------
    #
    # 1. Never parse an upload. People push malware samples through this site,
    #    and image/video parsers are the most common RCE surface there is.
    #    This app also has no previews, thumbnails or variants by design.
    config.active_storage.analyzers = []
    config.active_storage.previewers = []
    config.active_storage.variant_processor = :disabled

    # 2. Don't draw ActiveStorage's own blob-serving routes.
    #
    #    The default /rails/active_storage/blobs/... authenticates a blob's
    #    signed_id and ignores the session entirely, which bypasses invariant 3
    #    (no cross-channel access): hand someone any signed_id and they get the
    #    file, whichever channel they are signed in to. It also responds with
    #    the content_type recorded on the blob, bypassing invariant 1.
    #
    #    We keep only the two routes a direct upload needs (see config/routes.rb).
    #    Downloads always go through items#download, which queries from
    #    current_channel.
    config.active_storage.draw_routes = false
  end
end
