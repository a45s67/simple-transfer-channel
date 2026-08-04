require "test_helper"

# 🔒 Invariant 1: downloads are always attachment + application/octet-stream + nosniff.
# People move malware samples through this site; nothing may ever render inline.
class DownloadTest < ActionDispatch::IntegrationTest
  EVIL_HTML = "<script>alert(document.domain)</script>".freeze

  setup do
    @channel = create_channel("lab1")
    login_channel(@channel)
  end

  test "an .html file uploaded as text/html comes back as application/octet-stream" do
    item = upload(content: EVIL_HTML, filename: "evil.html", content_type: "text/html")

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal EVIL_HTML, response.body
  end

  test "an .svg file uploaded as image/svg+xml behaves the same way" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    item = upload(content: svg, filename: "evil.svg", content_type: "image/svg+xml")

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_equal "application/octet-stream", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "no declared MIME type changes any of the three headers" do
    [
      "text/html", "image/svg+xml", "application/pdf", "image/png",
      "text/plain", "application/javascript", "text/xml"
    ].each do |declared|
      item = upload(content: "x", filename: "sample", content_type: declared)

      get download_channel_item_path(name: "lab1", id: item.id)

      assert_equal "application/octet-stream", response.media_type, "broke when declared as #{declared}"
      assert_match "attachment", response.headers["Content-Disposition"]
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    end
  end

  test "the blob's content_type is never used as the response Content-Type" do
    item = upload(content: "x", filename: "evil.html", content_type: "text/html")

    assert_equal "text/html", item.file.blob.content_type, "the declared value stays on the blob"

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_equal "application/octet-stream", response.media_type
  end

  test "a filename with CJK characters, spaces and emoji survives the round trip" do
    # Deliberately non-ASCII: this is the behaviour under test
    filename = "報告 v2 🎯.bin"
    item = upload(content: "x", filename: filename)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :success
    disposition = response.headers["Content-Disposition"]

    assert_match "attachment", disposition
    # RFC 5987 filename* carries the raw UTF-8 name
    assert_match "filename*=UTF-8''#{ERB::Util.url_encode(filename)}", disposition
  end

  test "a filename containing path separators cannot escape the storage root" do
    item = upload(content: "pwned", filename: "../../etc/passwd")

    blob = item.file.blob
    storage_root = Pathname.new(ActiveStorage::Blob.service.root).realpath
    stored = Pathname.new(ActiveStorage::Blob.service.path_for(blob.key))

    assert stored.exist?, "the file should exist"
    assert stored.realpath.to_s.start_with?(storage_root.to_s),
           "#{stored} landed outside the storage root"

    get download_channel_item_path(name: "lab1", id: item.id)

    disposition = response.headers["Content-Disposition"]

    assert_no_match %r{\.\./}, disposition
    assert_no_match %r{etc/passwd}, disposition
    assert_equal "pwned", response.body
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

  # Goes through the real items#create, exactly as the browser does after a
  # direct upload.
  def upload(content:, filename:, content_type: "application/octet-stream")
    blob = create_blob(content: content, filename: filename, content_type: content_type)
    post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }

    assert_response :created
    Item.find(blob.attachments.sole.record_id)
  end
end
