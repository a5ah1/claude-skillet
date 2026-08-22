#!/usr/bin/env bash
# Pre-publish privacy scan. Fails (exit 1) if any tracked file contains
# private hostnames, identities, email addresses, IPs, or secret material.
# Personal patterns live in .private-patterns (gitignored — never commit it),
# one case-insensitive substring per line, # for comments.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

hits=0
report() {
    printf 'PRIVATE-INFO HIT (%s):\n%s\n\n' "$1" "$2"
    hits=1
}

# 1. Personal patterns
if [[ -f .private-patterns ]]; then
    while IFS= read -r pat; do
        [[ -z "$pat" || "$pat" == \#* ]] && continue
        out=$(git grep -inF "$pat" 2>/dev/null || true)
        [[ -n "$out" ]] && report "pattern: $pat" "$out"
    done < .private-patterns
else
    echo "WARNING: .private-patterns missing — personal pattern scan skipped." >&2
fi

# 2. Email addresses (GitHub noreply and example domains are allowed)
out=$(git grep -inE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' \
    | grep -viE 'users\.noreply\.github\.com|example\.(com|org|net)' || true)
[[ -n "$out" ]] && report "email address" "$out"

# 3. IPv4 addresses (loopback and documentation ranges are allowed)
out=$(git grep -inE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -vE '127\.0\.0\.1|0\.0\.0\.0|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.' || true)
[[ -n "$out" ]] && report "IP address" "$out"

# 4. Key material and token shapes
out=$(git grep -inE 'BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}' || true)
[[ -n "$out" ]] && report "secret/key material" "$out"

if (( hits )); then
    echo "Privacy check FAILED — scrub the findings above before pushing."
    echo "(False positive? Adjust the exclusions in scripts/privacy-check.sh.)"
    exit 1
fi
echo "Privacy check passed."
