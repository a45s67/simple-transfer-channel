# Simple channel

自架的檔案中繼站。Admin 建立具名 channel(名稱 + 密碼),任何知道名稱與密碼的
裝置都能進入同一個 channel,丟檔案和文字進去,別的裝置再來拿。

跟「產生分享連結」的工具不同:channel 是持久的、可重複進入的空間,
上傳者和下載者不需要同時在線。

規格在 `docs/`(SPEC / BOOTSTRAP / GOTCHAS / VERIFY)。

## 跑起來

```bash
# 改 docker-compose.yml:
#   SECRET_KEY_BASE 換成 `openssl rand -hex 64` 的輸出
#   ADMIN_USER / ADMIN_PASSWORD 換掉

docker compose build
docker compose up -d
docker compose logs -f
```

然後開 http://localhost:3000 → `/admin` 建 channel → 回首頁用 channel 名稱 + 密碼進入。

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

### SECRET_KEY_BASE vs master.key

GOTCHAS.md 第 2 條列了兩條路,**這裡選 `SECRET_KEY_BASE` 環境變數**。
`config/master.key` 沒有被使用,也不需要掛進容器。

### FORCE_SSL

`config.force_ssl` 預設是開的。這個 app 常見的部署是 LAN 或 Tailscale 上的純 HTTP,
所以 `docker-compose.yml` 裡設成 `FORCE_SSL=0`,`docker compose up` 之後才走得完
VERIFY.md 的手動流程。

**放到公開網路前請把它設回 `1`,並在前面擺一台終結 TLS 的 reverse proxy。**
`/up` 這個 health check 端點不受 HTTPS 轉址影響。

## 資料放哪

SQLite 的四個資料庫(primary / cache / queue / cable)和 ActiveStorage 的 blob
全部在 `storage/` 底下,compose 用一個 named volume 掛在那裡。

**不要改成 bind mount。** 容器裡跑的是非 root 的 `rails` 使用者(UID 1000),
host 上的目錄是 root 所有,SQLite 會直接開不起來(GOTCHAS.md 第 1 條)。備份:

```bash
docker compose cp app:/rails/storage ./backup-storage
```

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

bundle 放 named volume,repo 保持乾淨;`-u` 對齊 host uid,產出的檔案不會變成 root 所有。
（`bundle install` 需要 `build-essential` 和 `libyaml-dev`,ruby:3.4 完整版已經有了。）

## 安全上的三個不變量

這三項都有對應的測試,不要在沒有補測試的情況下改掉行為。

### 1. 下載一律 `attachment` + `application/octet-stream` + `nosniff`

`items#download` 硬寫這三個 header,完全不看 blob 上宣告的 content type。
上傳一個 `.html` 或 `.svg`,下載時不會被瀏覽器 inline 渲染。
測試:`test/integration/download_test.rb`。

連帶做的兩件事:

- **ActiveStorage 自己的 blob 服務路由沒有被畫出來。**
  `config.active_storage.draw_routes = false`,只在 `config/routes.rb` 手動留下
  direct upload 需要的兩條。預設的 `/rails/active_storage/blobs/...` 只認 blob 的
  signed_id、完全不看 session,會同時繞過不變量 1 與不變量 3。
- **`x_sendfile_header` 刻意不啟用**,否則檔案會由 Thruster 直接送出,
  上面三個 header 就不在我們手上。`send_file` 走 Rack 的 FileBody 分塊串流,
  幾 GB 的檔案也不會把整份讀進記憶體。

### 2. 登入端點限流

`/login` 和 `/admin/login` 都是 `rate_limit to: 10, within: 3.minutes`(Rails 8 內建)。
channel 名稱是可枚舉的,沒有限流等於開放暴力破解。
限流依賴真的 cache store —— production 是 Solid Cache,test 是 `:memory_store`
(`:null_store` 會讓限流靜默失效,GOTCHAS.md 第 6 條)。
測試:`test/integration/rate_limit_test.rb`。

### 3. 跨 channel 不可存取

`current_channel` 同時檢查「channel 存在」和「id 在 `session[:channel_ids]` 裡」,
每個 items 的 action 都從 `current_channel.items` 出發查詢,沒有任何一處用
`Item.find(params[:id])`。admin 授權與 channel 授權互相獨立:admin 只能建立/刪除
channel,拿不到 channel 裡的內容。測試:`test/integration/authorization_test.rb`。

### 其他刻意的取捨

- **不對上傳物做任何解析。** `config.active_storage.analyzers = []` /
  `previewers = []`,Gemfile 也拿掉了 `image_processing`(Dockerfile 連帶不裝 libvips)。
  使用者會傳惡意樣本進來,image/video parser 是最常見的 RCE 面,
  而 SPEC 本來就排除預覽、縮圖與變體。
- **孤兒 blob 有 job 會清。** direct upload 先建 blob 才 POST 給 `items#create`,
  中間關掉分頁、或驗證失敗(0 bytes / 超過上限)都會留下沒 attach 的 blob。
  `CleanupUnattachedBlobsJob` 每小時清掉超過 6 小時的孤兒。

## 過期清除

Solid Queue recurring job(`config/recurring.yml`),跑在 Puma 行程內
(`SOLID_QUEUE_IN_PUMA=1`,不開獨立容器):

- `CleanupExpiredItemsJob` — 每小時,刪掉 `expires_at <= now` 的項目。
  `dependent: :purge_later` 會讓 ActiveStorage 一併清掉 blob。
- `CleanupUnattachedBlobsJob` — 每小時,清掉孤兒 blob。

面向使用者的查詢一律經過 `Item.alive`,不依賴清除 job 的即時性。
