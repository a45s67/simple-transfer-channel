# 參考實作 — 未執行過,以 SPEC.md 為準
module Admin
  class SessionsController < ApplicationController
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to admin_root_path, alert: "嘗試次數過多,請稍後再試" }

    def new
      redirect_to admin_channels_path if admin?
    end

    def create
      if valid_credentials?
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

    def valid_credentials?
      user = ENV["ADMIN_USER"].to_s
      pass = ENV["ADMIN_PASSWORD"].to_s
      return false if user.empty? || pass.empty?

      # & 而非 &&:兩邊都要跑,避免短路造成時序差異
      secure_equal?(params[:user].to_s, user) & secure_equal?(params[:password].to_s, pass)
    end

    def secure_equal?(given, expected)
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        Digest::SHA256.digest(given), Digest::SHA256.digest(expected)
      )
    end
  end
end
