# 參考實作 — 未執行過,以 SPEC.md 為準
#
# 前端已經透過 DirectUpload 把檔案送到 /rails/active_storage/direct_uploads,
# 這裡收到的 params[:signed_id] 是那一步回傳的。檔案不經過這個 action。
class ItemsController < ApplicationController
  before_action :require_channel!

  def create
    item = params[:signed_id].present? ? build_file_item : build_text_item

    if item.nil?
      render json: { error: "沒有內容" }, status: :unprocessable_entity
    elsif item.save
      head :created
    else
      render json: { error: item.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    # 不變量 3:從 current_channel 出發,不是 Item.find
    item = current_channel.items.find_by(id: params[:id])
    return head :not_found unless item

    item.destroy
    head :no_content
  end

  # 不變量 1:強制 octet-stream + attachment + nosniff。
  # GOTCHAS.md 第 3 條有其他做法,選一個並寫測試。
  def download
    item = current_channel.items.alive.find_by(id: params[:id], kind: "file")
    return head :not_found unless item&.file&.attached?

    response.headers["X-Content-Type-Options"] = "nosniff"

    send_data item.file.download,
              filename: item.file.filename.to_s,
              type: "application/octet-stream",
              disposition: "attachment"
  end

  private

  def build_text_item
    body = params[:body].to_s
    return nil if body.strip.empty?

    current_channel.items.new(kind: "text", body: body, expires_at: Item.default_expires_at)
  end

  def build_file_item
    item = current_channel.items.new(kind: "file", expires_at: Item.default_expires_at)
    item.file.attach(params[:signed_id])
    item
  end
end
