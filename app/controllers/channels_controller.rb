class ChannelsController < ApplicationController
  before_action :require_channel!

  def show
    # 所有面向使用者的查詢都經過 alive,不依賴清除 job 的即時性
    @items = current_channel.items.alive.with_attached_file.order(created_at: :desc)
  end
end
