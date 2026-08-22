# Cache Invalidation on Cached WordPress Sites

Production WordPress usually sits behind multiple cache layers. Each layer has its own purge command; none covers the others. This file covers ordering, per-layer specifics, and how to diagnose "why is the old version still showing."

## The layers

From closest-to-PHP outward to the client:

1. **PHP opcache** — per-FPM-worker, caches compiled PHP
2. **WordPress object cache** — in-process `WP_Object_Cache` or persistent (Redis/Memcached)
3. **WordPress transients** — DB-backed (or object-cache-backed with persistent backend)
4. **WordPress rewrite rules** — option-stored; regenerated with `wp rewrite flush`
5. **Origin page cache** — nginx FastCGI cache, Varnish, or similar
6. **CDN** — Cloudflare, Fastly, CloudFront
7. **Browser** — user's problem, but affects your testing

## Purge ordering: inside-out

**Rule**: purge from the layer closest to PHP outward. Each outer layer, on its next miss, refills from the layer beneath it — that layer must already be fresh.

The failure mode when you reverse the order: purge CDN first, it immediately refills from the still-stale origin cache, and now you're back to square one with a 24-hour TTL ahead of you.

Canonical sequence after a code-affecting deploy:

1. **Opcache reset** so PHP-FPM executes new code
2. **WP caches** (`wp cache flush`, transients, rewrite rules if relevant)
3. **Origin page cache** (FastCGI / Varnish)
4. **CDN** (Cloudflare)
5. **Verify** with curl + cache-status headers

---

## 1. PHP opcache

Opcache caches compiled PHP bytecode per-FPM-worker. After a theme/plugin PHP change, opcache may still serve the old bytecode until `revalidate_freq` expires (default 2s on Ubuntu, often bumped to 60–180s on production).

**Reset options**:

- **`sudo systemctl reload php-fpm`** (or `php8.3-fpm`, etc.) — graceful. Worker pool rolls over; opcache clears. Can cause brief 502s on in-flight requests — usually invisible on moderate traffic.
- **`opcache_reset()` from a web-hit endpoint** — requires a PHP file accessible only from localhost. Avoids the reload pause.
- **`php -r 'opcache_reset();'` from CLI** — **does NOT work** for FPM's opcache. CLI and FPM have separate opcache instances.

For most sites, `systemctl reload php-fpm` is the right tool.

---

## 2. WordPress caches

```bash
# Object cache (Redis/Memcached backends; no-op on sites without persistent cache)
wp cache flush

# DB-backed transients
wp transient delete --all

# Rewrite rules (regenerates option)
wp rewrite flush [--hard]
```

- **`wp cache flush`** affects the object cache. On a site without a persistent backend (Redis/Memcached), it's effectively a no-op — the "cache" only lives for one request. On a site WITH a persistent backend, it nukes EVERY site's cache on multisite.
- **Transients** live in `wp_options` when no object cache is active, or in the object cache when there is one. `wp transient delete --all` handles both. Needed when:
  - ACF field-group schema changed
  - Plugin data shape changed
  - Menu/permalink structure changed
  - Stale nav HTML is in transients (common cause of "nav still wrong")
- **`wp rewrite flush`** — needed after custom post type / taxonomy / permalink changes. `--hard` additionally writes `.htaccess` (Apache only, single-site only).

**WordPress does NOT auto-purge nginx or Cloudflare.** Unless you have the Nginx Helper plugin or Cloudflare plugin wired in, assume page caches are stale until you explicitly purge.

---

## 3. Origin page cache (nginx FastCGI)

Common configurations:

### Purge via HTTP endpoint

If the nginx config includes the `fastcgi_cache_purge` directive (via `ngx_cache_purge` module):

```nginx
location ~ /purge(/.*) {
    allow 127.0.0.1;
    deny all;
    fastcgi_cache_purge SITE "$scheme$request_method$host$1";
}
```

Purge a specific URL from the server:
```bash
curl -X GET "http://127.0.0.1/purge/technology/" -H "Host: example.com"
```

