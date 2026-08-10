require "test_helper"

# The curl API. The token in the URL is the whole credential: it is signed, it
# carries the channel and the direction, and it stops verifying five minutes
# after it was minted.
class ApiTest < ActionDispatch::IntegrationTest
  setup { @channel = create_channel("lab1") }

  # --- upload ---------------------------------------------------------------

  test "PUT with a filename in the path creates a file item in the channel" do
    assert_difference "Item.count", 1 do
      api_upload(@channel, "report.zip", "zip bytes")
    end

    assert_response :created
    item = @channel.items.sole

    assert_predicate item, :file?
    assert_equal "report.zip", item.file.filename.to_s
    assert_equal "zip bytes", item.file.download
    assert_in_delta Item.default_expires_at, item.expires_at, 5
  end

  test "the response body is a download command's worth of URL for the item just uploaded" do
    api_upload(@channel, "report.zip", "zip bytes")
    item = @channel.items.sole

    assert_match %r{\Ahttp://www\.example\.com/api/c/lab1/d/[\w\-]+/#{item.id}/report\.zip\n\z}, response.body

    get response.body.strip

    assert_response :success
    assert_equal "zip bytes", response.body
  end

  test "a binary body survives byte for byte" do
    content = (0..255).map(&:chr).join.b * 40

    api_upload(@channel, "bytes.bin", content)

    assert_response :created
    assert_equal content, @channel.items.sole.file.download.b
  end

  test "the Content-Type sent at upload time is never stored" do
    put api_upload_path(@channel, "evil.html"), params: "<script>alert(1)</script>",
        headers: { "CONTENT_TYPE" => "text/html" }

    assert_response :created
    assert_equal "application/octet-stream", @channel.items.sole.file.blob.content_type
  end

  test "a filename with path separators is reduced to its basename" do
    api_upload(@channel, ERB::Util.url_encode("../../etc/passwd"), "pwned")

    assert_response :created
    assert_equal "passwd", @channel.items.sole.file.filename.to_s
  end

  test "leaving the trailing slash off says so instead of 404ing" do
    assert_no_difference "Item.count" do
      put api_upload_path(@channel).chomp("/"), params: "x", headers: OCTET_STREAM
    end

    assert_response :unprocessable_content
    assert_match "ends in a slash", response.body
  end

  test "an empty file is rejected the same way it is in the browser" do
    assert_no_difference "Item.count" do
      api_upload(@channel, "empty.bin", "")
    end

    assert_response :unprocessable_content
    assert_match "empty", response.body
  end

  test "a body larger than the limit is refused before it is stored" do
    with_env("MAX_UPLOAD_MB" => "1") do
      assert_no_difference "Item.count" do
        api_upload(@channel, "big.bin", "x" * 2.megabytes)
      end
    end

    assert_response :content_too_large
    assert_equal 0, ActiveStorage::Blob.count
  end

  # --- download -------------------------------------------------------------

  test "GET returns the file" do
    item = create_file_item(@channel, content: "contents", filename: "notes.txt")

    get api_download_path(@channel, item)

    assert_response :success
    assert_equal "contents", response.body
  end

  test "the filename in the URL is decorative -- the id selects the item" do
    item = create_file_item(@channel, content: "contents", filename: "notes.txt")

    get "/api/c/lab1/d/#{@channel.api_token(Channel::API_DOWNLOAD)}/#{item.id}/anything-at-all.txt"

    assert_response :success
    assert_match "notes.txt", response.headers["Content-Disposition"]
  end

  test "an expired item is not downloadable" do
    item = create_file_item(@channel, expires_at: 1.hour.ago)

    get api_download_path(@channel, item)

    assert_response :not_found
  end

  test "a text item's id is not downloadable" do
    item = create_text_item(@channel)

    get api_download_path(@channel, item)

    assert_response :not_found
  end

  test "an unknown id returns 404" do
    token = @channel.api_token(Channel::API_DOWNLOAD)

    get "/api/c/lab1/d/#{token}/999999/x.bin"

    assert_response :not_found
  end

  # --- the token ------------------------------------------------------------

  test "a token stops working once its five minutes are up" do
    item = create_file_item(@channel)
    path = api_download_path(@channel, item)

    get path

    assert_response :success

    travel Channel.api_token_ttl + 1.minute do
      get path

      assert_response :unauthorized
      assert_match "expired", response.body
    end
  end

  test "the lifetime is configurable" do
    with_env("API_TOKEN_TTL_MINUTES" => "60") do
      item = create_file_item(@channel)
      path = api_download_path(@channel, item)

      travel 30.minutes do
        get path

        assert_response :success
      end
    end
  end

  test "a tampered token is refused" do
    item = create_file_item(@channel)
    token = @channel.api_token(Channel::API_DOWNLOAD)

    [ token.succ, token.reverse, token.split("--").first, "--#{token}", "garbage" ].each do |bad|
      get "/api/c/lab1/d/#{bad}/#{item.id}/x.bin"

      assert_response :unauthorized, "#{bad.inspect} should not verify"
    end

    # An empty token isn't a token, it's a different URL, and there is no route
    # to a channel's files that doesn't carry one.
    get "/api/c/lab1/d//#{item.id}/x.bin"

    assert_response :not_found
  end

  test "an upload token cannot download and a download token cannot upload" do
    item = create_file_item(@channel)

    get api_download_path(@channel, item, token: @channel.api_token(Channel::API_UPLOAD))

    assert_response :unauthorized

    assert_no_difference "Item.count" do
      api_upload(@channel, "x.bin", "x", token: @channel.api_token(Channel::API_DOWNLOAD))
    end

    assert_response :unauthorized
  end

  test "a token outlives nothing -- deleting the channel invalidates it immediately" do
    item = create_file_item(@channel)
    path = api_download_path(@channel, item)
    @channel.destroy

    get path

    assert_response :unauthorized
  end

  # Successful requests are deliberately not rate limited (a script pushing 200
  # files is normal), so the wall has to be on failures.
  test "failed attempts are rate limited" do
    20.times do |i|
      get "/api/c/lab1/d/garbage/1/x.bin"

      assert_response :unauthorized, "attempt #{i + 1} should not be limited yet"
    end

    get "/api/c/lab1/d/garbage/1/x.bin"

    assert_response :too_many_requests

    # And a good token is blocked too, exactly like the login limit does it
    item = create_file_item(@channel)

    get api_download_path(@channel, item)

    assert_response :too_many_requests
  end

  test "successful requests are not counted towards the limit" do
    item = create_file_item(@channel)

    30.times { get api_download_path(@channel, item) }

    assert_response :success
  end
end
