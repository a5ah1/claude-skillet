#!/usr/bin/env bash
# pre-op-snapshot.sh — take a timestamped WP DB snapshot before a destructive op.
#
# Usage:
#   pre-op-snapshot.sh <env-label> <reason-slug> [--remote <ssh-host> --path <wp-path>]
#
# Examples:
#   # Local
#   pre-op-snapshot.sh local pre-search-replace
#
#   # Remote (via SSH)
#   pre-op-snapshot.sh prod pre-plugin-update \
#       --remote prod-host --path /var/www/site.com
#
# Output: prints the snapshot file path on stdout.
#
# Snapshots are stored in ./db-snapshots/ by default (relative to cwd).
# Override with SNAPSHOT_DIR env var.
# CAUTION: the snapshot dir must be OUTSIDE the webroot. Don't put it where
# nginx would serve it.

set -euo pipefail

ENV_LABEL="${1:-}"
REASON="${2:-}"

if [[ -z "$ENV_LABEL" || -z "$REASON" ]]; then
    echo "Usage: $0 <env-label> <reason-slug> [--remote <host> --path <wp-path>]" >&2
    exit 2
fi

shift 2

REMOTE=""
WP_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote) REMOTE="$2"; shift 2 ;;
        --path) WP_PATH="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

SNAPSHOT_DIR="${SNAPSHOT_DIR:-./db-snapshots}"
mkdir -p "$SNAPSHOT_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
FILENAME="${ENV_LABEL}-${TS}-${REASON}.sql"
DEST="${SNAPSHOT_DIR}/${FILENAME}"

if [[ -n "$REMOTE" ]]; then
    [[ -z "$WP_PATH" ]] && { echo "--remote requires --path" >&2; exit 2; }
    # Export on remote, then scp back
    ssh "$REMOTE" "sudo -u www-data wp --path=$WP_PATH db export /tmp/$FILENAME --add-drop-table" >&2
    scp "$REMOTE:/tmp/$FILENAME" "$DEST" >&2
    ssh "$REMOTE" "rm /tmp/$FILENAME" >&2
else
    # Local snapshot — assumes cwd has wp-config.php or adjust with $WP_PATH
    if [[ -n "$WP_PATH" ]]; then
        sudo -u www-data wp --path="$WP_PATH" db export "$DEST" --add-drop-table >&2
    else
        sudo -u www-data wp db export "$DEST" --add-drop-table >&2
    fi
fi

echo "$DEST"
