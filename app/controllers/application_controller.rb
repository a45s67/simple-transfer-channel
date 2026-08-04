class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def authorized_channel_ids
    Array(session[:channel_ids]).map(&:to_i)
  end

  def authorized_channels
    Channel.where(id: authorized_channel_ids).order(:name)
  end

  # 不變量 3:一定要同時檢查「channel 存在」與「id 在 session 陣列裡」。
  # 絕對不要在 items 的 action 裡用 Item.find(params[:id])。
  def current_channel
    return @current_channel if defined?(@current_channel)

    channel = Channel.by_name(params[:name])
    @current_channel = channel if channel && authorized_channel_ids.include?(channel.id)
  end
  helper_method :current_channel

  def require_channel!
    redirect_to root_path, alert: "請先登入該 channel" unless current_channel
  end

  # admin 與 channel 授權互相獨立 —— admin 不會因此取得任何 channel 的內容存取權。
  def admin?
    session[:admin] == true
  end
  helper_method :admin?

  def require_admin!
    redirect_to admin_root_path, alert: "請先登入" unless admin?
  end
end
