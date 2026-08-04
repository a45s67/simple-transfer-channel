# Simple channel — 給 Claude Code 的交接說明

## 你的任務

把這份規格實作成一個能跑的 Rails 8 應用,並用測試驗證到全綠。

這個目錄**不是**一個 Rails 專案。它是規格 + 參考實作片段。你要先跑 `rails new` 生出骨架,
再把 `reference/` 底下的東西適配進去。

## 為什麼是這種形式

規格是在一個沒有 Ruby 環境的地方寫的,所以裡面每一行 Ruby 都**沒有執行過**。
`reference/` 的定位是「設計意圖的載體」,不是可以直接 copy 的成品。
遇到跑不起來的地方,以 SPEC.md 的意圖為準,程式碼自己改。

## 工作順序

1. 讀 `SPEC.md`(產品規格與資料模型)
2. 讀 `BOOTSTRAP.md`,照著跑 `rails new` 和後續設定
3. 讀 `GOTCHAS.md` — 這裡有八個已知會卡住的地方,先看過再動手,可以省很多時間
4. 依 SPEC.md 實作,參考 `reference/` 的片段
5. 寫測試,以 `VERIFY.md` 的驗收條件為準
6. `docker compose build && docker compose up -d`,手動走一遍 VERIFY.md 的流程

## 不可妥協的三件事

這三個是安全不變量,實作方式你可以改,行為不能改。每一項都必須有對應的測試。

1. **下載一律 `Content-Disposition: attachment` 且 `Content-Type: application/octet-stream`。**
   使用者會拿這個站傳惡意樣本。上傳一個 `.html` 或 `.svg` 檔,下載時絕對不能被瀏覽器 inline 渲染。
   不要信任上傳時宣告的 MIME type。

2. **channel 登入端點必須限流。** channel 名稱是可枚舉的,沒有限流等於開放暴力破解。
   用 Rails 8 內建的 `rate_limit`。

3. **跨 channel 不可存取。** 登入 channel A 的 session 不能讀寫、下載、刪除 channel B 的任何項目。
   每一個 items 的 action 都必須從 `current_channel` 出發查詢,不能用 `Item.find(params[:id])`。

## 風格

- 中文註解和 commit message 沒問題,程式碼識別字用英文
- 不要加沒被要求的功能。這是 MVP,範圍在 SPEC.md 的「不做」那節寫死了
- rubocop-rails-omakase 是 `rails new` 附的,保持綠燈
- brakeman 也是附的,跑一次,有 warning 要嘛修要嘛在 commit 裡說明為什麼可接受

## 完成的定義

- `bin/rails test` 全綠
- `bin/rubocop` 沒有 offense
- `bin/brakeman` 沒有未說明的 warning
- 在乾淨環境下 `docker compose build && docker compose up -d` 之後,
  VERIFY.md 的手動流程從頭到尾走得通
- `Gemfile.lock` 有被 commit
