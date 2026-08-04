# Simple channel

自架的檔案中繼站。Admin 建立具名 channel(名稱 + 密碼),任何知道名稱與密碼的
裝置都能進入同一個 channel,丟檔案和文字進去,別的裝置再來拿。

跟「產生分享連結」的工具不同:channel 是持久的、可重複進入的空間,
上傳者和下載者不需要同時在線。

Rails 8 單體 · SQLite · Solid Queue / Cache / Cable · ActiveStorage disk service ·
Turbo + Stimulus + importmap · 沒有 Node build step。

產品規格在 [`docs/SPEC.md`](docs/SPEC.md)。

---

## 跑起來

改 `docker-compose.yml`:

- `SECRET_KEY_BASE` 換成 `openssl rand -hex 64` 的輸出
- `ADMIN_USER` / `ADMIN_PASSWORD` 換掉

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

開 http://localhost:3000 → `/admin` 登入建 channel → 回首頁用 channel 名稱 + 密碼進入。

## 環境變數

| 變數 | 預設 | 說明 |
|---|---|---|
| `SECRET_KEY_BASE` | (必填) | `openssl rand -hex 64`。**不要每次重啟都換**,session 會全部失效 |
| `ADMIN_USER` | (空) | admin 帳號。與 `ADMIN_PASSWORD` 任一為空時,admin 登入一律失敗 |
| `ADMIN_PASSWORD` | (空) | admin 密碼 |
| `DEFAULT_TTL_DAYS` | `7` | 新項目幾天後過期。`0` = 永不過期 |
| `MAX_UPLOAD_MB` | `2048` | 單檔上限 |
| `FORCE_SSL` | `1` | `0` 時關閉強制 HTTPS 與 secure cookie |
| `SOLID_QUEUE_IN_PUMA` | (空) | 設 `1` 讓 Solid Queue 跑在 Puma 行程內 |
| `RAILS_MAX_THREADS` | `5` | direct upload 的 PUT 會佔住一條 thread 直到傳完 |
| `TZ` | `UTC` | 時區,同時決定畫面上的時間顯示 |

沒有 admin 資料表。admin 就是上面那組 ENV,用 SHA256 + 固定長度比對驗證。

**`FORCE_SSL`**:`config.force_ssl` 預設是開的,但這個 app 常見的部署是 LAN 或
Tailscale 上的純 HTTP,所以 compose 裡設成 `0`。放到公開網路前請設回 `1`,
並在前面擺一台終結 TLS 的 reverse proxy。`/up` 這個 health check 不受轉址影響。

## 資料放哪

SQLite 的四個資料庫(primary / cache / queue / cable)和 ActiveStorage 的 blob
全部在 `storage/` 底下,compose 用一個 named volume 掛在那裡。

**不要改成 bind mount。** 容器裡跑的是非 root 的 `rails` 使用者(UID 1000),
host 上的目錄是 root 所有,SQLite 會直接開不起來。備份:

```bash
docker compose cp app:/rails/storage ./backup-storage
```

`SECRET_KEY_BASE` 與 `config/master.key` 兩條路裡,這裡選前者。
master.key 沒有被使用,也不需要掛進容器。

## 過期清除

Solid Queue recurring job(`config/recurring.yml`),跑在 Puma 行程內
(`SOLID_QUEUE_IN_PUMA=1`,不開獨立容器):

- `CleanupExpiredItemsJob` — 每小時,刪掉 `expires_at <= now` 的項目。
  `dependent: :purge_later` 會讓 ActiveStorage 一併清掉 blob。
- `CleanupUnattachedBlobsJob` — 每小時,清掉超過 6 小時的孤兒 blob。
  direct upload 先建 blob 才 POST 給 `items#create`,中間關掉分頁、
  或驗證失敗(0 bytes / 超過上限)都會留下沒 attach 的 blob。

面向使用者的查詢一律經過 `Item.alive`,不依賴清除 job 的即時性。

---

## 安全上的三個不變量

這三項是這個 app 存在的前提,每一項都有對應的測試。
實作方式可以改,行為不能改 —— 不要在沒有補測試的情況下動它們。

### 1. 下載一律 `attachment` + `application/octet-stream` + `nosniff`

使用者會拿這個站傳惡意樣本。上傳一個 `.html` 或 `.svg`,下載時絕對不能被瀏覽器
inline 渲染。`items#download` 硬寫這三個 header,完全不看 blob 上宣告的 content type。

→ `app/controllers/items_controller.rb` · 測試 `test/integration/download_test.rb`

連帶做的兩件事:

- **ActiveStorage 自己的 blob 服務路由沒有被畫出來。**
  `config.active_storage.draw_routes = false`,只在 `config/routes.rb` 手動留下
  direct upload 需要的兩條。預設的 `/rails/active_storage/blobs/...` 只認 blob 的
  signed_id、完全不看 session,會同時繞過不變量 1 與不變量 3 ——
  而 signed_id 正是 direct upload 回傳給前端的東西。
- **`x_sendfile_header` 刻意不啟用**,否則檔案會由 Thruster 直接送出,
  上面三個 header 就不在我們手上。`send_file` 走 Rack 的 FileBody 分塊串流,
  幾 GB 的檔案也不會把整份讀進記憶體(`send_data` 會)。

