module Admin
  # Invariant 2: the admin login endpoint is rate limited too.
  class SessionsController < ApplicationController
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to admin_root_path, alert: "Too many attempts, try again later" }

    def new
      redirect_to admin_channels_path if admin?
    end

    def create
      if valid_credentials?
        reset_session_preserving_channels
        session[:admin] = true
        redirect_to admin_channels_path
      else
        redirect_to admin_root_path, alert: "Wrong username or password"
      end
    end

    def destroy
      session[:admin] = false
      redirect_to admin_root_path, notice: "Signed out"
    end

    private

    # There is no admin table. It's one pair of ENV vars, and if either is blank
    # every login attempt fails.
    def valid_credentials?
      user = ENV["ADMIN_USER"].to_s
      pass = ENV["ADMIN_PASSWORD"].to_s
      return false if user.empty? || pass.empty?

      # `&` rather than `&&`: both sides must run, so short-circuiting can't
      # produce an observable timing difference.
      secure_equal?(params[:user].to_s, user) & secure_equal?(params[:password].to_s, pass)
    end

    # Hash first so both sides are a fixed length, which is what
    # fixed_length_secure_compare requires.
    def secure_equal?(given, expected)
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        Digest::SHA256.digest(given), Digest::SHA256.digest(expected)
      )
    end

    # Rotate the session id on privilege escalation to block session fixation,
    # but keep the channels already signed in (admin and channel authorization
    # are independent -- see invariant 3 in the README).
    def reset_session_preserving_channels
      channel_ids = session[:channel_ids]
      reset_session
      session[:channel_ids] = channel_ids
    end
  end
end
