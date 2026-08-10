# The browser has already sent the file to /rails/active_storage/direct_uploads,
# so params[:signed_id] is what that step returned. File contents never pass
# through this action.
class ItemsController < ApplicationController
  include ItemDownloading

  before_action :require_channel!

  def create
    item = params[:signed_id].present? ? build_file_item : build_text_item

    if item.nil?
      render json: { error: "Nothing to save" }, status: :unprocessable_content
    elsif item.save
      head :created
    else
      render json: { error: item.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    render json: { error: "Invalid upload token" }, status: :unprocessable_content
  end

  def destroy
    # Invariant 3: start from current_channel, not Item.find
    item = current_channel.items.find_by(id: params[:id])
    return head :not_found unless item

    item.destroy
    head :no_content
  end

  # Invariant 1 is in ItemDownloading, shared with the curl API.
  def download
    item = current_channel.items.alive.find_by(id: params[:id], kind: "file")
    return head :not_found unless item&.file&.attached?

    send_item_file(item)
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
