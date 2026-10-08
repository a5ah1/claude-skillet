#!/usr/bin/env bash
# Symlink every plugin's skill into ~/.claude/skills, so this repo is the copy
# Claude Code loads on the dev machine. Edit skills here; pushing publishes.
# Safe to re-run: existing correct links are left alone, nothing is overwritten.
#
# Usage: link.sh                link (or verify) every plugin in plugins/
#        link.sh adopt <name>   move a local-only ~/.claude/skills/<name> into
#                               plugins/, scaffold its manifest, and link it back
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
status=0

link_one() {
    local s=$1
    local target="$REPO/plugins/$s/skills/$s" dest="$SKILLS_DIR/$s"
    if [[ ! -f "$target/SKILL.md" ]]; then
        echo "MISSING $s — expected plugins/$s/skills/$s/SKILL.md"
        status=1
        return
    fi
    if [[ -L "$dest" ]]; then
        if [[ "$(readlink "$dest")" == "$target" ]]; then
            echo "OK      $s"
        else
            echo "WRONG   $s → $(readlink "$dest") (expected $target)"
            status=1
        fi
    elif [[ -e "$dest" ]]; then
        echo "BLOCKED $s — $dest is a real directory; diff it against the repo, then move it aside"
        status=1
    else
        ln -s "$target" "$dest"
        echo "LINKED  $s"
    fi
    if ! grep -q "\"name\": \"$s\"" .claude-plugin/marketplace.json; then
        echo "TODO    $s is not listed in .claude-plugin/marketplace.json yet"
    fi
}

adopt() {
    local s=$1
    local src="$SKILLS_DIR/$s" manifest="plugins/$s/.claude-plugin/plugin.json"
    if [[ ! -d "$src" || -L "$src" ]]; then
        echo "$src is not a local skill directory" >&2
        exit 1
    fi
    if [[ -e "plugins/$s" ]]; then
        echo "plugins/$s already exists" >&2
        exit 1
    fi
    mkdir -p "plugins/$s/skills" "plugins/$s/.claude-plugin"
    mv "$src" "plugins/$s/skills/$s"
    cat > "$manifest" <<EOF
{
  "name": "$s",
  "description": "TODO: one-line description",
  "author": { "name": "a5ah1", "url": "https://github.com/a5ah1" }
}
EOF
    echo "ADOPTED $s — fill in $manifest and add it to the README table"
    link_one "$s"
}

if [[ "${1:-}" == adopt ]]; then
    adopt "${2:?usage: link.sh adopt <name>}"
    echo
    echo "Review with: git status && git diff"
    exec scripts/privacy-check.sh
fi

for dir in plugins/*/; do
    link_one "$(basename "$dir")"
done

# Links left behind by plugins that were removed or renamed
for link in "$SKILLS_DIR"/*; do
    if [[ -L "$link" && "$(readlink "$link")" == "$REPO/plugins/"* && ! -e "$link" ]]; then
        echo "STALE   $(basename "$link") → $(readlink "$link") (remove the link)"
        status=1
    fi
done

exit $status
