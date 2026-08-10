class ChannelsController < ApplicationController
  include ChannelApiUrls

  before_action :require_channel!

  def show
    # Every user-facing query goes through `alive`; never rely on the cleanup job
    # having run yet.
    @items = current_channel.items.alive.with_attached_file.order(created_at: :desc)
    @api_urls = channel_api_urls(current_channel)
  end

  # What the page polls to rotate its URLs before the current ones expire.
  # Session-authenticated like every other HTML action -- being able to mint a
  # token requires already being signed in to the channel.
  def api_urls
    # The body is a credential. Nothing along the way gets to keep a copy.
    response.headers["Cache-Control"] = "no-store"
    render json: channel_api_urls(current_channel)
  end
end
