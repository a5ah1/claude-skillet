---
name: wp-ops
description: Operate safely against WordPress sites via WP-CLI, including remote installations accessed over SSH. Use this skill whenever the user asks to run WP-CLI commands, deploy to a WordPress site, clone WP between environments (prod↔staging↔local), update content / options / post meta / ACF fields via CLI, purge caches (Cloudflare / nginx FastCGI / WP object cache), troubleshoot stale content on a cached site, snapshot or roll back a WP database, or do any WordPress operation that involves SSH access to a server. Also trigger when the user mentions "production WordPress", "staging site", "wp search-replace", "ACF field update", "cache purge", "maintenance mode", or describes a WP task where getting it wrong would damage live content. The skill maintains a per-project registry of WP installations and encodes non-obvious safety patterns — dual-row ACF storage, cache-layer purge ordering, pre-op DB snapshots, prod→local sanitization — that prevent real damage.
---

# wp-ops

A skill for operating WordPress sites via WP-CLI, with emphasis on remote installations and the gotchas that bite in production.

This skill does not re-document WP-CLI. The WP-CLI command reference is already clear at [developer.wordpress.org/cli](https://developer.wordpress.org/cli/commands/). What's captured here is the *surrounding procedural knowledge*: what order to do things in, where silent data corruption hides, and how to roll back when something breaks.

---

## 1. Find the target installation first

Every operation targets a specific WP install. Before running anything, figure out which one.

Look for `<project-root>/.claude/wp-installations.json` — this is where a project registers its installs (paths, SSH hosts, cache layers, token env var names). If the file exists, read it before asking the user which environment. If it doesn't exist and the project has multiple environments, offer to create it from `templates/wp-installations.json` — it's worth the 2 minutes because the skill consults it every time.

**Verify before operating** (especially on remote hosts):

```bash
ssh <host> 'sudo -u www-data wp --path=<path> cli info'
```

This prints WP version, PHP version, DB host, and confirms the path resolves. Catches typos before you touch data. Run it once at the start of a session and you've ruled out a whole class of "oops wrong site" errors.

---

## 2. Invocation pattern

- **Local**: `sudo -u www-data wp --path=/var/www/site.test <command>`
- **Remote**: `ssh <host> 'sudo -u www-data wp --path=/var/www/site <command>'`

Always `sudo -u www-data` (or whichever user the webserver runs as). Never `--allow-root` outside a container where root *is* the site user. **Why it matters**: wp-cli writes files — upload cache, update artifacts, `.maintenance`, plugin installs. Files written as root end up root-owned, and the webserver user can't later read/write them. The symptom is weeks later: "plugin updates silently fail" or "uploads don't save". By then the cleanup (`chown -R`) is obvious but the cause is hidden.

**SSH multiplexing** speeds up long sessions dramatically. In `~/.ssh/config`:
```
Host <alias>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```
First connection prompts (if needed); subsequent `ssh <alias> ...` reuse the socket. Critical when chaining 10–20 wp-cli calls.

**Quoting over SSH**: the remote shell re-evaluates the command. Single-quote the whole remote command. Escape inner single-quotes. For anything complex, write a local script and `scp + ssh execute` instead of inline.

---

## 3. Triage table

| Task | Primary reference |
|------|-------------------|
| Deploy theme/plugin to staging or prod | `references/caching.md` (deploy sequence) + `scripts/safe-deploy.sh` |
| Clone prod → local | `references/clone-down.md` (**must sanitize first**) |
| Clone local → staging | `references/wp-cli-gotchas.md` §search-replace |
| Update ACF field values | `references/acf.md` |
| Update options / post meta | `references/wp-cli-gotchas.md` + `references/safety.md` |
| Purge caches / fix stale content | `references/caching.md` |
| Plugin or core update on prod | `references/safety.md` §updates |
| Anything that can't be undone | `references/safety.md` §destructive-ops |

---

## 4. Non-negotiable safety defaults

Before ANY destructive operation — `search-replace`, `db query` with `UPDATE`/`DELETE`, plugin/core update, `option update`, anything with `--yes`, or `wp db import` onto an existing DB:

1. **Snapshot the DB.**
   ```bash
   wp db export db-snapshots/<env>-$(date -u +%Y%m%dT%H%M%SZ)-<reason>.sql --add-drop-table
   ```
   Store outside webroot. `--add-drop-table` makes restores idempotent. See `scripts/pre-op-snapshot.sh`.

2. **Verify the target.** `wp option get siteurl` — does it match what you expect? On SSH sessions, also `wp cli info` to confirm the path. This is a 2-second check that has saved people from running prod commands against prod when they meant staging.

3. **Dry-run where supported.** `wp search-replace --dry-run` works. `wp plugin update --dry-run` works. `wp db query` has no dry-run — simulate with a matching `SELECT` first (convert `UPDATE x SET y=z WHERE w=1` to `SELECT id, w, y FROM x WHERE w=1`).

4. **Confirm with the user before destructive prod operations.** Show: the exact command, the target (URL + path), the snapshot path, the rollback command. Wait for explicit approval. Never assume "--yes they said go ahead" covers a second similar command.

---

## 5. Cache-layer awareness

WordPress in production usually sits behind **multiple cache layers**. Different commands address different layers; none of them covers all of them.

| Layer | Purged by |
|-------|-----------|
| Browser | Hard-reload (your problem) |
| CDN (Cloudflare) | API call with bearer token |
| Origin page cache (nginx FastCGI / Varnish) | Purge endpoint or `rm` cache dir |
| PHP opcache | `systemctl reload php-fpm` |
| WP object cache (Redis/Memcached) | `wp cache flush` |
| WP transients (DB-backed) | `wp transient delete --all` |
| WP rewrite rules | `wp rewrite flush` |

**Purge order: inside-out.** Opcache → WP caches → origin page cache → CDN. If you invalidate CDN first, it immediately refills from the still-stale origin and you're back to square one.

**`wp cache flush` ≠ "flush the page cache"** — it flushes the object cache only. This confuses people constantly.

Full sequences and per-layer commands in `references/caching.md`.

---

## 6. ACF gotcha (the biggest one)

ACF stores each field value as **two rows** in postmeta: the value (keyed `my_field`) and a field-key reference (keyed `_my_field` = `field_abc123`). `get_field()` uses the reference row to locate the field definition — without it, filters like image-URL resolution and relationship-object hydration silently don't run.

**Consequence**: `wp post meta update 42 my_field 'new value'` writes only the value row. `get_field('my_field', 42)` may return `null` or raw unformatted data.

**Fix**: use `wp eval` / `wp eval-file` to call `update_field()`, which writes both rows and triggers ACF's update filters:

```bash
wp eval "update_field('field_abc123', 'new value', 42);"
```

Repeaters, flexible content, and options pages have their own storage quirks — see `references/acf.md`.

---

## 7. Clone prod → local (the most dangerous routine)

The up-direction (local → staging) is generally safe. The **down-direction** is where real damage happens: the clone still has real user emails, real SMTP config, real payment API keys, real cron jobs that may fire outbound requests on first page load.

**Required first step**: drop a `00-local-safety.php` mu-plugin that kills `wp_mail` **before any other step, and before any HTTP request hits the clone**. Template at `templates/00-local-safety.php`. Full sanitization sequence in `references/clone-down.md`.

---

## 8. Rolling back

For every destructive op, know the rollback **before** running:

- DB change → `wp db import <snapshot>` (reset first if schema diverged)
- Plugin update → restore `wp-content/plugins/` from pre-op rsync backup; re-import snapshot if DB schema changed
- File deploy → re-rsync from a known-good local checkout

**DDL auto-commits.** `ALTER TABLE`, `DROP TABLE`, `TRUNCATE` commit implicitly — wrapping them in `START TRANSACTION` does nothing. The snapshot is your only rollback for schema changes.

---

## 9. The installation registry

Path: `<project-root>/.claude/wp-installations.json`

Schema lives at `templates/wp-installations.json`. Each entry captures:
- `path` — WordPress root
- `url` — canonical site URL (for search-replace)
- `ssh` — host alias (omit for local)
- `sudo_user` — usually `www-data`
- `cache` — which cache layers are in front (FastCGI zone/purge endpoint, Cloudflare token env var, etc.)

**Secrets do not live in the registry.** Store env var names (`CF_TOKEN`), load the values from the shell environment or a gitignored `.env`. Commit the registry file; do not commit secrets.

---

## 10. Troubleshooting checklist

Common symptoms and where to look:

| Symptom | First check |
|---------|-------------|
| "Old content still showing on the site" | `references/caching.md` §diagnosis |
| "`get_field()` returns empty after an update" | `references/acf.md` §dual-row |
| "search-replace ran but nothing changed" | `references/wp-cli-gotchas.md` §search-replace — likely escaped-slash in Gutenberg blocks or wrong `--all-tables` scope |
| "Plugin update broke the site" | `references/safety.md` §rollback-after-wsod |
| "Can't write to uploads / plugin install fails" | Permissions drift — `chown -R www-data:www-data wp-content/` |
| "Maintenance mode not showing on long migration" | `.maintenance` expires after 10 min — see `references/safety.md` |
| "Commands hang over SSH" | Check `ControlMaster`; try without `-t`; ensure wp-cli is on PATH for non-interactive shells |
| "Imported DB has wrong charset/collation" | `utf8mb4_0900_ai_ci` vs `utf8mb4_unicode_ci` mismatch — see `references/wp-cli-gotchas.md` §db |

---

## Reference files

Read the relevant one(s) when the task calls for depth:

- `references/wp-cli-gotchas.md` — search-replace, db export/import, remote invocation, permissions, multisite
- `references/acf.md` — dual-row storage, repeaters, flexible content, options pages, safe update patterns
- `references/caching.md` — purge ordering per layer, cache-status diagnosis, deploy sequence
- `references/safety.md` — snapshots, maintenance mode, dry-runs, destructive commands, rollback patterns
- `references/clone-down.md` — prod→local sanitization (mu-plugin, cron disable, PII scrub, API key null-out)

## Scripts

Templates that can be copied into a project and adapted:

- `scripts/pre-op-snapshot.sh` — timestamped DB snapshot helper
- `scripts/safe-deploy.sh` — rsync → chown → opcache → WP caches → FastCGI → Cloudflare
- `scripts/clone-down.sh` — guided prod→local with sanitization baked in

## Templates

- `templates/wp-installations.json` — registry schema with an example
- `templates/00-local-safety.php` — mu-plugin that kills outbound email in dev clones
- `templates/wp-cli.yml` — wp-cli config with `@alias` blocks for multi-env shortcuts