(Host header must match the cached key.)

### Purge by deleting files

Nuclear but reliable:
```bash
sudo rm -rf /var/cache/nginx/<zone>/*
```

Safe — the directory contains only cache files. Optionally follow with `sudo systemctl reload nginx`.

### Bypass without purging (for testing)

Most FastCGI configs bypass cache for:
- Query strings (`$query_string != ""`)
- `wordpress_logged_in_*` cookies
- `wp-postpass_*` cookies
- `comment_author_*` cookies
- `wordpress_no_cache` cookie

Forcing a MISS without invalidation:
```bash
curl 'https://example.com/?nocache=1'
curl -H 'Cookie: wordpress_no_cache=1' 'https://example.com/'
```

### Cache-status header

Most setups expose `X-FastCGI-Cache: HIT|MISS|BYPASS|EXPIRED|UPDATING`. If not exposed, add `add_header X-FastCGI-Cache $upstream_cache_status;` in the nginx config.

---

## 4. Cloudflare

### Purge options (ordered by surgical precision)

```bash
# By URL (most surgical)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE/purge_cache" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"files":["https://example.com/path/"]}'

# By prefix (up to 30 prefixes, max 31 path separators each)
... -d '{"prefixes":["example.com/technology/"]}'

# By hostname
... -d '{"hosts":["example.com"]}'

# Everything (last resort — thundering herd)
... -d '{"purge_everything":true}'
```

**Notes**:
- Purge by URL must include scheme and match cached key exactly. Query-string variants need separate purge requests.
- Purge by prefix caps at 30 entries per call.
- Purge by cache-tag requires Enterprise plan on most zones — don't plan around it without confirming.
- **Rate limits**: Free ~5 req/min (25 bucket), higher tiers higher. URL/tag/prefix share 30,000/24h with up to 30 items per call.

### Development Mode

```bash
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE/settings/development_mode" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"value":"on"}'
```

3-hour bypass of the edge cache. Useful for diagnosing "is it CDN or origin?" — not a substitute for purging, and should never be left on.

---

## Deploy sequence (complete)

For a code change affecting PHP (theme/plugin deploy):

```bash
# 1. Rsync to server (via a staging dir + atomic move)
rsync -av --delete theme/ host:/tmp/theme-deploy/
ssh host 'sudo rsync -av --delete /tmp/theme-deploy/ /var/www/site/wp-content/themes/theme/ \
    && sudo chown -R www-data:www-data /var/www/site/wp-content/themes/theme/'

# 2. Reset opcache
ssh host 'sudo systemctl reload php8.3-fpm'

# 3. WP caches (only if relevant — harmless if not)
ssh host 'sudo -u www-data wp --path=/var/www/site cache flush'
ssh host 'sudo -u www-data wp --path=/var/www/site transient delete --all'  # only if schema/menu changed
ssh host 'sudo -u www-data wp --path=/var/www/site rewrite flush'           # only if permalinks changed

# 4. Origin page cache (FastCGI)
ssh host 'sudo rm -rf /var/cache/nginx/<zone>/*'

# 5. CDN (Cloudflare) — if the change affects cached URLs
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE/purge_cache" \
    -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
    -d '{"files":["https://example.com/","https://example.com/affected-page/"]}'
```

**Skip step 5 entirely** if the change is CSS/JS and cache-busted by filename or query string — the new filename is a different cache key.

---

## Content-update scenarios

