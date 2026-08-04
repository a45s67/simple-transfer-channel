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
| `FORCE_SSL` | `0` | `1` forces HTTPS and secure cookies |
| `RAILS_MAX_THREADS` | `5` | A direct upload's PUT holds a thread for the whole transfer |
| `TZ` | `Asia/Taipei` | Also determines how timestamps render |

There is no admin table. The admin is that one pair of `ADMIN_USER` /
`ADMIN_PASSWORD` values, compared with SHA256 plus a fixed-length comparison.

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
it must never render inline in a browser. `items#download` writes those three
headers itself and never looks at the content type declared on the blob.

→ `app/controllers/items_controller.rb` · test `test/integration/download_test.rb`

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

→ `app/controllers/application_controller.rb` · test `test/integration/authorization_test.rb`

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

`config/brakeman.ignore` holds one documented false positive (the `send_file` in
`items#download`). Any new entry must carry a `note` explaining why it's acceptable.

### Test coverage

```
test/models/channel_test.rb                     name normalization, format, password length, authenticate
test/models/item_test.rb                        kind validation, alive scope, TTL, size limits, broadcasts
test/integration/authorization_test.rb       🔒 invariant 3
test/integration/rate_limit_test.rb          🔒 invariant 2
test/integration/download_test.rb            🔒 invariant 1
test/integration/items_test.rb                  upload / send text / delete, XSS, 0 bytes, over the limit
test/integration/sessions_test.rb               sign in and out, Turbo Stream broadcasts
test/integration/admin_test.rb                  blank ENV fails closed, create and delete channels
test/jobs/cleanup_expired_items_job_test.rb     expiry, and the blob really leaving disk
test/jobs/cleanup_unattached_blobs_job_test.rb  orphaned blobs
```
