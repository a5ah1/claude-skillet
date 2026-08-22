# Safety & Rollback Patterns

This file covers the guardrails for destructive wp-cli operations: snapshots, dry-runs, maintenance mode, plugin/core updates, and what rollback actually looks like when things go wrong.

## The rule of thumb

**For every destructive op, know your rollback before running it.** If you can't state the exact rollback command in one sentence, stop and figure that out first.

---

## 1. Pre-op DB snapshots

### When

Before:
- `wp search-replace` (even with `--dry-run` done)
- `wp db query` with `UPDATE`/`DELETE`/`DROP`/`ALTER`
- `wp db reset`, `wp db import`
- `wp site empty`
- `wp plugin update`, `wp core update`
- `wp option update`/`wp post meta update` on critical options
- ACF field-group overwrites

### Command

```bash
wp db export db-snapshots/<env>-$(date -u +%Y%m%dT%H%M%SZ)-<reason>.sql --add-drop-table
```

- **`--add-drop-table`** — import becomes idempotent (drops existing tables before recreate). Without it, schema mismatches fail imports.
- **UTC ISO-8601 timestamp** — sorting matches chronology.
- **Reason slug** — `ls` tells you why each snapshot exists.

### Where

**Outside the webroot.** Never `/var/www/site/db-snapshots/` — that's publicly accessible. Good locations:
- On the server: `/var/backups/<site>/`
- Pulled back to dev machine: `<project>/content/snapshots/` (gitignored)

### Retention

Keep last 10 pre-op snapshots + any manually tagged "known-good" ones. `find db-snapshots/ -mtime +30 -delete` in cron is fine but only after a separate process has pushed them to durable storage.

### Restore

```bash
wp db import db-snapshots/prod-20260413T1432Z-pre-plugin-update.sql
```

**Two gotchas**:
1. `wp db import` runs against whatever `wp-config.php` points at — confirm with `wp config get DB_NAME` first
2. It does NOT drop tables that exist in the target but not the dump. If you added tables post-snapshot, they persist. Safer: `wp db reset --yes && wp db import <file>` (destructive — only on dev/staging).

### Atomic snapshot+op pattern

```bash
SNAP=$(wp db export --porcelain)
<risky command> || wp db import "$SNAP"
```

`--porcelain` returns just the filename. One-line rollback on failure.

See `scripts/pre-op-snapshot.sh` for a wrapper.

---

## 2. Maintenance mode

### What it does

`wp maintenance-mode activate` drops a `.maintenance` file in the WP root containing `<?php $upgrading = <timestamp>;`. Core's `wp_maintenance()` checks for it on every request and serves the default "Briefly unavailable for scheduled maintenance" screen via `die()` before bootstrapping most of WP.

### The 10-minute silent expiry

WordPress only honors `.maintenance` if `$upgrading` is **less than 10 minutes old**. Long migrations silently exit maintenance mode mid-operation.

**Fixes for long ops**:
- Touch-loop the file: `while true; do touch .maintenance; sleep 60; done &`
- Write a custom `.maintenance` with fresh timestamps
- Drop `wp-content/maintenance.php` — core `require`s this drop-in file when in maintenance mode, and its presence can display a custom screen independent of the timestamp

### When it's worth it

- DB migrations >30s
- Schema changes (`ALTER TABLE` on big tables)
- Bulk `wp search-replace`
- Plugin/core updates on prod
- Bulk media operations

### When it's overkill

- `wp option update <single_key>`
- `wp post meta update` on a handful of posts
- Read-only `wp db query 'SELECT ...'`
- CSS/JS deploys

### Activate / deactivate

```bash
wp maintenance-mode activate
# ... run op ...
wp maintenance-mode deactivate
```

### The reverse-proxy caveat

If nginx/Varnish is serving cached pages, visitors see the cached page before PHP's maintenance check runs — maintenance mode is invisible until cache expires. For a visible maintenance screen behind an aggressive cache, either:
- Purge cache before activating maintenance mode (trades visitor experience for correctness)
- Add an nginx rule returning `503` during the window (server-level)

---

## 3. Dry-run patterns

### Commands that support `--dry-run`

