# Simple channel

A minimal relay for files and text messages.
1. An admin creates a named channel (name + password)
2. Any device that knows the name and password enters the same channel and drops files and text into it

---

## Running it

```bash
cp .env.example .env
sed -i "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -hex 64)|" .env
# then set ADMIN_PASSWORD in .env

docker compose build
docker compose up -d
docker compose logs -f
```

Open http://localhost:3000 → sign in at `/admin` to create a channel → back to
the home page and enter it with the channel name and password.

Secrets live in `.env` only (already gitignored) and never enter version control.
If any of the three required values is missing, compose refuses to start — on
purpose, so this can't quietly come up without an admin password.

## Environment variables

All of them go in `.env`; see [`.env.example`](.env.example).
Defaults for the optional ones live in `docker-compose.yml`.

| Variable | Default | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | **required** | `openssl rand -hex 64`. **Don't rotate on every restart** — it signs out every session |
| `ADMIN_USER` | **required** | Admin username |
| `ADMIN_PASSWORD` | **required** | Admin password. If either of the pair is blank, every admin login fails |
| `APP_PORT` | `3000` | Host port to publish on (the container always listens on 80) |
| `DEFAULT_TTL_DAYS` | `7` | Days until a new item expires. `0` = never |
| `MAX_UPLOAD_MB` | `2048` | Per-file limit |
| `API_TOKEN_TTL_MINUTES` | `5` | How long a copied curl URL keeps working |
| `FORCE_SSL` | `0` | `1` forces HTTPS and secure cookies |
| `RAILS_MAX_THREADS` | `5` | A direct upload's PUT holds a thread for the whole transfer |
| `HTTP_READ_TIMEOUT` / `HTTP_WRITE_TIMEOUT` | `3600` | Seconds Thruster allows for a whole upload / download (a hard deadline, not an idle timeout) |
| `TZ` | `Asia/Taipei` | Also determines how timestamps render |

There is no admin table. The admin is that one pair of `ADMIN_USER` /
`ADMIN_PASSWORD` values, compared with SHA256 plus a fixed-length comparison.

## The curl API

A channel page hands out ready-made commands for machines that have no browser.
Copy the one in the "Upload from a terminal" card, or press **Copy curl** on any
file to get its download command:

```bash
# upload -- the trailing slash is what makes curl append the file's own name
curl -T ./report.zip http://box:3000/api/c/lab1/u/eyJfcmFpbHMi…/

# download -- the filename in the path is what makes plain -O write the right one
curl -O http://box:3000/api/c/lab1/d/eyJfcmFpbHMi…/42/report.zip
```

An upload replies with the download URL for the item it just created, so a
script can hand one straight on.

**The token in the URL is the entire credential, and it is only good for five
minutes** (`API_TOKEN_TTL_MINUTES`). It is a signed message, not a stored
secret — `{ channel id, direction }` with an expiry, signed with a key derived
from `SECRET_KEY_BASE`. That has consequences worth knowing:

- Nothing is stored and nothing is revocable. A leaked URL is dealt with by
  waiting; five minutes is chosen to make that an acceptable answer.
- A link is minted for one direction. A download URL cannot upload, and an
  upload URL cannot read anything back.
- The channel page rotates its links before they expire, so what is on screen is
  always usable — but a URL already copied elsewhere still dies on its own
  schedule. Copy it again when it does.
- The token travels in the path, so it lands in access logs. That is the price
  of a URL that works with a bare `curl -T`, and the reason the window is short.

The API never reads the session, and being signed in to the channel in a browser
grants nothing there. Being able to *mint* a link is what needs the session:
`/c/:name/api_urls` is behind the same channel login as everything else.
Successful requests are not rate limited — pushing 200 files from a script is a
normal thing to do — but failed ones are, so probing gets nowhere.

## Expiry and cleanup

Solid Queue recurring jobs (`config/recurring.yml`), running inside the Puma
process (`SOLID_QUEUE_IN_PUMA=1`, no separate container):

- `CleanupExpiredItemsJob` — hourly; deletes items where `expires_at <= now`.
  `dependent: :purge_later` takes the ActiveStorage blob with it.
- `CleanupUnattachedBlobsJob` — hourly; purges orphaned blobs older than six hours.
  A direct upload creates the blob before the browser POSTs to `items#create`,
  so a closed tab or a rejected item (0 bytes, over the limit) leaves one behind.

Every user-facing query goes through `Item.alive`, so nothing depends on a
cleanup job having run yet.

---

## The three security invariants

These are why this app can exist at all, and each one has tests.
The implementation can change; the behaviour cannot — don't touch them without
moving the tests too.

### 1. Downloads are always `attachment` + `application/octet-stream` + `nosniff`

People move malware samples through this site. Upload an `.html` or an `.svg` and
it must never render inline in a browser. `ItemDownloading#send_item_file` writes
those three headers itself and never looks at the content type declared on the
blob. Two routes serve files — the browser's `items#download` and the curl API's
`api/items#show` — and they share that one concern rather than each writing their
own headers; the download tests run every header assertion against both.

