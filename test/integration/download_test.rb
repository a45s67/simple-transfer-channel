require "test_helper"

# 🔒 Invariant 1: downloads are always attachment + application/octet-stream + nosniff.
# People move malware samples through this site; nothing may ever render inline.
#
# Two routes serve files -- the browser's and the curl API's -- and they share
# ItemDownloading. Every header assertion below runs against both, so the day
# they stop sharing it, this file fails.
class DownloadTest < ActionDispatch::IntegrationTest
  EVIL_HTML = "<script>alert(document.domain)</script>".freeze

  setup do
    @channel = create_channel("lab1")
    login_channel(@channel)
  end

  test "an .html file uploaded as text/html comes back as application/octet-stream" do
    item = upload(content: EVIL_HTML, filename: "evil.html", content_type: "text/html")

    each_download_of(item) do |route|
      assert_response :success, route
      assert_equal "application/octet-stream", response.media_type, route
      assert_match "attachment", response.headers["Content-Disposition"], route
      assert_equal "nosniff", response.headers["X-Content-Type-Options"], route
      assert_equal EVIL_HTML, response.body, route
    end
  end

  test "an .svg file uploaded as image/svg+xml behaves the same way" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    item = upload(content: svg, filename: "evil.svg", content_type: "image/svg+xml")

    each_download_of(item) do |route|
      assert_equal "application/octet-stream", response.media_type, route
      assert_match "attachment", response.headers["Content-Disposition"], route
      assert_equal "nosniff", response.headers["X-Content-Type-Options"], route
    end
  end

  test "no declared MIME type changes any of the three headers" do
    [
      "text/html", "image/svg+xml", "application/pdf", "image/png",
      "text/plain", "application/javascript", "text/xml"
    ].each do |declared|
      item = upload(content: "x", filename: "sample", content_type: declared)

      each_download_of(item) do |route|
        assert_equal "application/octet-stream", response.media_type, "#{route} broke when declared as #{declared}"
        assert_match "attachment", response.headers["Content-Disposition"], route
        assert_equal "nosniff", response.headers["X-Content-Type-Options"], route
      end
    end
  end

  test "the blob's content_type is never used as the response Content-Type" do
    item = upload(content: "x", filename: "evil.html", content_type: "text/html")

    assert_equal "text/html", item.file.blob.content_type, "the declared value stays on the blob"

    each_download_of(item) do |route|
      assert_equal "application/octet-stream", response.media_type, route
    end
  end

  test "a filename with CJK characters, spaces and emoji survives the round trip" do
    # Deliberately non-ASCII: this is the behaviour under test
    filename = "報告 v2 🎯.bin"
    item = upload(content: "x", filename: filename)

    each_download_of(item) do |route|
      assert_response :success, route
      disposition = response.headers["Content-Disposition"]

      assert_match "attachment", disposition, route
      # RFC 5987 filename* carries the raw UTF-8 name
      assert_match "filename*=UTF-8''#{ERB::Util.url_encode(filename)}", disposition, route
    end
  end

  test "a filename containing path separators cannot escape the storage root" do
    item = upload(content: "pwned", filename: "../../etc/passwd")

    blob = item.file.blob
    storage_root = Pathname.new(ActiveStorage::Blob.service.root).realpath
    stored = Pathname.new(ActiveStorage::Blob.service.path_for(blob.key))

    assert stored.exist?, "the file should exist"
    assert stored.realpath.to_s.start_with?(storage_root.to_s),
           "#{stored} landed outside the storage root"

    each_download_of(item) do |route|
      disposition = response.headers["Content-Disposition"]

      assert_no_match %r{\.\./}, disposition, route
      assert_no_match %r{etc/passwd}, disposition, route
      assert_equal "pwned", response.body, route
    end
  end

  test "an expired item cannot be downloaded" do
    item = upload(content: "x", filename: "old.bin")
    item.update!(expires_at: 1.hour.ago)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :not_found
  end

  test "a text item's id cannot be used to download" do
    item = create_text_item(@channel)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :not_found
  end

  test "an unknown id returns 404" do
    get download_channel_item_path(name: "lab1", id: 999_999)

    assert_response :not_found
  end

  private

  # Both ways out of a channel, so no assertion below can be true of only one.
  def each_download_of(item)
    { "browser download" => download_channel_item_path(name: "lab1", id: item.id),
      "curl API download" => api_download_path(@channel, item) }.each do |route, path|
      get path
      yield route
    end
  end

  # Goes through the real items#create, exactly as the browser does after a
  # direct upload.
  def upload(content:, filename:, content_type: "application/octet-stream")
    blob = create_blob(content: content, filename: filename, content_type: content_type)
    post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }

    assert_response :created
    Item.find(blob.attachments.sole.record_id)
  end
end