- `wp search-replace` — full support, prints a report
- `wp plugin update` — supported
- `wp theme update` — probably supported (verify)
- `wp core update` — NOT supported; use `wp core check-update` instead

### Commands that do NOT support `--dry-run`

- `wp db query`, `wp db import`, `wp db reset`
- `wp option update`, `wp post meta update`, `wp user update`
- `wp site empty`

### Simulating dry-run for unsupported commands

| Command | Simulation |
|---------|------------|
| `wp db query "UPDATE x SET y=z WHERE w=1"` | Run `SELECT id, w, y FROM x WHERE w=1` first to see row count and scope |
| `wp option update <key> <val>` | `wp option get <key> --format=json > /tmp/before.txt`, change, compare |
| `wp post meta update <id> <key> <val>` | `wp post meta get <id> <key>` first |
| `wp user update <id> ...` | `wp user get <id> --format=json` first |
| Bulk scope check | `wp post list --meta_key=... --format=ids \| wc -l` |

### `search-replace` with inspection

```bash
wp search-replace 'old' 'new' --dry-run \
    --log=/tmp/sr.log \
    --before_context=40 \
    --after_context=40 \
    --report-changed-only
```

Inspect `/tmp/sr.log` before the real run.

---

## 4. Atomic operations

### Single-invocation transactions

```bash
wp db query "START TRANSACTION; UPDATE ...; UPDATE ...; COMMIT;"
```

The statement list runs in one connection; `START TRANSACTION`/`COMMIT`/`ROLLBACK` work. Useful for multi-row consistency.

### DDL kills transactions

**MySQL issues an implicit COMMIT before AND after every DDL statement.** DDL = `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`, `TRUNCATE`, `RENAME TABLE`.

```sql
START TRANSACTION;
ALTER TABLE x ADD COLUMN y INT;  -- implicit COMMIT happens here
UPDATE y SET z = 1;              -- runs in a new implicit transaction
ROLLBACK;                         -- rolls back ONLY the UPDATE
```

The `ALTER` is already permanent. **Never mix DDL and DML in a single transactional block** — do them as separate snapshot+op pairs.

### MyISAM caveat

Legacy WP tables may be MyISAM (non-transactional). `START TRANSACTION` silently accepts but does nothing. Check:

```bash
wp db query "SELECT table_name, engine FROM information_schema.tables WHERE table_schema=DATABASE();"
```

Modern installs default to InnoDB, but old sites mix.

### Practical rollback for non-transactional ops

The rollback IS the DB snapshot. There is no middle ground.

---

## 5. Destructive commands & guardrails

### The dangerous ones

| Command | What it does | Guardrail |
|---------|--------------|-----------|
| `wp db reset` | DROPs and re-CREATEs the database | Confirm NOT prod (check `siteurl`), fresh snapshot, explicit user confirmation — don't rely on `--yes` alone |
| `wp site empty` | Truncates posts/comments/terms/meta (keeps users/options) | Snapshot; never with `--uploads` on prod |
| `wp site empty --uploads` | Additionally wipes `wp-content/uploads/` | Flag visibly; never on prod |
| `wp post delete --force` | Skips trash | Omit `--force` where possible — trash is recoverable |
| `wp search-replace` | See dedicated section below | `--precise --skip-columns=guid`, table scope, dry-run |
| `wp db import` | Replaces DB contents | Verify target DB, pre-op snapshot |
| `wp plugin update --all` | Updates all at once | Loop one at a time for failure isolation |
| `wp core update --force` | Bypasses version checks | Very rarely needed |

### `search-replace` footguns

- Omitting table list → replaces across ALL registered tables (often desired, sometimes not)
- Forgetting `--skip-columns=guid`
- Too-generic search string (e.g., `http://` with no host)
- Forgetting `--precise` → escaped-slash Gutenberg blocks don't get replaced
- Wrong direction (`old` and `new` swapped — hard to undo without snapshot)

### Checksum discipline

```bash
wp core verify-checksums          # before/after core updates
wp plugin verify-checksums --all  # plugins in .org repo only
```

For custom theme/plugin files (not in .org), manual:
```bash
find wp-content/themes/my-theme -type f -exec sha256sum {} \; | sort | sha256sum
```

---

## 6. Plugin / core updates on production

### Safe sequence

