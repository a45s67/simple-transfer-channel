# 參考實作 — 未執行過,以 SPEC.md 為準
module Admin
  class ChannelsController < ApplicationController
    before_action :require_admin!

    def index
      @channels = Channel.left_joins(:items).group(:id).select("channels.*, COUNT(items.id) AS items_count").order(:name)
      @channel = Channel.new
    end

    def create
      @channel = Channel.new(channel_params)

      if @channel.save
        redirect_to admin_channels_path, notice: "已建立 channel #{@channel.name}"
      else
        index
        flash.now[:alert] = @channel.errors.full_messages.to_sentence
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      channel = Channel.find(params[:id])
      channel.destroy
      redirect_to admin_channels_path, notice: "已刪除 channel #{channel.name}"
    end

    private

    def channel_params
      params.expect(channel: [ :name, :password ])
    end
  end
end
