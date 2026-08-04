# Simple channel — 給 Claude Code 的專案說明

自架的檔案中繼站。Rails 8 單體,SQLite,ActiveStorage disk service,
Turbo + Stimulus + importmap,沒有 Node build step。

先讀 `README.md`(架構、環境變數、三個不變量),產品規格在 `docs/SPEC.md`,
部署方式在 `docs/DEPLOY.md`。

祕密(`SECRET_KEY_BASE` / `ADMIN_USER` / `ADMIN_PASSWORD`)只放 `.env`,
**不要寫回 `docker-compose.yml`**,那個檔案是進版控的。
新增環境變數時 `.env.example` 要跟著更新。

## 不可妥協的三件事

這三個是安全不變量,實作方式可以改,行為不能改。每一項都已經有對應的測試,
動到它們的時候測試必須跟著改,不能只是讓測試過。

1. **下載一律 `Content-Disposition: attachment` 且 `Content-Type: application/octet-stream`。**
   使用者會拿這個站傳惡意樣本。上傳一個 `.html` 或 `.svg`,下載時絕對不能被瀏覽器
   inline 渲染。不要信任上傳時宣告的 MIME type。
   → `items#download` · `test/integration/download_test.rb`

   附帶條件:`config.active_storage.draw_routes = false` 不要打開,
   `x_sendfile_header` 不要啟用。理由見 README 的「安全上的三個不變量」。

2. **channel 登入端點必須限流。** channel 名稱是可枚舉的,沒有限流等於開放暴力破解。
   用 Rails 8 內建的 `rate_limit`。test 環境的 `cache_store` 必須是 `:memory_store`,
   `:null_store` 會讓限流靜默失效、測試整批假綠。
   → `test/integration/rate_limit_test.rb`

3. **跨 channel 不可存取。** 登入 channel A 的 session 不能讀寫、下載、刪除
   channel B 的任何項目。每一個 items 的 action 都必須從 `current_channel` 出發查詢,
   不能用 `Item.find(params[:id])`。admin 授權與 channel 授權互相獨立。
   → `application_controller#current_channel` · `test/integration/authorization_test.rb`

## 範圍

MVP,`docs/SPEC.md` 的「不做」那節寫死了範圍。不要自作主張加功能 ——
特別是**檔案預覽、縮圖、變體**:那不只是範圍問題,還會讓 image parser
跑在惡意樣本上。ActiveStorage 的 analyzers / previewers 是刻意清空的。

## 風格

- 中文註解和 commit message 沒問題,程式碼識別字用英文
- rubocop-rails-omakase 保持綠燈
- brakeman 有 warning 要嘛修、要嘛在 commit 裡說明為什麼可接受

## 完成的定義

- `bin/rails test` 全綠
- `bin/rubocop` 沒有 offense
- `bin/brakeman` 沒有未說明的 warning
- 動到上傳/下載/即時同步的話,`docker compose build && docker compose up -d`
  之後用兩個瀏覽器實際走一遍(拖拉、貼上、進度列、跨裝置即時出現、下載)

## 開發環境

Host 上不一定有 Ruby。用容器跑,指令見 README 的「開發」那節。
