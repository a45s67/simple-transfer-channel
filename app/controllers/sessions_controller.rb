# 不變量 2:channel 名稱是可枚舉的,登入端點必須限流。
# GOTCHAS.md 第 6 條:限流依賴真的 cache store,test 環境要用 :memory_store。
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to root_path, alert: "嘗試次數過多,請稍後再試" }

  def new
    @channels = authorized_channels
  end

  def create
    channel = Channel.by_name(params[:name])

    if channel&.authenticate(params[:password].to_s)
      session[:channel_ids] = (authorized_channel_ids + [ channel.id ]).uniq
      redirect_to channel_path(name: channel.name)
    else
      redirect_to root_path, alert: "channel 名稱或密碼錯誤"
    end
  end

  def destroy
    session[:channel_ids] = []
    redirect_to root_path, notice: "已登出所有 channel"
  end
end