→ `app/controllers/concerns/item_downloading.rb` · test `test/integration/download_test.rb`

Two things follow from it:

- **ActiveStorage's own blob-serving routes are not drawn.**
  `config.active_storage.draw_routes = false`, and `config/routes.rb` keeps only
  the two routes a direct upload needs. The default
  `/rails/active_storage/blobs/...` authenticates a blob's signed_id and ignores
  the session, which bypasses invariants 1 and 3 at once —
  and that signed_id is exactly what a direct upload hands back to the browser.
- **`x_sendfile_header` is deliberately off**, because with it on Thruster serves
  the file directly and those three headers are no longer ours to set.
  `send_file` streams through Rack's FileBody, so a multi-gigabyte file never
  lands in memory the way `send_data` would.

### 2. The login endpoints are rate limited

Channel names are enumerable; without a limit this is an open brute-force target.
`/login` and `/admin/login` both use `rate_limit to: 10, within: 3.minutes`
(built into Rails 8).

→ `app/controllers/sessions_controller.rb`, `app/controllers/admin/sessions_controller.rb`
· test `test/integration/rate_limit_test.rb`

`rate_limit` needs a real cache store. **With the wrong one it fails silently —
no error, it just doesn't block.** Production uses Solid Cache; the test
environment must use `:memory_store` (Rails' default `:null_store` would let the
whole rate limit suite pass while blocking nothing).

### 3. No cross-channel access

A session signed in to channel A cannot read, write, download or delete anything
in channel B. `current_channel` checks both that the channel exists and that its
id is in `session[:channel_ids]`, and every items action queries from
`current_channel.items` —
**there is no `Item.find(params[:id])` anywhere in the codebase**.

Admin and channel authorization are independent: an admin can create and delete
channels but cannot see what is inside them. That is on purpose.

The curl API has its own `current_channel`, resolved from the signed token
instead of the session, and it additionally requires that the channel named in
the path *is* the token's channel — a link for A is never usable under B's name.
It is CSRF-exempt because curl has no CSRF token, which is only safe as long as
it keeps ignoring the session completely: a cookie alone must be worth nothing
there, or exempting CSRF would open exactly the hole it exists to close.

→ `app/controllers/application_controller.rb`, `app/controllers/api/base_controller.rb`
· test `test/integration/authorization_test.rb`

### Other deliberate trade-offs

**Uploads are never parsed.** `config.active_storage.analyzers = []` /
`previewers = []` / `variant_processor = :disabled`, and the `image_processing`
gem is gone from the Gemfile (so the Dockerfile doesn't install libvips either).
People push hostile files through here, image and video parsers are the most
common RCE surface there is, and this app has no previews, thumbnails or
variants anyway.

---

## Development

The host doesn't need Ruby — run it in a container:

```bash
docker run --rm -it -v "$PWD:/app" -w /app \
  -v simple-channel-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -e GEM_HOME=/bundle -e HOME=/tmp \
  -u "$(id -u):$(id -g)" ruby:3.4 bash

# inside the container
bundle install
bin/rails db:prepare
bin/rails test
bin/rubocop
bin/brakeman
```

Gems go in a named volume so the repo stays clean; `-u` matches the host uid so
nothing is written back as root. `bundle install` needs `build-essential` and
`libyaml-dev`, both already in the full `ruby:3.4` image.

`config/brakeman.ignore` is empty. It used to hold one entry, for the `send_file`
in `items#download`; moving that call into `ItemDownloading` put it out of reach
of Brakeman's data flow and the warning stopped firing, so the entry went with
it. Read that as "Brakeman is no longer watching that line", not as "the line got
safer" — the argument for why the path is safe (it comes from `blob.key`, never
from a filename) is in the concern's comments, and the traversal test in
`download_test.rb` is what actually holds it. Any new entry must carry a `note`
explaining why it's acceptable.

### Test coverage

```
test/models/channel_test.rb                     name normalization, format, password length, authenticate, API tokens
test/models/item_test.rb                        kind validation, alive scope, TTL, size limits, broadcasts
test/integration/authorization_test.rb       🔒 invariant 3
test/integration/rate_limit_test.rb          🔒 invariant 2
test/integration/download_test.rb            🔒 invariant 1
test/integration/items_test.rb                  upload / send text / delete, XSS, 0 bytes, over the limit
test/integration/api_test.rb                    curl upload / download, token expiry, direction, failure limit
test/integration/sessions_test.rb               sign in and out, Turbo Stream broadcasts
test/integration/admin_test.rb                  blank ENV fails closed, create and delete channels
test/jobs/cleanup_expired_items_job_test.rb     expiry, and the blob really leaving disk
test/jobs/cleanup_unattached_blobs_job_test.rb  orphaned blobs
```
