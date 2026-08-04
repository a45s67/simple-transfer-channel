# 部署

把這個 repo 送上一台你 ssh 得進去的機器(例如 homelab 的 Debian),然後跑起來。

兩種方式:

| | [方法 1:`git archive` + ssh](#方法-1git-archive--ssh) | [方法 2:bare repo + `git push`](#方法-2bare-repo--git-push) |
|---|---|---|
| 一次性丟過去看看 | ✅ | 過度 |
| 會反覆改、反覆部署 | ❌ 孤兒檔案會累積 | ✅ |
| 對面要能查版本 / rollback | ❌ | ✅ |
| 對面沒有 git 也能用 | ✅ | ❌ |
| 前置作業 | 無 | 一次 |

**會反覆部署就直接用方法 2。**

兩種方式都**不會碰 `storage/`** —— 線上的 SQLite 資料庫和使用者上傳的檔案是安全的。

---

## 先做:準備目標機器的 `.env`

祕密不進版控,每台機器各自維護一份。**這一步兩種方法都要做,而且要在第一次
`docker compose up` 之前做完**,否則 compose 會直接報錯不讓你起。

在目標機器上:

```bash
cd ~/srv/sc
cp .env.example .env
sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -hex 64)|" .env
# 再把 ADMIN_PASSWORD 填掉
```

必填三項:`SECRET_KEY_BASE`、`ADMIN_USER`、`ADMIN_PASSWORD`。
其餘可選項的預設值寫在 `docker-compose.yml` 裡,要改才寫進 `.env`。

`SECRET_KEY_BASE` **不要每次部署都換** —— 換掉之後所有人的 session 會失效。

> `.env` 是 `.gitignore` 掉的,不會被 push 也不會被 `git archive` 打包,
> 所以它在目標機器上是持久的,重複部署不會覆蓋掉。

---

## 方法 1:`git archive` + ssh

### 部署

```bash
git archive HEAD | ssh -C user@debian 'mkdir -p ~/srv/sc && tar -xf - -C ~/srv/sc'
```

然後在目標機器上:

```bash
cd ~/srv/sc
docker compose build && docker compose up -d
```

### 這行指令在做什麼

```
git archive HEAD | ssh -C user@debian 'mkdir -p ~/srv/sc && tar -xf - -C ~/srv/sc'
└──────┬───────┘ │ └───────────────────────┬───────────────────────────────────┘
   本地打包      管線                   遠端解開
```

`git archive HEAD` 把 HEAD 的檔案樹輸出成 tar 串流到 stdout,管線接給 ssh,
**ssh 會把本地 stdin 轉發給遠端指令的 stdin**,遠端的 tar 再從 stdin 解開。
中間不產生任何檔案。

- 只含被 git 追蹤的檔案 —— `.gitignore` 裡的 `storage/`、`tmp/`、`log/`、`.env`
  自動排除,也沒有 `.git/` 目錄
- **用單引號**,`~` 才會由遠端 shell 展開(雙引號會變成你本機的家目錄)
- `-C` 讓 ssh 壓縮傳輸
- `-f -` 的 `-` 就是 stdin。GNU tar 不寫也會從 stdin 讀,但明寫對 BSD / busybox tar 比較保險
- `&&` 短路:目錄建不出來就不會解到奇怪的地方

打包量的差別很大 —— 直接 `tar czf .` 或 `zip -r` 是 5.7M(會把 3250 個雜物含
SQLite 資料庫一起包進去),`git archive` 是 61K。

### 限制

**只覆蓋,不刪除。** tar 解壓是疊上去的,你在 repo 裡刪掉的檔案在對面會留著。
實測:先部署有 `README.md` 的版本,再部署刪掉它的版本 → `README.md` 仍在對面。
反覆部署下去,對面的目錄會和 repo 對不上,而你不會知道。

另外它不是原子操作(連線斷掉會留下解到一半的目錄),對面也沒有版本資訊。

想要每次都乾淨,得解到新目錄再換過去:

```bash
git archive HEAD | ssh user@debian '
  rm -rf ~/srv/sc.new && mkdir -p ~/srv/sc.new && tar -xf - -C ~/srv/sc.new
  cp ~/srv/sc/.env ~/srv/sc.new/.env 2>/dev/null || true
  rm -rf ~/srv/sc.old && mv ~/srv/sc ~/srv/sc.old 2>/dev/null; mv ~/srv/sc.new ~/srv/sc'
```

注意要自己把 `.env` 帶過去 —— 它不在 archive 裡。到這個複雜度就該用方法 2 了。

---

## 方法 2:bare repo + `git push`

### 一次性設定

**目標機器上:**

```bash
mkdir -p ~/srv/sc.git ~/srv/sc
git init --bare ~/srv/sc.git
```

建立 `~/srv/sc.git/hooks/post-receive`:

```bash
#!/bin/bash
set -e
unset GIT_DIR
BARE="$HOME/srv/sc.git"
TARGET="$HOME/srv/sc"

while read -r _old _new ref; do
  [ "$ref" = "refs/heads/main" ] || continue
  git --git-dir="$BARE" --work-tree="$TARGET" checkout -f main
  cd "$TARGET"
  docker compose build && docker compose up -d
  echo "[deploy] 已更新到 $(git --git-dir="$BARE" rev-parse --short main)"
done
```

```bash
chmod +x ~/srv/sc.git/hooks/post-receive
```

- `unset GIT_DIR` 是必要的 —— hook 執行時 git 會設一個相對路徑的 `GIT_DIR`,
  `cd` 之後就失效了
- `while read` 讀的是 post-receive 從 stdin 收到的 ref 清單,只有 push 到 main 才部署
- 用 **bare** repo 是因為往「有 checkout 的 repo」push 當前分支,
  git 預設會擋(`receive.denyCurrentBranch`)

**開發機上:**

```bash
git remote add homelab user@debian-host:srv/sc.git
```

> 這是 scp-like 語法,路徑相對於遠端使用者的家目錄。
> 要用 `ssh://` 開頭的話路徑必須是絕對的:
> `ssh://user@debian-host/home/user/srv/sc.git`。兩種語法不要混用。

第一次 push 之前記得先在 `~/srv/sc` 放好 `.env`(見上面)。

### 之後每次部署

```bash
git push homelab main
```

輸出:

```
remote: [deploy] 已更新到 3691640
```

### 為什麼這個比較乾淨

`git checkout -f` 會讓工作樹**完全對齊** commit:repo 裡刪掉的檔案在對面也會消失,
但 untracked 的東西(`storage/`、`.env`)完全不受影響。實測結果:

| 檢查項目 | 結果 |
|---|---|
| 刪掉的檔案有沒有從對面消失 | ✅ 有 |
| `storage/production.sqlite3` | ✅ 保住了 |
| `.env` | ✅ 保住了 |
| 對面有沒有多一個 `.git/` | ✅ 沒有(bare repo 在別的地方) |

還可以查版本:

```bash
git --git-dir=~/srv/sc.git log --oneline
```

### Rollback

```bash
cd ~/srv/sc
git --git-dir=~/srv/sc.git --work-tree=. checkout -f <前一個 commit>
docker compose build && docker compose up -d
```

---

## 部署之後

```bash
docker compose logs -f          # 確認 Puma 和 Solid Queue 都起來了
curl -f localhost:3000/up       # health check
```

開 `http://<host>:3000` → `/admin` 登入建 channel。

`FORCE_SSL` 預設 `0`(純 HTTP)。**放到公開網路前請在 `.env` 設 `FORCE_SSL=1`**,
並在前面擺一台終結 TLS 的 reverse proxy。`/up` 不受 HTTPS 轉址影響。

### 備份

資料全部在一個 named volume 裡(SQLite 四個 db 檔 + ActiveStorage 的 blob):

```bash
docker compose cp app:/rails/storage ./backup-$(date +%F)
```

不要把 `storage/` 改成 bind mount —— 容器裡跑的是非 root 的 `rails` 使用者(UID 1000),
host 上的目錄是 root 所有,SQLite 會直接開不起來。
