# 參考實作 — 未執行過,以 SPEC.md 為準
#
# 不變量 2:限流。GOTCHAS.md 第 6 條說明 cache store 的坑。
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to root_path, alert: "嘗試次數過多,請稍後再試" }

  def new
    @channels = authorized_channels
  end

  def create
    channel = Channel.find_by(name: params[:name].to_s.strip.downcase)

    if channel&.authenticate(params[:password].to_s)
      session[:channel_ids] = (authorized_channel_ids + [channel.id]).uniq
      redirect_to channel_path(name: channel.name)
    else
      redirect_to root_path, alert: "channel 名稱或密碼錯誤"
    end
  end

  def destroy
    session[:channel_ids] = []
    redirect_to root_path, notice: "已登出"
  end
end
