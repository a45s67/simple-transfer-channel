module Api
  # The curl half of the channel. Unlike the browser, which uploads straight to
  # ActiveStorage and then POSTs a signed_id, here the file contents do pass
  # through this action -- so nothing may read them into memory. `attach(io:)`
  # checksums and copies in chunks from Puma's rewindable request body.
  class ItemsController < BaseController
    include ItemDownloading

    TOKEN_ACTIONS = { "create" => Channel::API_UPLOAD, "show" => Channel::API_DOWNLOAD }.freeze

    def create
      filename = File.basename(params[:filename].to_s)
      return no_filename if filename.blank? || filename == "."
      return too_large if request.content_length.to_i > Item.max_upload_bytes

      item = current_channel.items.new(kind: "file", expires_at: Item.default_expires_at)
      # identify: false keeps Marcel from sniffing hostile bytes, and keeps the
      # stored type from being anything the uploader chose. Invariant 1 ignores
      # it on the way out either way.
      item.file.attach(io: request.body, filename: filename,
                       content_type: "application/octet-stream", identify: false)

      if item.save
        render plain: "#{channel_api_download_url(channel_api_urls(current_channel)[:download_base], item)}\n",
               status: :created
      else
        render plain: "#{item.errors.full_messages.to_sentence}\n", status: :unprocessable_content
      end
    end

    def show
      # Invariant 3: start from current_channel, not Item.find
      item = current_channel.items.alive.find_by(id: params[:id], kind: "file")
      return head :not_found unless item&.file&.attached?

      send_item_file(item)
    end

    private

    def api_token_action
      TOKEN_ACTIONS.fetch(action_name)
    end

    def no_filename
      render plain: "No filename. The upload URL ends in a slash: curl -T ./file.zip <url>/\n",
             status: :unprocessable_content
    end

    def too_large
      render plain: "File exceeds the #{ActiveSupport::NumberHelper.number_to_human_size(Item.max_upload_bytes)} limit\n",
             status: :content_too_large
    end
  end
end
