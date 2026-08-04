# Simple channel — notes for Claude Code

A self-hosted file relay. Rails 8 monolith, SQLite, ActiveStorage disk service,
Turbo + Stimulus + importmap, no Node build step.

## The three things that are not negotiable

These are security invariants. How they are implemented can change; the behaviour
cannot. Each already has tests — when you touch one, the tests must change with
it, not just be made to pass again.

1. **Downloads are always `Content-Disposition: attachment` and
   `Content-Type: application/octet-stream`.**
   People move malware samples through this site. Upload an `.html` or `.svg`
   and it must never render inline in a browser. The MIME type declared at
   upload time is attacker-controlled — don't trust it.
   → `items#download` · `test/integration/download_test.rb`

   Two things go with it: don't turn on `config.active_storage.draw_routes`, and
   don't enable `x_sendfile_header`. Reasons are in the README under
   "The three security invariants".

2. **The channel login endpoint must be rate limited.** Channel names are
   enumerable; without a limit this is an open brute-force target. Use the
   `rate_limit` built into Rails 8. The test environment's `cache_store` must be
   `:memory_store` — with `:null_store` the limit fails silently and the whole
   suite goes green while blocking nothing.
   → `test/integration/rate_limit_test.rb`

3. **No cross-channel access.** A session signed in to channel A must not read,
   write, download or delete anything in channel B. Every items action queries
   from `current_channel`, never `Item.find(params[:id])`. Admin and channel
   authorization are independent.
   → `application_controller#current_channel` · `test/integration/authorization_test.rb`

## Scope

This is an MVP. Don't add features that weren't asked for — in particular **file
previews, thumbnails and variants**. That isn't only a scope question: it would
put an image parser in front of hostile uploads. ActiveStorage's analyzers and
previewers are switched off on purpose.

## Secrets

`SECRET_KEY_BASE` / `ADMIN_USER` / `ADMIN_PASSWORD` live in `.env` only.
**Never write them back into `docker-compose.yml`** — that file is in version
control. When you add an environment variable, update `.env.example` too.

## Style

- rubocop-rails-omakase stays green
- brakeman warnings get either fixed or an entry in `config/brakeman.ignore`
  with a `note` explaining why it's acceptable

## Definition of done

- `bin/rails test` all green
- `bin/rubocop` no offenses
- `bin/brakeman` no unexplained warnings
- If you touched upload, download or live sync: `docker compose build &&
  docker compose up -d` and walk it in two browsers (drag, paste, progress bars,
  the item appearing on the other device, download)

## Development environment

The host may not have Ruby. Run in a container — see "Development" in the README.
