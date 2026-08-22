# WP-CLI Gotchas & Non-Obvious Patterns

This file covers the parts of WP-CLI where defaults bite and where silent data corruption hides. For command references, use [developer.wordpress.org/cli](https://developer.wordpress.org/cli/commands/).

## search-replace

### The short version

```bash
wp search-replace 'old-string' 'new-string' \
    --all-tables-with-prefix \
    --precise \
    --skip-columns=guid \
    --dry-run
```

Then drop `--dry-run` when ready.

### Why every flag

- **`--precise`** — forces the PHP code path instead of the default SQL path. The SQL path is faster but auto-switches to PHP only when it *detects* serialized data. Non-serialized columns that contain escaped JSON (Gutenberg block attributes, ACF flex content config) are NOT auto-detected and get corrupted. Always use `--precise` for content migrations. It's 10–20× slower but correct.
- **`--skip-columns=guid`** — GUIDs are permanent identifiers in WP feeds and must never change, even on URL migrations. The codex is emphatic about this. wp-cli doesn't reliably skip `guid` by default despite some claims — skip it explicitly.
- **`--all-tables-with-prefix`** — default scope is only tables registered with `$wpdb`. This **misses** tables registered by plugins that don't hook into `$wpdb` (WooCommerce HPOS order tables, analytics plugins, many custom-plugin tables). `--all-tables-with-prefix` covers everything with the configured WP prefix. `--all-tables` covers *every* table in the DB regardless of prefix (only use if you know what you're doing).

### The Gutenberg escaped-slash trap

Block content stores URLs with escaped slashes: `http:\/\/example.com\/path\/`. A single search-replace pass over `https://old.com` → `https://new.com` **misses every block-stored URL**.

**Fix**: run two passes.

```bash
wp search-replace 'https://old.com' 'https://new.com' --precise --skip-columns=guid
wp search-replace 'https:\/\/old.com' 'https:\/\/new.com' --precise --skip-columns=guid
```

JSON-in-options and some ACF settings have the same pattern. If unsure, run both.

### `--dry-run` shows rows, not content

The dry-run report shows row counts, not the actual resulting strings. Serialized content can "count correct" and still re-serialize incorrectly on a real run if the source data was already corrupted. To see actual before/after:

```bash
wp search-replace 'old' 'new' --dry-run \
    --log=/tmp/sr.log \
    --before_context=40 \
    --after_context=40 \
    --report-changed-only
```

Inspect `/tmp/sr.log` before running for real.

### Post-ID remapping is dangerous

Using search-replace to remap post IDs (`wp search-replace '42' '99'`) can corrupt serialized-array length prefixes on unrelated rows. For ID remapping, script it via `update_field()` / `update_post_meta()` loops in `wp eval-file` instead. Details in `acf.md`.

### Table scope flags at a glance

| Flag | What it covers |
|------|----------------|
| (default) | Tables registered with `$wpdb` for the current blog |
| `--all-tables-with-prefix` | Every table matching the configured WP prefix (includes unregistered plugin tables) |
| `--all-tables` | Every table in the DB, prefix or not. Overrides `--network`. |
| `--network` | Multisite-registered tables across all sites (but NOT unregistered custom-plugin tables) |
| `--export=file.sql` | Writes SQL without touching the DB — good for staging→prod transfers |

---

## Database operations

### Always snapshot before destructive changes

```bash
wp db export db-snapshots/$(date -u +%Y%m%dT%H%M%SZ)-<reason>.sql --add-drop-table
```

`--add-drop-table` makes the dump idempotent — `wp db import` will drop existing tables before recreating them. Without it, if a table exists but has a different schema, import fails.

### Charset / collation mismatches

MySQL 8 → MariaDB (or older MySQL) imports often fail with `ERROR 1273 (HY000): Unknown collation: 'utf8mb4_0900_ai_ci'`. This is MySQL 8's default; older servers don't have it.

**Fix**:
```bash
sed -i 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' dump.sql
```

For Japanese / multibyte content, `utf8mb4_unicode_520_ci` is a good target. Never drop to `utf8mb4_general_ci` on multilingual content — collation affects sort order.

### `wp db query` through SSH+sudo

Quoting layers stack up (local shell → ssh → remote shell → sudo → wp-cli). Complex queries with quotes, backslashes, or multibyte chars get mangled silently. Safer options:

- Write the SQL to a file, scp it, then `wp db query < file.sql`
- Use `wp eval` with `$wpdb->prepare` — PHP handles the escaping
- For read-only queries, `--format=json` and pipe to `jq` on the local side

### `--no-tablespaces` is the default (good)

This avoids "PROCESS privilege" errors on managed DB hosts. If you need it for MyISAM tables with tablespaces, pass `--include-tablespaces` explicitly.

### MySQL 8 → 5.7 `column_statistics` error

If import fails with `Unknown table 'column_statistics'`, the dump was from MySQL 8 and includes a stats table the target doesn't have. Grep/remove that section or use `mysqldump --column-statistics=0` when producing the dump.

---

## Post meta and revisions

`wp post meta delete <id> <key>` and `delete_post_meta()` route **revision** IDs (`post_type = revision`, `post_status = inherit`) to the parent post — they leave the revision's own postmeta row untouched and return truthy with no error. If you're sweeping orphan meta after a schema or ACF location change, write your `DELETE` against `wp_postmeta` directly (or use `$wpdb->delete`), and `JOIN wp_posts` in the survey query so you can see which rows live on revisions vs. live posts.

