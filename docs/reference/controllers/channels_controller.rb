# 參考實作 — 未執行過,以 SPEC.md 為準
class ChannelsController < ApplicationController
  before_action :require_channel!

  def show
    @items = current_channel.items.alive.with_attached_file.order(created_at: :desc)
  end
end
