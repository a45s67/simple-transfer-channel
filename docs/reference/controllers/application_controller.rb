# 參考實作 — 未執行過,以 SPEC.md 為準
class ApplicationController < ActionController::Base
  private

  def authorized_channel_ids
    Array(session[:channel_ids])
  end

  def authorized_channels
    Channel.where(id: authorized_channel_ids).order(:name)
  end

  # 不變量 3:一定要同時檢查存在與授權。
  # 絕對不要在 items 的 action 裡用 Item.find(params[:id])。
  def current_channel
    return @current_channel if defined?(@current_channel)

    channel = Channel.find_by(name: params[:name].to_s.downcase)
    @current_channel = channel if channel && authorized_channel_ids.include?(channel.id)
  end
  helper_method :current_channel

  def require_channel!
    redirect_to root_path, alert: "請先登入該 channel" unless current_channel
  end

  def admin?
    session[:admin] == true
  end

  def require_admin!
    redirect_to admin_root_path unless admin?
  end
end
