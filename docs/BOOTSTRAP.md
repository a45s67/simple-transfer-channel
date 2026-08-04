# Bootstrap

## 1. 生骨架

在這個 spec 目錄的**外面**跑:

```bash
gem install rails -v '~> 8.0'

rails new simple_channel \
  --database=sqlite3 \
  --skip-action-mailer \
  --skip-action-mailbox \
  --skip-action-text \
  --skip-jbuilder \
  --skip-system-test \
  --skip-kamal \
  --skip-devcontainer
```

保留的東西以及理由:

- **ActiveStorage** — direct upload 是整個上傳體驗的核心,檔案不經過 Puma
- **Turbo + Stimulus + importmap** — 即時同步和前端互動,不需要 Node build step
- **Solid Queue / Cache / Cable** — 分別給過期清除、rate limit、Turbo 廣播用,全部走 SQLite
- **Propshaft** — 資產處理
- **minitest** — 你要靠它迭代
- **rubocop-rails-omakase / brakeman** — 保持綠燈

跳掉的都是這個 app 用不到的。`--skip-system-test` 是因為 headless browser 在容器裡很麻煩,
拖拉和貼上改用 JS 單元邏輯 + 整合測試涵蓋。

## 2. 把 spec 目錄搬進去

```bash
mv ../sc-spec simple_channel/docs
cd simple_channel
```

之後 `docs/reference/` 就是你適配的來源。

## 3. 需要手動 pin 的 JS

importmap 預設**不會**幫你 pin ActiveStorage。要自己加:

```bash
bin/importmap pin @rails/activestorage --from unpkg
```

或直接在 `config/importmap.rb` 寫(用 gem 自帶的資產,不依賴 CDN,推薦這個):

```ruby
pin "@rails/activestorage", to: "activestorage.esm.js"
```

然後在 `app/javascript/application.js` 加 `import "@rails/activestorage"`。

**注意**:`ActiveStorage.start()` 只在有 `data-direct-upload-url` 的 form field 時才起作用。
我們是從 Stimulus controller 手動 `new DirectUpload(...)`,
所以**不需要**呼叫 `ActiveStorage.start()`,只要 import `DirectUpload` 這個 class。

## 4. Solid Queue 跑在 Puma 內

Rails 8 生出來的 `config/puma.rb` 已經有這行:

```ruby
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]
```

所以只要在 compose 的 environment 設 `SOLID_QUEUE_IN_PUMA: "1"` 就好,不用改 puma.rb。

`config/recurring.yml` 需要自己寫,參考 `docs/reference/config/recurring.yml`。

## 5. Docker

`rails new` 生的 Dockerfile 直接用,不要重寫。它已經處理了 jemalloc、非 root 使用者、
Thruster、bootsnap、assets precompile,寫得比手工的好。

只要改一個地方:確認 `db/`、`storage/`、`log/`、`tmp/` 在 `chown` 那行裡。

compose 檔參考 `docs/reference/docker-compose.yml`。**用 named volume,不要 bind mount**
(理由見 GOTCHAS.md 第 1 條)。

## 6. 第一次跑起來之後

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

把 `Gemfile.lock` commit 進去。
