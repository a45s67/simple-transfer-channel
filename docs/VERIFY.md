# 驗收條件

## 必須有的自動化測試

以下每一項都要有對應的測試。安全相關的(標 🔒)不能省。

### Channel model

- [ ] name 存入前正規化為小寫,`"Lab1"` 和 `"lab1"` 視為同一個
- [ ] name 格式不合(大寫、空白、`/`、太短、太長)會被拒絕
- [ ] name 重複會被拒絕
- [ ] 密碼少於 8 字元會被拒絕
- [ ] `authenticate` 對正確密碼回傳 channel、錯誤密碼回傳 false

### Item model

- [ ] `kind: "text"` 且 `body` 空白時無效
- [ ] `kind: "file"` 且沒有 attached file 時無效
- [ ] `alive` scope 排除 `expires_at` 已過的項目,包含 `expires_at` 為 nil 的項目
- [ ] `DEFAULT_TTL_DAYS=0` 時建立的項目 `expires_at` 為 nil
- [ ] 刪除 channel 會連帶刪除底下所有 items

### 授權 🔒

- [ ] 未登入時存取 `/c/foo` 會被導回首頁
- [ ] 登入 channel A 後,存取 `/c/b` 會被導回首頁(即使 b 存在)
- [ ] 登入 channel A 後,用 channel B 的 item id 呼叫 download 會得到 404,**不是** 200
- [ ] 登入 channel A 後,用 channel B 的 item id 呼叫 destroy 會得到 404,且該 item 仍存在
- [ ] admin 登入**不會**取得任何 channel 的內容存取權
- [ ] 同時登入兩個 channel 後,兩邊都能正常存取

### 限流 🔒

- [ ] 對 `/login` 連續送 11 次錯誤密碼,第 11 次得到限流回應而非「密碼錯誤」
- [ ] 對 `/admin/login` 同上

### 下載 🔒

- [ ] 上傳一個 `.html` 檔,下載的 response `Content-Type` 是 `application/octet-stream`
- [ ] 同上,`Content-Disposition` 包含 `attachment`
- [ ] 同上,`X-Content-Type-Options` 是 `nosniff`
- [ ] 上傳時宣告 `content_type: "text/html"` 不會影響上述三項

### Admin

- [ ] `ADMIN_USER` 或 `ADMIN_PASSWORD` 為空字串時,任何登入嘗試都失敗
- [ ] 正確帳密可登入,錯誤帳密不行
- [ ] 未登入 admin 時存取 `/admin/channels` 會被導向 admin 登入頁

### 過期清除

- [ ] cleanup job 會刪除 `expires_at` 已過的項目
- [ ] cleanup job 不會刪除 `expires_at` 為 nil 的項目
- [ ] 刪除後 ActiveStorage blob 也被清掉(記得 `perform_enqueued_jobs`)

## 手動走一遍

在 `docker compose up -d` 之後,用兩個不同的瀏覽器(或一個正常一個無痕)驗:

1. Admin 登入 → 建立 channel `test1`,密碼 `password123`
2. 瀏覽器 A 用 `test1` / `password123` 登入,看到空的時間軸
3. 瀏覽器 B 同樣登入
4. A 拖一個大檔(>100MB)進去 → 進度列有動、百分比會跑
5. 上傳完成的瞬間,**B 的頁面應該自動出現該項目**,不需要重新整理
6. B 點下載 → 檔案正確,大小相符
7. A 在文字框貼一段多行文字,Ctrl+Enter → B 立即看到
8. B 點複製 → 剪貼簿內容正確
9. A 截圖後在頁面上 Ctrl+V → 圖片以檔案形式上傳
10. B 刪除某項 → A 的頁面上該項消失
11. Admin 刪除 `test1` → 兩邊都失去存取,`storage` 裡的 blob 也不見了

## 邊界情況

- [ ] 上傳 0 bytes 的檔案 → 明確的錯誤訊息,不是 500
- [ ] 上傳超過 `MAX_UPLOAD_MB` → 明確的錯誤訊息
- [ ] 檔名含中文、空白、emoji → 下載時檔名正確
- [ ] 檔名含 `../` 或路徑分隔符 → 不會寫到預期目錄之外
- [ ] 同時上傳 5 個檔案 → 五條進度列各自獨立,不互相干擾
- [ ] 上傳中把分頁關掉 → 不會留下孤兒 blob(或至少有 job 會清掉)
- [ ] 文字項目內容含 `<script>` → 顯示為純文字,不會執行 🔒
