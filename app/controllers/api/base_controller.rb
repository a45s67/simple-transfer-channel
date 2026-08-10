module Api
  # Deliberately ActionController::API and not ApplicationController:
  #
  # - no RequestForgeryProtection. curl has no CSRF token. That is only safe
  #   because nothing below ever reads the session -- a browser cookie alone can
  #   never drive these endpoints, so there is no cookie-authenticated,
  #   CSRF-exempt hole to walk through. Keep it that way.
  # - no `allow_browser versions: :modern`, which exists to turn away old
  #   browsers and would be free to start turning away curl.
  #
  # Successful requests are not rate limited. Invariant 2 is about enumerable
  # credentials -- a channel name and a password someone can guess. The
  # credential here is a 256-bit HMAC that stops verifying after five minutes,
  # and a script pushing 200 files is a normal thing to do. Failures are counted
  # instead, so a probe still runs into a wall.
  class BaseController < ActionController::API
    include ChannelApiUrls

    MAX_AUTH_FAILURES = 20
    AUTH_FAILURE_WINDOW = 3.minutes

    before_action :authenticate_api_token!

    private

    attr_reader :current_channel

    # "u" or "d" -- a link handed out for downloading is not usable for
    # uploading, and the other way round.
    def api_token_action
      raise NotImplementedError
    end

    def authenticate_api_token!
      return too_many_failures if auth_failures.to_i >= MAX_AUTH_FAILURES

      channel = Channel.from_api_token(params[:token], api_token_action)

      # Invariant 3: the token decides which channel this is, and the name in
      # the path has to be that same channel. A token for A is never usable
      # under B's name, whatever the session says -- there is no session here.
      if channel && channel.name == Channel.normalize(params[:name])
        @current_channel = channel
      else
        record_auth_failure
        unauthorized
      end
    end

    def unauthorized
      render plain: "This link has expired or is not valid. Open the channel page and copy a fresh one.\n",
             status: :unauthorized
    end

    def too_many_failures
      render plain: "Too many failed attempts, try again later.\n", status: :too_many_requests
    end

    def auth_failures
      Rails.cache.read(auth_failure_key, raw: true)
    end

    def record_auth_failure
      Rails.cache.increment(auth_failure_key, 1, expires_in: AUTH_FAILURE_WINDOW)
    end

    def auth_failure_key
      "api-auth-fail:#{request.remote_ip}"
    end
  end
end
