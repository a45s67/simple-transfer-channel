# 測試

VERIFY.md 列出了每一項必須涵蓋的行為。這裡只記幾個寫測試時的注意事項。

## 環境設定

`config/environments/test.rb` 要設:

```ruby
config.cache_store = :memory_store    # 不然 rate_limit 測試會靜默失效
config.active_job.queue_adapter = :test
config.active_storage.service = :test
```

## 限流測試會污染彼此

`rate_limit` 用 IP 當 key,測試之間會互相累積。每個限流測試前後清 cache:

```ruby
setup { Rails.cache.clear }
```

## Direct upload 在整合測試裡

不要真的走 direct upload 流程。直接建 blob 拿 signed_id:

```ruby
blob = ActiveStorage::Blob.create_and_upload!(
  io: StringIO.new("<script>alert(1)</script>"),
  filename: "evil.html",
  content_type: "text/html"
)

post channel_items_path(name: "test1"), params: { signed_id: blob.signed_id }
```

這也是驗證不變量 1 最直接的方式:content_type 明確宣告成 text/html,
下載回來必須是 application/octet-stream。

## Turbo Stream 廣播

同步版 `broadcast_prepend_to` 可以用 `assert_turbo_stream_broadcasts` 斷言,
或直接檢查 `Turbo::StreamsChannel` 收到的訊息。
不要為了測試把它改成 `_later`。
