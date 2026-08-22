# claude-skillet

A personal [Claude Code](https://code.claude.com) plugin marketplace. Each skill
is packaged as its own plugin so it can be installed and toggled independently.

## Install

```
/plugin marketplace add a5ah1/claude-skillet
/plugin install <name>@claude-skillet
```

Manage with `/plugin` (enable, disable, uninstall). Pull updates with
`/plugin marketplace update claude-skillet` — plugins omit the `version`
field, so every pushed commit propagates without version bumps.

## Skills

_None published yet — first batch (wp-ops, lucide-icons, wrap, primer-colors)
is being prepared._

## Maintenance model

This repo is a **publish mirror**, not a working copy:

- The source of truth is `~/.claude/skills/` on the dev machine, where the
  skills run live as personal skills.
- `scripts/sync.sh` copies them one-way into `plugins/`, then runs the
  privacy check. Never edit skill content here directly.
- Never edit installed plugin copies on consuming machines either — they are
  overwritten on every marketplace update.
- `scripts/privacy-check.sh` must pass before any push (wired up as a
  pre-push hook via `git config core.hooksPath .githooks`). It scans tracked
  files for private hostnames, identities, emails, IPs, and secrets;
  personal patterns live in the gitignored `.private-patterns`.
- `archive/` (gitignored, dev machine only) parks retired skills.
