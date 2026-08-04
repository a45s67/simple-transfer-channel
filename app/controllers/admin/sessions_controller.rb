module Admin
  # 不變量 2:admin 登入端點同樣要限流。
  class SessionsController < ApplicationController
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to admin_root_path, alert: "嘗試次數過多,請稍後再試" }

    def new
      redirect_to admin_channels_path if admin?
    end

    def create
      if valid_credentials?
        reset_session_preserving_channels
        session[:admin] = true
        redirect_to admin_channels_path
      else
        redirect_to admin_root_path, alert: "帳號或密碼錯誤"
      end
    end

    def destroy
      session[:admin] = false
      redirect_to admin_root_path, notice: "已登出"
    end

    private

    # 沒有 admin 表。ENV 一組,任一為空時一律登入失敗。
    def valid_credentials?
      user = ENV["ADMIN_USER"].to_s
      pass = ENV["ADMIN_PASSWORD"].to_s
      return false if user.empty? || pass.empty?

      # & 而非 &&:兩邊都要跑完,避免短路造成可觀察的時序差異
      secure_equal?(params[:user].to_s, user) & secure_equal?(params[:password].to_s, pass)
    end

    # 先 SHA256 再比對,讓兩邊長度固定,fixed_length_secure_compare 才成立
    def secure_equal?(given, expected)
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        Digest::SHA256.digest(given), Digest::SHA256.digest(expected)
      )
    end

    # 提權時換 session id 擋 session fixation,但保留已登入的 channel
    # (SPEC:admin 與 channel 授權互相獨立)
    def reset_session_preserving_channels
      channel_ids = session[:channel_ids]
      reset_session
      session[:channel_ids] = channel_ids
    end
  end
end
