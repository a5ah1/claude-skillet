#!/usr/bin/env bash
# clone-down.sh — clone a remote WordPress DB + uploads to a local dev site,
# with safety mu-plugin drop and sanitization baked in.
#
# This script assumes:
#   - Local WordPress install is already set up (wp-config.php exists)
#   - You have SSH access to the source
#   - You have sudo + www-data on local
#
# Usage:
#   clone-down.sh \
#       --source-ssh <host> \
#       --source-path <remote-wp-root> \
#       --source-url <https://prod.example.com> \
#       --local-path <local-wp-root> \
#       --local-url <http://local.test> \
#       [--uploads]                       (also rsync uploads)
#       [--mu-plugin-template <path>]     (default: $SKILL_DIR/templates/00-local-safety.php)
#       [--skip-scrub]                    (don't scrub user PII — rarely appropriate)
#
# Example:
#   clone-down.sh \
#       --source-ssh prod-host \
#       --source-path /var/www/site.com \
#       --source-url https://site.com \
#       --local-path /var/www/site.test \
#       --local-url http://site.test \
#       --uploads

set -euo pipefail

SRC_SSH=""
SRC_PATH=""
SRC_URL=""
LOCAL_PATH=""
LOCAL_URL=""
UPLOADS=0
MU_TEMPLATE=""
SKIP_SCRUB=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MU_TEMPLATE="$SCRIPT_DIR/../templates/00-local-safety.php"

usage() { grep '^#' "$0" | head -25; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-ssh) SRC_SSH="$2"; shift 2 ;;
        --source-path) SRC_PATH="$2"; shift 2 ;;
        --source-url) SRC_URL="$2"; shift 2 ;;
        --local-path) LOCAL_PATH="$2"; shift 2 ;;
        --local-url) LOCAL_URL="$2"; shift 2 ;;
        --uploads) UPLOADS=1; shift ;;
        --mu-plugin-template) MU_TEMPLATE="$2"; shift 2 ;;
        --skip-scrub) SKIP_SCRUB=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown: $1" >&2; usage ;;
    esac
done

[[ -z "$SRC_SSH" || -z "$SRC_PATH" || -z "$SRC_URL" || -z "$LOCAL_PATH" || -z "$LOCAL_URL" ]] && usage

MU_TEMPLATE="${MU_TEMPLATE:-$DEFAULT_MU_TEMPLATE}"
[[ ! -f "$MU_TEMPLATE" ]] && { echo "MU plugin template not found: $MU_TEMPLATE" >&2; exit 2; }