### 2. 登入端點限流

channel 名稱是可枚舉的,沒有限流等於開放暴力破解。
`/login` 和 `/admin/login` 都是 `rate_limit to: 10, within: 3.minutes`(Rails 8 內建)。

→ `app/controllers/sessions_controller.rb`, `app/controllers/admin/sessions_controller.rb`
· 測試 `test/integration/rate_limit_test.rb`

`rate_limit` 依賴真的 cache store。**cache store 不對的話它會靜默失效 —— 不報錯,
就是不擋。** production 是 Solid Cache,test 環境必須是 `:memory_store`
(Rails 預設的 `:null_store` 會讓限流測試整批假綠)。

### 3. 跨 channel 不可存取

登入 channel A 的 session 不能讀寫、下載、刪除 channel B 的任何項目。
`current_channel` 同時檢查「channel 存在」和「id 在 `session[:channel_ids]` 裡」,
items 的每個 action 都從 `current_channel.items` 出發查詢 ——
**全專案沒有任何一處 `Item.find(params[:id])`**。

admin 授權與 channel 授權互相獨立:admin 只能建立/刪除 channel,
拿不到 channel 裡的內容。這是刻意的。

→ `app/controllers/application_controller.rb` · 測試 `test/integration/authorization_test.rb`

### 其他刻意的取捨

**不對上傳物做任何解析。** `config.active_storage.analyzers = []` /
`previewers = []` / `variant_processor = :disabled`,Gemfile 也拿掉了
`image_processing`(Dockerfile 連帶不裝 libvips)。使用者會傳惡意樣本進來,
image/video parser 是最常見的 RCE 面,而 SPEC 本來就排除預覽、縮圖與變體。

---

## 開發

Host 上不需要 Ruby,用容器跑就好:

```bash
docker run --rm -it -v "$PWD:/app" -w /app \
  -v simple-channel-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -e GEM_HOME=/bundle -e HOME=/tmp \
  -u "$(id -u):$(id -g)" ruby:3.4 bash

# 容器內
bundle install
bin/rails db:prepare
bin/rails test
bin/rubocop
bin/brakeman
```

bundle 放 named volume,repo 保持乾淨;`-u` 對齊 host uid,產出的檔案不會變成
root 所有。`bundle install` 需要 `build-essential` 和 `libyaml-dev`,
`ruby:3.4` 完整版已經有了。

`config/brakeman.ignore` 裡有一筆已說明的誤報(`items#download` 的 `send_file`)。
新增 ignore 一律要寫 `note` 說明為什麼可接受。

### 維護時容易踩到的地方

- **上傳進度只能從 delegate 拿。** `new DirectUpload(file, url, delegate)` 的第三個
  參數是 delegate,進度只有 `directUploadWillStoreFileWithXHR(xhr)` 這個 callback,
  沒有 `onProgress` 之類的東西。每個檔案各自建一個 delegate,五條進度列才不會互相蓋掉。
  → `app/javascript/controllers/dropzone_controller.js`
- **廣播用的 partial 沒有 controller context。** `broadcast_prepend_to` 在 model 層觸發,
  `items/_item.html.erb` 只能吃 `item` 這個 local,路徑要從 `item.channel.name` 推,
  不能碰 `current_channel`、`session`、或任何依賴請求狀態的 helper。
  用的是同步版 `broadcast_prepend_to`,不要為了別的原因換成 `_later`(測試會難斷言)。
- **`dependent: :purge_later` 需要 job queue 有在跑。** 測試環境的 queue adapter 是
  `:test`,不包 `perform_enqueued_jobs` 的話 blob 不會真的從磁碟消失,
  測試會假綠。→ `test/jobs/cleanup_expired_items_job_test.rb`
- **`app/models/channel.rb` 跟 `ApplicationCable::Channel` 是兩回事。**
  命名空間不同不會真的衝突,但不要搞混。`app/channels/` 底下的檔案保持原樣。
- **direct upload 不走 `items#create`。** 檔案內容先 PUT 到
  `/rails/active_storage/disk/...`,前端拿到 `blob.signed_id` 之後才 POST 給
  `items#create`。這個 action 只看得到 signed_id,看不到檔案內容。

### 測試涵蓋

```
test/models/channel_test.rb                     name 正規化、格式、密碼長度、authenticate
test/models/item_test.rb                        kind 驗證、alive scope、TTL、大小上限、廣播
test/integration/authorization_test.rb       🔒 不變量 3
test/integration/rate_limit_test.rb          🔒 不變量 2
test/integration/download_test.rb            🔒 不變量 1
test/integration/items_test.rb                  上傳/送文字/刪除、XSS、0 bytes、超過上限
test/integration/sessions_test.rb               登入登出、Turbo Stream 廣播
test/integration/admin_test.rb                  ENV 為空時失敗、建立/刪除 channel
test/jobs/cleanup_expired_items_job_test.rb     過期清除 + blob 真的從磁碟消失
test/jobs/cleanup_unattached_blobs_job_test.rb  孤兒 blob
```
