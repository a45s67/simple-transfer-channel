# Builds the copy-and-paste curl URLs for a channel.
#
# The paths are interpolated rather than taken from a route helper for one
# reason: the upload URL has to end in a slash. `curl -T ./report.zip <url>/`
# appends the filename itself, which is what makes a bare URL enough -- no
# -H, no form field, nothing to edit before pressing enter.
#
# Channel names match NAME_FORMAT, so nothing here needs escaping.
module ChannelApiUrls
  extend ActiveSupport::Concern

  private

  def channel_api_urls(channel)
    {
      upload_url: "#{request.base_url}/api/c/#{channel.name}/u/#{channel.api_token(Channel::API_UPLOAD)}/",
      download_base: "#{request.base_url}/api/c/#{channel.name}/d/#{channel.api_token(Channel::API_DOWNLOAD)}",
      ttl_seconds: Channel.api_token_ttl.to_i
    }
  end

  # The filename in a download URL is decorative -- it is there so that plain
  # `curl -O` writes the right name. The id is what selects the item, and
  # Content-Disposition still comes from the blob.
  def channel_api_download_url(download_base, item)
    "#{download_base}/#{item.id}/#{ERB::Util.url_encode(item.file.filename.sanitized.to_s)}"
  end
end