# Confirmation
echo "About to clone:"
echo "  FROM: $SRC_SSH:$SRC_PATH ($SRC_URL)"
echo "  TO:   $LOCAL_PATH ($LOCAL_URL)"
echo "  This will RESET the local DB. All local content will be replaced."
read -p "Proceed? [y/N] " ans
[[ "$ans" != "y" ]] && { echo "Aborted."; exit 0; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"

# 1. Export prod DB
echo "=== 1. Export source DB ==="
ssh "$SRC_SSH" "sudo -u www-data wp --path=$SRC_PATH db export /tmp/prod-dump-$TS.sql --add-drop-table"
scp "$SRC_SSH:/tmp/prod-dump-$TS.sql" "/tmp/prod-dump-$TS.sql"
ssh "$SRC_SSH" "rm /tmp/prod-dump-$TS.sql"

# 2. Reset + import local
echo "=== 2. Reset local DB and import ==="
sudo -u www-data wp --path="$LOCAL_PATH" db reset --yes
sudo -u www-data wp --path="$LOCAL_PATH" db import "/tmp/prod-dump-$TS.sql"

# 3. CRITICAL: drop safety mu-plugin BEFORE anything else hits the clone
echo "=== 3. Install safety mu-plugin (kills outbound email) ==="
MU_DIR="$LOCAL_PATH/wp-content/mu-plugins"
sudo mkdir -p "$MU_DIR"
sudo cp "$MU_TEMPLATE" "$MU_DIR/00-local-safety.php"
sudo chown www-data:www-data "$MU_DIR/00-local-safety.php"
sudo chmod 644 "$MU_DIR/00-local-safety.php"

# 4. Disable cron
echo "=== 4. Disable WP cron ==="
if ! grep -q "DISABLE_WP_CRON" "$LOCAL_PATH/wp-config.php"; then
    sudo sed -i "/\/\* That's all, stop editing/i define('DISABLE_WP_CRON', true);" "$LOCAL_PATH/wp-config.php"
fi
sudo -u www-data wp --path="$LOCAL_PATH" db query "DELETE FROM wp_options WHERE option_name = 'cron';" || true

# 5. Rewrite URLs
echo "=== 5. Search-replace URLs ==="
sudo -u www-data wp --path="$LOCAL_PATH" search-replace "$SRC_URL" "$LOCAL_URL" \
    --all-tables-with-prefix --precise --skip-columns=guid

# Gutenberg escaped-slash variant
ESCAPED_SRC="${SRC_URL//\//\\/}"
ESCAPED_DEST="${LOCAL_URL//\//\\/}"
sudo -u www-data wp --path="$LOCAL_PATH" search-replace "$ESCAPED_SRC" "$ESCAPED_DEST" \
    --all-tables-with-prefix --precise --skip-columns=guid

# 6. Scrub PII
if [[ $SKIP_SCRUB -eq 0 ]]; then
    echo "=== 6. Scrub user PII ==="
    sudo -u www-data wp --path="$LOCAL_PATH" db query "
        UPDATE wp_users
        SET user_email = CONCAT('user', ID, '@example.invalid'),
            user_pass = MD5(RAND())
        WHERE ID > 1;
    "
    sudo -u www-data wp --path="$LOCAL_PATH" db query "
        UPDATE wp_comments
        SET comment_author_email = 'commenter@example.invalid',
            comment_author_IP = '127.0.0.1';
    "
fi

# 7. Reset admin password
echo "=== 7. Reset admin (user 1) password ==="
NEWPASS="local-$(openssl rand -hex 8)"
sudo -u www-data wp --path="$LOCAL_PATH" user update 1 \
    --user_pass="$NEWPASS" \
    --user_email='dev@example.invalid'
echo ""
echo "  Admin (user 1) password: $NEWPASS"
echo "  (NOT logged — copy it now)"
echo ""

# 8. Sync uploads if requested
if [[ $UPLOADS -eq 1 ]]; then
    echo "=== 8. Sync uploads ==="
    rsync -av --delete "$SRC_SSH:$SRC_PATH/wp-content/uploads/" "/tmp/uploads-$TS/"
    sudo rm -rf "$LOCAL_PATH/wp-content/uploads"
    sudo mv "/tmp/uploads-$TS" "$LOCAL_PATH/wp-content/uploads"
    sudo chown -R www-data:www-data "$LOCAL_PATH/wp-content/uploads"
fi

# 9. Flush caches
echo "=== 9. Flush caches ==="
sudo -u www-data wp --path="$LOCAL_PATH" transient delete --all
sudo -u www-data wp --path="$LOCAL_PATH" cache flush
sudo -u www-data wp --path="$LOCAL_PATH" rewrite flush

# 10. Verify
echo "=== 10. Verification ==="
echo "Testing wp_mail (should return bool(false)):"
sudo -u www-data wp --path="$LOCAL_PATH" eval 'var_dump(wp_mail("t@example.com","t","t"));'
echo "Site URL:"
sudo -u www-data wp --path="$LOCAL_PATH" option get siteurl
echo "Admin email:"
sudo -u www-data wp --path="$LOCAL_PATH" user get 1 --field=user_email

echo ""
echo "=== Clone complete ==="
echo "Don't forget to audit plugin-specific API keys (Stripe, analytics, etc.)"
echo "Cleanup: rm /tmp/prod-dump-$TS.sql"
