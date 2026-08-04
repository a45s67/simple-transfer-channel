module Admin
  class ChannelsController < ApplicationController
    before_action :require_admin!

    def index
      load_channels
      @channel ||= Channel.new
    end

    def create
      @channel = Channel.new(channel_params)

      if @channel.save
        redirect_to admin_channels_path, notice: "已建立 channel #{@channel.name}"
      else
        load_channels
        flash.now[:alert] = @channel.errors.full_messages.to_sentence
        render :index, status: :unprocessable_content
      end
    end

    def destroy
      channel = Channel.find(params[:id])
      channel.destroy
      redirect_to admin_channels_path, notice: "已刪除 channel #{channel.name}"
    end

    private

    def load_channels
      @channels = Channel.order(:name)
      # 面向使用者的計數也走 alive,避免顯示已過期但還沒被清掉的項目
      @item_counts = Item.alive.group(:channel_id).count
    end

    def channel_params
      params.expect(channel: [ :name, :password ])
    end
  end
end
