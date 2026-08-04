require "test_helper"

# 🔒 不變量 1:下載一律 attachment + application/octet-stream + nosniff。
# 使用者會拿這個站傳惡意樣本,絕對不能被瀏覽器 inline 渲染。
class DownloadTest < ActionDispatch::IntegrationTest
  EVIL_HTML = "<script>alert(document.domain)</script>".freeze

  setup do
    @channel = create_channel("lab1")
    login_channel(@channel)
  end

  test "上傳時宣告 text/html 的 .html 檔,下載時是 application/octet-stream" do
    item = upload(content: EVIL_HTML, filename: "evil.html", content_type: "text/html")

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal EVIL_HTML, response.body
  end

  test "上傳時宣告 image/svg+xml 的 .svg 檔也一樣" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    item = upload(content: svg, filename: "evil.svg", content_type: "image/svg+xml")

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_equal "application/octet-stream", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "上傳時宣告任何 MIME type 都不影響三個 header" do
    [
      "text/html", "image/svg+xml", "application/pdf", "image/png",
      "text/plain", "application/javascript", "text/xml"
    ].each do |declared|
      item = upload(content: "x", filename: "sample", content_type: declared)

      get download_channel_item_path(name: "lab1", id: item.id)

      assert_equal "application/octet-stream", response.media_type, "宣告 #{declared} 時失守"
      assert_match "attachment", response.headers["Content-Disposition"]
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    end
  end

  test "blob 的 content_type 不會被拿來當回應的 Content-Type" do
    item = upload(content: "x", filename: "evil.html", content_type: "text/html")

    assert_equal "text/html", item.file.blob.content_type, "blob 上宣告的值保持原樣"

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_equal "application/octet-stream", response.media_type
  end

  test "檔名含中文、空白、emoji 時下載檔名正確" do
    filename = "報告 v2 🎯.bin"
    item = upload(content: "x", filename: filename)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :success
    disposition = response.headers["Content-Disposition"]

    assert_match "attachment", disposition
    # RFC 5987 的 filename* 帶 UTF-8 原始檔名
    assert_match "filename*=UTF-8''#{ERB::Util.url_encode(filename)}", disposition
  end

  test "檔名含路徑分隔符時不會寫到預期目錄之外,下載檔名也不含路徑" do
    item = upload(content: "pwned", filename: "../../etc/passwd")

    blob = item.file.blob
    storage_root = Pathname.new(ActiveStorage::Blob.service.root).realpath
    stored = Pathname.new(ActiveStorage::Blob.service.path_for(blob.key))

    assert stored.exist?, "檔案應該存在"
    assert stored.realpath.to_s.start_with?(storage_root.to_s),
           "#{stored} 落在 storage 目錄之外"

    get download_channel_item_path(name: "lab1", id: item.id)

    disposition = response.headers["Content-Disposition"]

    assert_no_match %r{\.\./}, disposition
    assert_no_match %r{etc/passwd}, disposition
    assert_equal "pwned", response.body
  end

  test "已過期的項目不能下載" do
    item = upload(content: "x", filename: "old.bin")
    item.update!(expires_at: 1.hour.ago)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :not_found
  end

  test "文字項目的 id 不能拿來下載" do
    item = create_text_item(@channel)

    get download_channel_item_path(name: "lab1", id: item.id)

    assert_response :not_found
  end

  test "不存在的 id 得到 404" do
    get download_channel_item_path(name: "lab1", id: 999_999)

    assert_response :not_found
  end

  private

  # 走真正的 items#create,和瀏覽器 direct upload 之後做的事一樣
  def upload(content:, filename:, content_type: "application/octet-stream")
    blob = create_blob(content: content, filename: filename, content_type: content_type)
    post channel_items_path(name: "lab1"), params: { signed_id: blob.signed_id }

    assert_response :created
    Item.find(blob.attachments.sole.record_id)
  end
end