```bash
# 1. Snapshot
wp db export db-snapshots/prod-$(date -u +%Y%m%dT%H%M%SZ)-pre-update.sql --add-drop-table

# 2. Backup plugin files
rsync -a /var/www/site/wp-content/plugins/ /var/backups/site/plugins-$(date -u +%Y%m%dT%H%M%SZ)/

# 3. Maintenance mode
wp maintenance-mode activate

# 4. Update plugins one at a time (NOT --all)
wp plugin list --update=available --field=name | while read p; do
    wp plugin update "$p" || { echo "FAILED on $p"; break; }
done

# 5. Verify nothing auto-deactivated
wp plugin list --status=active

# 6. Smoke test
curl -sI https://example.com/ | head -1
wp option get siteurl
# hit 2-3 key URLs while logged in as admin in another window

# 7. Cache flush
wp cache flush

# 8. Maintenance mode off
wp maintenance-mode deactivate
```

### Why one-at-a-time (`--all` is risky)

If plugin 4 of 12 fatals during a `--all` update, you're stuck with 3 updated and 9 on old versions — a mixed state that's hard to reason about. Looping gives you clean failure isolation.

### Rollback after white-screen-of-death

```bash
# Force-deactivate all plugins
mv wp-content/plugins wp-content/plugins.broken
cp -r /var/backups/site/plugins-<ts> wp-content/plugins

# Restore DB if schema was touched
wp db import db-snapshots/prod-<ts>-pre-update.sql
```

### Version-pin downgrade

```bash
wp plugin install <slug> --version=X.Y.Z --force
```

Reverts a specific plugin to a known version.

### Core updates

```bash
wp core check-update          # see what would happen
wp core update --minor        # minor version only (safer)
```

Major-version bumps: test on staging first. No dry-run. No shortcuts.

---

## 7. Auth / permission discipline

### Why `sudo -u www-data` beats `--allow-root`

- Files written match webserver ownership → later reads/writes work
- Compromised session can't modify system files, install packages, or bind privileged ports
- Matches what WP itself does in normal operation

### `--allow-root` warnings

WP-CLI warns for good reason. Only appropriate in:
- Containers where root IS the site user
- Specific automation where file ownership is handled externally

### Check session capabilities

```bash
sudo -u www-data whoami
sudo -u www-data id
sudo -u www-data touch /var/www/site/.test && rm /var/www/site/.test
sudo -u www-data wp cli info
```

---

## 8. Logging & auditability

Minimal pattern:

```bash
LOG=.claude/ops.log
CMD="wp db import /tmp/prod-dump.sql"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$USER@$(hostname)] $CMD" >> "$LOG"
eval "$CMD" 2>&1 | tee -a "$LOG"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) exit=$?" >> "$LOG"
```

Richer pattern (captures rollback info):

```bash
SNAP=$(wp db export --porcelain)
echo "$(date -u +%FT%TZ) snapshot=$SNAP pre=$CMD" >> "$LOG"
```

**Log**: timestamp (UTC), actor, target env/URL, command, exit code, snapshot path, rollback cmd if any.

**Don't log**: passwords, search-replace patterns that might contain secrets, API tokens.

**Correlation with git**: after a significant op, `git commit --allow-empty -m "ops: <description> (snapshot: <file>)"` makes the timeline searchable.

---

## 9. The destructive-op checklist

Before executing ANY destructive command on a remote site, walk through:

1. **Target is what I think?** → `wp option get siteurl` + `wp cli info`
2. **Snapshot taken?** → `wp db export db-snapshots/<env>-<ts>-<reason>.sql --add-drop-table`
3. **Snapshot stored outside webroot?** → Check path
4. **Dry-run where possible?** → `--dry-run`, or simulate
5. **User has seen the exact command and approved?** → Pause for confirmation
6. **Rollback command noted?** → State it explicitly
7. **Maintenance mode appropriate?** → Activate if op exceeds ~30s
8. **Log entry written?** → `echo "..." >> ops.log`
9. **Run it.**
10. **Post-op verification.** → `wp option get siteurl`, spot-check URLs
11. **Maintenance mode off?** → Deactivate
12. **Log exit code.**

This list is long; use it anyway. Every skipped step is a potential failure mode.