| Change | Caches to purge |
|--------|-----------------|
| Post edited in wp-admin | Origin page cache (the post's URL + archives that embed it) + CDN for same URLs |
| ACF field *value* change | Same as post edit |
| ACF field *group* (schema) change | `wp cache flush` + `wp transient delete --all`; if nav-related, purge every page |
| `wp option update` | Depends — purge pages that render that option's output |
| New post published | CDN on home/feed/archive URLs (WP may auto-purge archives via Nginx Helper if configured) |

**WordPress admin** invalidates its own object-cache keys on save but cannot reach FastCGI or Cloudflare. Unless you have a WordPress→CDN integration plugin, content changes require manual purge.

---

## Diagnosis: "why is the old version still showing"

Work outward from the browser. Each step isolates one layer.

### Step 1: Rule out the browser

Hard-reload or `curl -sI https://example.com/path/` to remove the browser from the equation. If curl shows new content and browser shows old, clear browser cache.

### Step 2: CDN?

```bash
curl -sI https://example.com/path/ | grep -i cf-cache-status
```

Values:
- `HIT` → Cloudflare is serving stale. Purge it.
- `MISS` → CF asked origin. Problem is upstream.
- `DYNAMIC` → CF didn't try to cache (saw `Set-Cookie`, short `Cache-Control`, etc.). Origin-driven — check origin response headers.
- `BYPASS` → CF saw a cache-disabling header/cookie. Check `Cache-Control` and `Set-Cookie` from origin.
- `EXPIRED` / `REVALIDATED` → CF asked origin and origin said unchanged. Origin is stale.

### Step 3: Origin page cache?

```bash
curl -sI https://example.com/path/ | grep -i x-fastcgi-cache
```

Values:
- `HIT` → FastCGI serving stale. Purge it.
- `MISS` → FastCGI asked PHP. Problem is in WP/opcache.
- `BYPASS` → `$skip_cache` fired (cookie, query string, admin URL). Expected if you're logged in or using `?foo=bar`.

### Step 4: Opcache?

If rendered HTML still reflects old PHP code after FastCGI shows MISS on fresh requests, opcache hasn't picked up the new bytecode. Reload PHP-FPM.

### Step 5: WordPress itself?

Force WP to render past its own caches:

```bash
curl -sI -H 'Cookie: wordpress_no_cache=1' https://example.com/path/
```

Compare to a plain request. If this shows new content and plain doesn't, it's FastCGI/CDN holding old content. If this also shows old content, it's WP-level (object cache, transients, opcache, or the PHP code itself hasn't changed).

### Step 6: Stale transients?

Suspect when:
- Nav looks wrong on a freshly-rendered page
- ACF-driven blocks show old values
- Menu items disappeared or appeared duplicated

```bash
wp transient delete --all
```

### Step 7: Check response headers for cache-disabling signals

```bash
curl -sI https://example.com/path/ | grep -iE 'set-cookie|cache-control|vary|x-robots-tag'
```

Any of these can make CDN/origin mark a response as uncacheable. Common culprits:
- Session plugin setting `Set-Cookie` on unauthenticated pages
- `Cache-Control: private, no-cache` from WordPress admin bar logic
- `Vary: Cookie` matching any request-side cookie

---

## Authenticated Origin Pull caveat

If the origin enforces Cloudflare Authenticated Origin Pull (`ssl_verify_client on`), you **cannot** curl the origin directly from your laptop — TLS handshake fails without a Cloudflare-signed client cert.

Testing options:
- Hit staging or preview (usually no AOP)
- SSH to the box and `curl` from there (even from 127.0.0.1, AOP will still fail unless you temporarily relax `ssl_verify_client optional` — don't)
- Temporarily enable Cloudflare Development Mode to bypass edge cache and test the round-trip

---

## Quick header cheatsheet

| Header | What it tells you |
|--------|-------------------|
| `cf-cache-status: HIT` | Cloudflare served from edge |
| `cf-cache-status: MISS` | Cloudflare fetched from origin |
| `cf-cache-status: DYNAMIC` | Cloudflare didn't cache (origin said so) |
| `cf-cache-status: BYPASS` | Cloudflare bypassed due to config |
| `x-fastcgi-cache: HIT` | Origin served from FastCGI cache |
| `x-fastcgi-cache: MISS` | Origin rendered via PHP |
| `x-fastcgi-cache: BYPASS` | Origin skipped cache (cookie/query/admin) |
| `age: N` | Seconds since fetched from origin (CDN) |
| `x-cache: HIT` / `x-cache: MISS` | Generic CDN cache status |

Add `curl -D - <url> -o /dev/null -s` to dump all headers.
