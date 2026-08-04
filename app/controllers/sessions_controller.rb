# Invariant 2: channel names are enumerable, so the login endpoint must be rate limited.
# Rate limiting needs a real cache store; the test env uses :memory_store -- see
# config/environments/test.rb.
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to root_path, alert: "Too many attempts, try again later" }

  def new
    @channels = authorized_channels
  end

  def create
    channel = Channel.by_name(params[:name])

    if channel&.authenticate(params[:password].to_s)
      session[:channel_ids] = (authorized_channel_ids + [ channel.id ]).uniq
      redirect_to channel_path(name: channel.name)
    else
      redirect_to root_path, alert: "Wrong channel name or password"
    end
  end

  def destroy
    session[:channel_ids] = []
    redirect_to root_path, notice: "Signed out of all channels"
  end
end
