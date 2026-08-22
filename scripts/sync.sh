#!/usr/bin/env bash
# One-way sync: ~/.claude/skills (source of truth, dev machine) → plugins/.
# Never edit skill content inside this repo directly — improve the live skill,
# then re-run this script. Ends with the privacy check.
#
# Usage: sync.sh [skill ...]   (no args = the full roster below)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
SKILLS=(wp-ops lucide-icons wrap primer-colors glass-ui)
if (( $# )); then
    SKILLS=("$@")
fi

for s in "${SKILLS[@]}"; do
    src="$SKILLS_DIR/$s"
    if [[ ! -d "$src" ]]; then
        echo "SKIP    $s (not found in $SKILLS_DIR)"
        continue
    fi
    dest="plugins/$s/skills/$s"
    mkdir -p "$dest"
    rsync -a --delete "$src/" "$dest/"
    echo "SYNCED  $s"

    manifest="plugins/$s/.claude-plugin/plugin.json"
    if [[ ! -f "$manifest" ]]; then
        mkdir -p "plugins/$s/.claude-plugin"
        cat > "$manifest" <<EOF
{
  "name": "$s",
  "description": "TODO: one-line description",
  "author": { "name": "a5ah1", "url": "https://github.com/a5ah1" }
}
EOF
        echo "CREATED $manifest — fill in the description"
    fi
    if ! grep -q "\"name\": \"$s\"" .claude-plugin/marketplace.json; then
        echo "TODO    $s is not listed in .claude-plugin/marketplace.json yet"
    fi
done

echo
echo "Review with: git status && git diff"
exec scripts/privacy-check.sh