Full pattern in `acf.md` → "Cleanup: orphan rows after re-scoping a field group".

---

## Remote invocation

### Verify the target

```bash
ssh <host> 'sudo -u www-data wp --path=<path> cli info'
```

Prints WP version, PHP version, DB host. Run this first on any remote session — catches typos in the path / wrong host / missing wp-cli.

### `wp-cli.yml` aliases

Instead of typing `ssh host 'sudo -u www-data wp --path=...'` every time, define aliases:

```yaml
# ~/.wp-cli/config.yml or project-root/wp-cli.yml
@staging:
  ssh: user@host:/var/www/site
  path: /var/www/site
  user: www-data

@prod:
  ssh: user@host:/var/www/prod
  path: /var/www/prod
  user: www-data
```

Then: `wp @staging db export`, `wp @prod option get siteurl`, etc. Aliases can be grouped (`@all: [@staging, @prod]`) for fan-out operations. See `templates/wp-cli.yml`.

**Gotcha**: the remote `wp` must be on `$PATH` for non-interactive SSH. `~/.bashrc` is NOT sourced for `ssh host 'cmd'`. Put `wp` in `/usr/local/bin` or configure `PermitUserEnvironment` + `~/.ssh/environment`.

### SSH multiplexing

```
# ~/.ssh/config
Host <host-alias>
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 10m
```

First connection auths; subsequent commands reuse the socket. Huge speedup when chaining wp-cli calls. Combine with `BatchMode=yes` in automation to fail fast instead of hanging on a prompt.

### stdout vs stderr

wp-cli prints progress/warnings to stderr, results to stdout. Nested `ssh ... 'sudo ... wp ...'` usually preserves both, but `sudo`'s `use_pty` setting can merge them. If you're parsing output:

```bash
ssh host 'sudo -u www-data wp --path=/path post list --format=json 2>/tmp/wperr' > posts.json
```

Avoid `ssh -t` when capturing binary or JSON output — it mangles both.

### Quoting

Anything inside the SSH command string gets re-parsed by the remote shell. Rules:

- Single-quote the whole remote command
- Escape inner single-quotes as `'\''`
- For anything non-trivial, write a shell script, scp it, execute it remotely

Do NOT:
```bash
ssh host "sudo -u www-data wp option update my_key '$value'"   # double quotes → local shell expands $value early
```

Do:
```bash
cat > /tmp/run.sh <<'EOF'
sudo -u www-data wp --path=/var/www/site option update my_key "$1"
EOF
scp /tmp/run.sh host:/tmp/
ssh host 'bash /tmp/run.sh "the actual value"'
```

---

## Permissions

### Always `sudo -u www-data`

wp-cli writes files — upload cache, update artifacts, `.maintenance`, plugin installs, compiled templates. Files written as root become root-owned; the webserver user then can't read/write them.

**Symptom**: weeks later, "plugin updates silently fail" or "media uploads don't save". The cause is buried ownership drift.

**Cleanup** if it's happened:
```bash
sudo chown -R www-data:www-data /var/www/site/wp-content
```

### `--allow-root` is a red flag

Only appropriate in containers where root *is* the site user. On bare-metal servers, avoid it. WP-CLI warns for good reason — any plugin code executes with root authority, and plugins from the .org repo have been compromised before.

`WP_CLI_ALLOW_ROOT=1` env var is equivalent to the flag; same caution applies.

### Check what the session can do

```bash
sudo -u www-data whoami        # confirm user
sudo -u www-data id            # confirm groups
sudo -u www-data touch /var/www/site/.test && rm /var/www/site/.test   # confirm write
sudo -u www-data wp cli info   # confirm wp-cli loads
```

---

## Multisite (brief)

- `--url=https://site.example/` is REQUIRED for per-site operations, or you hit the main site silently
- `--network` on `search-replace` covers registered tables across all sites but skips unregistered plugin tables — use `--all-tables-with-prefix` for those
- `wp cache flush` on multisite with persistent object cache nukes every site's cache — expect a thundering herd
- `wp site list --field=url` enumerates for fan-out

---

## Cache-related commands (summary)

Full details in `caching.md`. Quick reference:

| Command | Layer | When needed |
|---------|-------|-------------|
| `wp cache flush` | Object cache (Redis/Memcached) | After schema changes, cache-key changes |
| `wp transient delete --all` | DB-backed transients | After menu/option/ACF schema changes |
| `wp rewrite flush` | Rewrite rules | After CPT slug / permalink changes |

None of these touch nginx FastCGI, Varnish, or Cloudflare. Those need separate calls.

---

## Commonly needed one-liners

```bash
# Check what version is actually on disk
wp cli info

# Find which plugins are active
wp plugin list --status=active --field=name

# Check site URL (sanity check before ops)
wp option get siteurl

# Dump & re-import to regenerate a clean DB file
wp db export clean.sql --add-drop-table && wp db reset --yes && wp db import clean.sql

# List all custom tables (for full-scope search-replace)
wp db tables --all-tables-with-prefix

# Show the active theme
wp theme list --status=active --fields=name,version

# Tail WP debug log
tail -f wp-content/debug.log   # requires WP_DEBUG_LOG=true in wp-config.php
```
