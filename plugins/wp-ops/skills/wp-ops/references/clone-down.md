# Cloning Prod → Local (Safely)

This is the most dangerous routine in the skill. The up-direction (local → staging) is generally safe — staging is disposable. **The down-direction is where real damage happens**: the cloned DB still has real user emails, live SMTP credentials, real payment API keys, real cron jobs that fire outbound requests on the first page load.

Never skip the sanitization steps. Do them in order.

---

## The sequence

### 1. Export prod DB

```bash
ssh prod 'sudo -u www-data wp --path=/var/www/prod db export /tmp/prod-dump.sql --add-drop-table'
scp prod:/tmp/prod-dump.sql ./
ssh prod 'rm /tmp/prod-dump.sql'
```

### 2. Import into local (or staging-as-dev)

```bash
sudo -u www-data wp --path=/var/www/site.test db reset --yes
sudo -u www-data wp --path=/var/www/site.test db import prod-dump.sql
```

### 3. **CRITICAL: drop the safety mu-plugin BEFORE anything else**

Before any URL rewrite, before WordPress bootstraps fully from the clone, before any cron or admin-init hook fires — kill outbound email.

```bash
sudo cp ~/wp-ops/templates/00-local-safety.php \
    /var/www/site.test/wp-content/mu-plugins/00-local-safety.php
sudo chown www-data:www-data /var/www/site.test/wp-content/mu-plugins/00-local-safety.php
```

The `00-` prefix makes it load first among mu-plugins. The mu-plugin kills `wp_mail` via `pre_wp_mail` filter AND corrupts PHPMailer SMTP config as a belt-and-suspenders measure.

**Why this must come first**: if you run `wp search-replace` before the mu-plugin is in place, any plugin that hooks `save_post` or `init` and fires emails (order confirmations, admin notifications, Akismet spam reports) could send from the clone with real SMTP creds.

### 4. Disable cron

Edit `wp-config.php`:
```php
define('DISABLE_WP_CRON', true);
```

Then clear the queue:
```bash
sudo -u www-data wp --path=/var/www/site.test cron event delete --all --due-now
# or to clear everything (including future):
sudo -u www-data wp --path=/var/www/site.test db query \
    "DELETE FROM wp_options WHERE option_name = 'cron';"
```

### 5. Rewrite URLs

```bash
sudo -u www-data wp --path=/var/www/site.test search-replace \
    'https://prod-domain.com' 'http://site.test' \
    --all-tables-with-prefix \
    --precise \
    --skip-columns=guid \
    --dry-run
```

Inspect output, then rerun without `--dry-run`.

**Then a second pass for Gutenberg's escaped slashes**:

```bash
sudo -u www-data wp --path=/var/www/site.test search-replace \
    'https:\/\/prod-domain.com' 'http:\/\/site.test' \
    --all-tables-with-prefix \
    --precise \
    --skip-columns=guid
```

### 6. Scrub user PII

Choice of approaches:

**Option A — 10up's wp-scrubber** (most thorough):
```bash
sudo -u www-data wp --path=/var/www/site.test plugin install wp-scrubber --activate
sudo -u www-data wp --path=/var/www/site.test scrub all
```

Scrubs users + comments per WP core schema. Refuses to run if env looks like prod.

**Option B — DIY scrub** (lightweight, no plugin):
```bash
sudo -u www-data wp --path=/var/www/site.test db query "
    UPDATE wp_users
    SET user_email = CONCAT('user', ID, '@example.invalid'),
        user_pass = MD5(RAND())
    WHERE ID > 1;
"

sudo -u www-data wp --path=/var/www/site.test db query "
    UPDATE wp_comments
    SET comment_author_email = 'commenter@example.invalid',
        comment_author_IP = '127.0.0.1';
"
```

**Option C — hoppinger/wp-cli-anonymize-command**: adds `wp anonymize` command for similar scrubbing.

Whichever approach, know that **none of these handle plugin PII**: third-party user meta, WooCommerce order tables, form plugin submissions, etc. Audit manually for anything sensitive the site stores.

### 7. Reset admin password

```bash
NEWPASS="local-$(openssl rand -hex 8)"
sudo -u www-data wp --path=/var/www/site.test user update 1 \
    --user_pass="$NEWPASS" \
    --user_email='dev@example.invalid'
echo "Admin password reset to: $NEWPASS"
```

Never commit the generated password. Never use a predictable password here — some dev setups accidentally expose the local site.

