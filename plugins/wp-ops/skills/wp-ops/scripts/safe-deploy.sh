#!/usr/bin/env bash
# safe-deploy.sh — rsync a theme or plugin to a remote WP site with the full
# cache-layer flush sequence afterward.
#
# Usage:
#   safe-deploy.sh \
#       --src <local-path/> \
#       --dest <remote:/absolute/path/> \
#       --ssh <host-alias> \
#       --wp-path <remote-wp-root> \
#       [--php-fpm <service-name>]       (default: php8.3-fpm)
#       [--fastcgi-cache-dir <path>]     (if set, wipes files)
#       [--fastcgi-purge-url <url>]      (alternative: HTTP purge endpoint)
#       [--cloudflare-zone <zone-id>]    (optional)
#       [--cloudflare-token-env CF_TOKEN] (env var name holding the token)
#       [--cloudflare-urls "url1,url2"]  (comma-separated; else purge-everything)
#       [--flush-transients]             (pass to flush DB-backed transients)
#       [--flush-rewrite]                (pass if permalinks changed)
#       [--dry-run]                       (print planned actions; don't execute)
#
# Example (production):
#   safe-deploy.sh \
#       --src mytheme/ \
#       --dest /var/www/site.com/wp-content/themes/mytheme/ \
#       --ssh prod-host \
#       --wp-path /var/www/site.com \
#       --fastcgi-cache-dir /var/cache/nginx/site.com \
#       --cloudflare-zone "$CF_ZONE_ID" \
#       --cloudflare-token-env CF_TOKEN
#
# NOTE: rsyncs via a /tmp staging dir on the remote, then sudo-moves into place.
# This avoids permissions issues with rsyncing directly to www-data-owned dirs.

set -euo pipefail

SRC=""
DEST=""
SSH_HOST=""
WP_PATH=""
PHP_FPM="php8.3-fpm"
FASTCGI_DIR=""
FASTCGI_URL=""
CF_ZONE=""
CF_TOKEN_ENV=""
CF_URLS=""
FLUSH_TRANSIENTS=0
FLUSH_REWRITE=0
DRY_RUN=0

usage() {
    grep '^#' "$0" | head -30
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src) SRC="$2"; shift 2 ;;
        --dest) DEST="$2"; shift 2 ;;
        --ssh) SSH_HOST="$2"; shift 2 ;;
        --wp-path) WP_PATH="$2"; shift 2 ;;
        --php-fpm) PHP_FPM="$2"; shift 2 ;;
        --fastcgi-cache-dir) FASTCGI_DIR="$2"; shift 2 ;;
        --fastcgi-purge-url) FASTCGI_URL="$2"; shift 2 ;;
        --cloudflare-zone) CF_ZONE="$2"; shift 2 ;;
        --cloudflare-token-env) CF_TOKEN_ENV="$2"; shift 2 ;;
        --cloudflare-urls) CF_URLS="$2"; shift 2 ;;
        --flush-transients) FLUSH_TRANSIENTS=1; shift ;;
        --flush-rewrite) FLUSH_REWRITE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown: $1" >&2; usage ;;
    esac
done

[[ -z "$SRC" || -z "$DEST" || -z "$SSH_HOST" || -z "$WP_PATH" ]] && usage

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] $*"
    else
        echo "[run] $*"
        eval "$@"
    fi
}

# 1. Rsync to /tmp on remote
STAGE_NAME="deploy-$(date -u +%Y%m%dT%H%M%SZ)-$$"
REMOTE_STAGE="/tmp/$STAGE_NAME"
echo "=== 1. Rsync to $SSH_HOST:$REMOTE_STAGE ==="
run "rsync -av --delete '$SRC' '$SSH_HOST:$REMOTE_STAGE/'"

# 2. sudo-move into place + chown
echo "=== 2. Move into place + chown ==="
run "ssh '$SSH_HOST' 'sudo rsync -av --delete $REMOTE_STAGE/ $DEST && sudo chown -R www-data:www-data $DEST && rm -rf $REMOTE_STAGE'"

# 3. Opcache reset via PHP-FPM reload
echo "=== 3. Reload PHP-FPM (opcache reset) ==="
run "ssh '$SSH_HOST' 'sudo systemctl reload $PHP_FPM'"

# 4. WP object cache flush
echo "=== 4. WP object cache flush ==="
run "ssh '$SSH_HOST' 'sudo -u www-data wp --path=$WP_PATH cache flush'"

# 5. Transients (optional)
if [[ $FLUSH_TRANSIENTS -eq 1 ]]; then
    echo "=== 5. Flush transients ==="
    run "ssh '$SSH_HOST' 'sudo -u www-data wp --path=$WP_PATH transient delete --all'"
fi

# 6. Rewrite flush (optional)
if [[ $FLUSH_REWRITE -eq 1 ]]; then
    echo "=== 6. Flush rewrite rules ==="
    run "ssh '$SSH_HOST' 'sudo -u www-data wp --path=$WP_PATH rewrite flush'"
fi

# 7. FastCGI cache
if [[ -n "$FASTCGI_DIR" ]]; then
    echo "=== 7. Wipe FastCGI cache dir $FASTCGI_DIR ==="
    run "ssh '$SSH_HOST' 'sudo rm -rf $FASTCGI_DIR/*'"
elif [[ -n "$FASTCGI_URL" ]]; then
    echo "=== 7. FastCGI purge via HTTP — caller must curl $FASTCGI_URL/<path> ==="
    echo "     (skipping — per-URL purging should be done explicitly)"
fi

# 8. Cloudflare
if [[ -n "$CF_ZONE" ]]; then
    [[ -z "$CF_TOKEN_ENV" ]] && { echo "--cloudflare-zone requires --cloudflare-token-env" >&2; exit 2; }
    TOKEN="${!CF_TOKEN_ENV:-}"
    [[ -z "$TOKEN" ]] && { echo "Env var \$$CF_TOKEN_ENV is empty" >&2; exit 2; }

    if [[ -n "$CF_URLS" ]]; then
        # Build JSON array
        IFS=',' read -ra URLS <<< "$CF_URLS"
        URLS_JSON=$(printf '"%s",' "${URLS[@]}")
        URLS_JSON="[${URLS_JSON%,}]"
        BODY="{\"files\":$URLS_JSON}"
    else
        echo "No --cloudflare-urls — would send purge_everything. Confirm with user."
        read -p "Purge Cloudflare cache for the ENTIRE zone? [y/N] " ans
        [[ "$ans" != "y" ]] && { echo "Skipping Cloudflare purge."; BODY=""; }
        [[ -n "${BODY-}" ]] || BODY='{"purge_everything":true}'
    fi

    if [[ -n "${BODY-}" ]]; then
        echo "=== 8. Cloudflare purge ==="
        run "curl -sS -X POST 'https://api.cloudflare.com/client/v4/zones/$CF_ZONE/purge_cache' \
            -H 'Authorization: Bearer $TOKEN' \
            -H 'Content-Type: application/json' \
            -d '$BODY'"
        echo
    fi
fi

echo "=== Deploy complete ==="
