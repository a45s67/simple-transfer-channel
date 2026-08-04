class ChannelsController < ApplicationController
  before_action :require_channel!

  def show
    # Every user-facing query goes through `alive`; never rely on the cleanup job
    # having run yet.
    @items = current_channel.items.alive.with_attached_file.order(created_at: :desc)
  end
end