### 8. Null out API keys for external services

Depends on what plugins are installed. Common ones:

```bash
# Stripe — set to test mode
wp option update stripe_mode test
wp option delete stripe_secret_key
wp option delete stripe_publishable_key

# WooCommerce — set to test/sandbox mode for gateways
wp option update woocommerce_default_country 'US'  # match test address

# SMTP plugins
wp plugin deactivate wp-mail-smtp easy-wp-smtp

# Analytics
wp plugin deactivate google-site-kit monsterinsights

# Backup plugins (will try to connect to external storage)
wp plugin deactivate updraftplus backupbuddy
```

For ACF-stored API keys:
```bash
sudo -u www-data wp --path=/var/www/site.test eval "
    update_field('stripe_api_key', '', 'option');
    update_field('mailchimp_api_key', '', 'option');
"
```

### 9. Deactivate plugins that phone home

These call external services even just on admin page loads:

```bash
sudo -u www-data wp --path=/var/www/site.test plugin deactivate \
    akismet \
    jetpack \
    wordfence \
    updraftplus \
    mainwp-child \
    google-site-kit
```

Add project-specific offenders as discovered.

### 10. Sync uploads (if needed)

```bash
rsync -av --delete prod:/var/www/prod/wp-content/uploads/ /tmp/uploads-clone/
sudo rm -rf /var/www/site.test/wp-content/uploads
sudo mv /tmp/uploads-clone /var/www/site.test/wp-content/uploads
sudo chown -R www-data:www-data /var/www/site.test/wp-content/uploads
```

### 11. Flush all caches on the clone

```bash
sudo -u www-data wp --path=/var/www/site.test transient delete --all
sudo -u www-data wp --path=/var/www/site.test cache flush
sudo -u www-data wp --path=/var/www/site.test rewrite flush
```

### 12. Verify sanitization worked

```bash
# Confirm email is dead
sudo -u www-data wp --path=/var/www/site.test eval "var_dump(wp_mail('test@example.com','test','test'));"
# Should print: bool(false)

# Confirm cron is dead
sudo -u www-data wp --path=/var/www/site.test cron event list
# Should be empty or throw an error

# Confirm URLs rewrote
sudo -u www-data wp --path=/var/www/site.test option get siteurl
# Should be http://site.test, not prod

# Confirm admin email changed
sudo -u www-data wp --path=/var/www/site.test user get 1 --field=user_email
# Should be dev@example.invalid, not a real address
```

### 13. Smoke-test

```bash
curl -I http://site.test/
# Should 200

# Log in via browser with the new admin password, click around
```

---

## Common pitfalls

| Pitfall | Consequence | Prevention |
|---------|-------------|------------|
| Run search-replace before mu-plugin in step 3 | Real email sent from clone with real SMTP creds | Do step 3 FIRST, always |
| Skip step 4 (cron) | Cron job on first page load fires outbound webhook | `DISABLE_WP_CRON = true` in wp-config.php |
| Forget `--precise` on search-replace | Serialized/escaped content doesn't update | Always `--precise` |
| Skip step 8 (API keys) | Admin dashboard shows live prod analytics, or test transactions hit real gateways | Audit plugins, null the keys |
| Skip step 11 (cache flush) | Clone shows stale admin-side cached content | Flush all three |
| Use predictable admin password | Dev site leaks via port forward | Use `openssl rand` |

---

## If the clone IS staging, not local

Same steps, except:
- Step 1 is `wp db export` on prod, step 2 is `wp db import` on staging (no local round-trip if staging is on the same server)
- Step 5 rewrites to staging domain, not `.test`
- Step 10 rsyncs between server paths, not down to local
- SSL / certificate setup is real — no `http://`

Critically, the mu-plugin, cron disable, and API-key nulling steps **all still apply**. Staging is a smaller target than prod but still capable of sending real emails, firing real webhooks, and leaking real user data. Treat it the same way.

---

## Reverse direction (local → prod)

Entirely different operation — mostly about not overwriting prod's real content. Only the theme files and select options (never `wp_posts` or `wp_users`) should move up. If you're about to do a full local→prod DB push, you almost certainly should be pushing content via migration scripts instead.

This file covers prod→local only. For content migration going UP, the pattern is:
- Dev in local
- Test on staging (which may be a clone of prod, but write-limited)
- Promote specific posts/options/files to prod via targeted `wp post create`, `wp option update`, or WXR export/import

Bulk `local → prod` DB copies are almost always the wrong tool.
