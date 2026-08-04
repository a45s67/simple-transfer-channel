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

  # Invariant 3: always check BOTH that the channel exists AND that its id is in
  # the session array. Never use Item.find(params[:id]) in an items action.
  def current_channel
    return @current_channel if defined?(@current_channel)

    channel = Channel.by_name(params[:name])
    @current_channel = channel if channel && authorized_channel_ids.include?(channel.id)
  end
  helper_method :current_channel

  def require_channel!
    redirect_to root_path, alert: "Sign in to this channel first" unless current_channel
  end

  # Admin and channel authorization are independent -- being admin grants no
  # access to the contents of any channel.
  def admin?
    session[:admin] == true
  end
  helper_method :admin?

  def require_admin!
    redirect_to admin_root_path, alert: "Sign in first" unless admin?
  end
end
