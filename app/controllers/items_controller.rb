# 前端已經透過 DirectUpload 把檔案送到 /rails/active_storage/direct_uploads,
# 這裡收到的 params[:signed_id] 是那一步回傳的。檔案內容不經過這個 action。
class ItemsController < ApplicationController
  before_action :require_channel!

  def create
    item = params[:signed_id].present? ? build_file_item : build_text_item

    if item.nil?
      render json: { error: "沒有內容" }, status: :unprocessable_content
    elsif item.save
      head :created
    else
      render json: { error: item.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    render json: { error: "上傳憑證無效" }, status: :unprocessable_content
  end

  def destroy
    # 不變量 3:從 current_channel 出發,不是 Item.find
    item = current_channel.items.find_by(id: params[:id])
    return head :not_found unless item

    item.destroy
    head :no_content
  end

  # 不變量 1:一律 attachment + application/octet-stream + nosniff。
  # 不看 blob 記錄的 content_type —— 那是上傳端宣告的,不可信。
  #
  # 這裡用 send_file 而不是 send_data:send_data 會把整個檔案讀進記憶體,
  # 這個站的檔案動輒上 GB。send_file 走 Rack 的 FileBody,分塊串流。
  # x_sendfile_header 刻意不啟用,否則檔案會由 Thruster 直接送出,
  # 我們就無法保證上面三個 header。
  def download
    item = current_channel.items.alive.find_by(id: params[:id], kind: "file")
    return head :not_found unless item&.file&.attached?

    blob = item.file.blob
    response.headers["X-Content-Type-Options"] = "nosniff"

    send_file disk_path_for(blob),
              filename: blob.filename.sanitized,
              type: "application/octet-stream",
              disposition: "attachment"
  end

  private

  # blob.key 是 Rails 產生的隨機字串,不是使用者輸入 —— 檔名(可能含 ../)
  # 完全不參與磁碟路徑的組成。
  def disk_path_for(blob)
    ActiveStorage::Blob.service.path_for(blob.key)
  end

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
