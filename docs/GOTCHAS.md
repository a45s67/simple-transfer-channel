# 已知會卡住的地方

先看完再動手。這幾個都是會浪費半小時以上的。

## 1. Rails 8 的 Dockerfile 跑非 root,bind mount 會權限爆炸

`rails new` 生的 Dockerfile 建了一個 `rails` 使用者(UID 1000)並 `chown` 了 `storage/`。
如果 compose 用 `./storage:/rails/storage` 這種 bind mount,
host 上的目錄是 root 所有,容器裡的 `rails` 使用者寫不進去,SQLite 直接開不起來。

用 named volume。備份用 `docker compose cp` 或臨時 mount 一個 busybox。

如果真的要 bind mount,在 compose 加 `user: "0:0"`,但那就失去非 root 的意義了。

## 2. SECRET_KEY_BASE 與 build 階段

Rails 8 的 Dockerfile 在 build 時跑 `SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile`,
build 階段沒問題。但 runtime 需要真的 key。

兩條路:compose 裡設 `SECRET_KEY_BASE`,或掛 `config/master.key`。
前者簡單,後者符合 Rails 慣例。選一個,寫進 README。

不要讓它每次重啟都變 — session 會全部失效。

## 3. 下載必須強制 octet-stream,ActiveStorage 預設不會

這是 CLAUDE.md 裡的不變量 1。`rails_blob_path` 預設會用 blob 記錄的 content_type,
上傳一個 `.html` 就可能被 inline 渲染,變成 stored XSS。

幾種做法,自己選一個並寫測試證明:

- 自訂 `items#download`,`send_data`/`send_file` 時硬寫 `type: "application/octet-stream"`
- `config.active_storage.content_types_to_serve_as_binary` 塞進所有型別
- 上傳時就把 blob 的 `content_type` 覆寫成 `application/octet-stream`,
  原始宣告值另存欄位供顯示

第一種最直觀也最好測。另外記得補 `X-Content-Type-Options: nosniff`。

## 4. DirectUpload 的進度事件要靠 delegate

`new DirectUpload(file, url, this)` 的第三個參數是 delegate。
進度只能透過 `directUploadWillStoreFileWithXHR(xhr)` 這個 callback 拿到:

```js
directUploadWillStoreFileWithXHR(xhr) {
  xhr.upload.addEventListener("progress", (e) => {
    // e.loaded / e.total
  })
}
```

沒有其他方式。如果你在 Stimulus controller 上直接找 `onProgress` 之類的會找不到。

direct upload 的端點是 `/rails/active_storage/direct_uploads`,
成功後回傳的 `blob.signed_id` 才是要 POST 給 `items#create` 的東西。

## 5. Turbo Stream 廣播的 partial 要能獨立渲染

`broadcast_prepend_to` 是在 model 層觸發的,渲染 partial 時**沒有 controller context**,
所以 partial 裡不能用 `current_channel`、`session`、或任何 helper 依賴的請求狀態。

partial 只能吃 `item` 這個 local,路徑要從 `item.channel.name` 推。

另外 `broadcast_prepend_later_to`(走 ActiveJob)在測試裡比較難斷言。
先用同步版 `broadcast_prepend_to`,測試綠了再考慮換。

## 6. rate_limit 需要一個真的 cache store

Rails 8 的 `rate_limit` 預設用 `Rails.cache`。如果 `config.action_controller.perform_caching`
是 false 或 cache store 是 `:null_store`,限流會靜默失效 —— 不報錯,就是不擋。

production 用 Solid Cache(`rails new` 預設就是),test 環境要記得設成 `:memory_store`,
不然限流的測試會過不了。

## 7. `dependent: :purge_later` 需要 job queue 有在跑

Item 刪除時 blob 的清除是排進 ActiveJob 的。如果測試環境的 queue adapter 是 `:test`,
blob 不會真的被刪,檔案留在磁碟上。

測試裡要驗證清除的話用 `perform_enqueued_jobs`。

## 8. Channel model 名稱

`Channel` 這個常數在載入 ActionCable 的 app 裡會有點微妙(`ActionCable::Channel`),
實務上因為命名空間不同不會真的衝突,但如果你在 `app/channels/` 底下看到 Rails 生的
`ApplicationCable::Channel`,不要把它跟 `app/models/channel.rb` 搞混。

我們用 Solid Cable,`app/channels/` 那些檔案保持原樣不要動。
