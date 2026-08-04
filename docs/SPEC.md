# Simple channel — 規格

## 一句話

一個自架的檔案中繼站。Admin 建立具名 channel(名稱 + 密碼),
任何知道名稱與密碼的裝置都能進入同一個 channel,丟檔案和文字進去,別的裝置再來拿。

跟「產生分享連結」的工具不同:channel 是持久的、可重複進入的空間,
上傳者和下載者不需要同時在線。

## 使用情境

Yu 有多台機器(Mac、Windows 分析 VM、homelab 上的 Linux),
分屬不同網段,常常需要在它們之間丟檔案。有些是惡意樣本。
現有工具要嘛是 P2P 需要兩端同時在線,要嘛是 link-based 沒有「空間」的概念。

## 資料模型

### channels

| 欄位 | 型別 | 說明 |
|---|---|---|
| `name` | string, not null, unique index | 小寫英數 + `-` + `_`,2–32 字元,存入前正規化為小寫 |
| `password_digest` | string, not null | `has_secure_password`,密碼至少 8 字元 |

`has_many :items, dependent: :destroy`

### items

| 欄位 | 型別 | 說明 |
|---|---|---|
| `channel_id` | references, not null, fk | |
| `kind` | string, not null | `file` 或 `text` |
| `body` | text | 只有 `kind == "text"` 時有值 |
| `expires_at` | datetime, nullable, index | null 表示永不過期 |

`belongs_to :channel`,`has_one_attached :file`

驗證:`kind == "text"` 時 `body` 必填;`kind == "file"` 時 `file` 必須 attached。

`scope :alive` — `expires_at IS NULL OR expires_at > now`。
**所有面向使用者的查詢都要經過 `alive`**,不要依賴清除 job 的即時性。

`expires_at` 預設 `ENV["DEFAULT_TTL_DAYS"]`(預設 7)天後,設 `0` 表示不過期。

### 不要建 admin 表

admin 是 `ENV["ADMIN_USER"]` / `ENV["ADMIN_PASSWORD"]` 一組,用
`ActiveSupport::SecurityUtils.fixed_length_secure_compare` 比對 SHA256 後的值。
兩個 ENV 任一為空時,admin 登入一律失敗。

## 路由

```
GET    /                          sessions#new         登入選擇頁
POST   /login                     sessions#create      channel 登入
DELETE /logout                    sessions#destroy     登出全部 channel

GET    /c/:name                   channels#show        channel 時間軸
POST   /c/:name/items             items#create         上傳檔案或送出文字
DELETE /c/:name/items/:id         items#destroy
GET    /c/:name/items/:id/download items#download

GET    /admin                     admin/sessions#new
POST   /admin/login               admin/sessions#create
DELETE /admin/logout              admin/sessions#destroy
GET    /admin/channels            admin/channels#index   列表 + 新增表單
POST   /admin/channels            admin/channels#create
DELETE /admin/channels/:id        admin/channels#destroy
```

`:name` 加 route constraint:`/[a-z0-9][a-z0-9_\-]{1,31}/`

## 授權模型

- channel 授權存在 session:`session[:channel_ids]` 是一個陣列,
  一個瀏覽器可以同時登入多個 channel
- admin 授權存在 `session[:admin]`
- 兩者互相獨立。admin 不會自動獲得 channel 內容的存取權(admin 只能建立/刪除 channel,
  不能瀏覽 channel 裡的東西)。這是刻意的
- `current_channel` 的實作必須同時檢查「channel 存在」和「id 在 session 陣列裡」

## UI

三個頁面就夠。

**登入頁 `/`** — 已登入的 channel 清單(如果有)、channel 登入表單、前往 admin 的連結。

**Channel 頁 `/c/:name`** — 由上而下:
- 拖曳區。支援拖拉檔案、點擊選檔、以及全頁面 `paste` 事件(貼上檔案或截圖)
- 上傳進度列(每個檔案一條,顯示百分比)
- 文字輸入框 + 送出按鈕,Ctrl/Cmd+Enter 也送出
- 項目時間軸,新的在上面。檔案項目顯示檔名、大小、時間、下載鍵;
  文字項目顯示內容、時間、複製鍵。每項都有刪除鍵

新項目要透過 Turbo Stream 即時出現在同 channel 的其他裝置上,不要用輪詢。

**Admin 頁 `/admin/channels`** — channel 列表(名稱、項目數、刪除鍵)+ 新增表單。
刪除要有確認。

視覺不用花俏,但要能在深色模式下看。

## 過期清除

Solid Queue recurring job,每小時跑一次,刪除 `expires_at <= now` 的項目。
`dependent: :purge_later` 讓 ActiveStorage 一併清掉 blob。

Solid Queue 跑在 Puma 行程內(`SOLID_QUEUE_IN_PUMA=1`),不開獨立容器。

## 不做

明確排除,不要自作主張加進來:

- E2EE
- WebDAV / SFTP / S3 相容介面
- 權限分級(唯讀 channel、drop-only inbox)
- 多個 admin 帳號、admin 表
- 檔案預覽、縮圖、變體
- 搜尋
- PWA / app 版
- 註冊流程、使用者表

## 技術選擇

Rails 8 單體,SQLite,Solid Queue / Solid Cache / Solid Cable,
ActiveStorage disk service,Turbo + Stimulus + importmap,Propshaft。
不要引入 Node build step、不要 Tailwind、不要前端框架。
