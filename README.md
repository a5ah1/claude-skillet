# claude-skillet

A personal [Claude Code](https://code.claude.com) plugin marketplace. Each skill
is packaged as its own plugin so it can be installed and toggled independently.

It's called skillet because it's for cooking.

## Install

```
/plugin marketplace add a5ah1/claude-skillet
/plugin install <name>@claude-skillet
```

Manage with `/plugin` (enable, disable, uninstall). Pull updates with
`/plugin marketplace update claude-skillet` — plugins omit the `version`
field, so every pushed commit propagates without version bumps.

## Skills

| Plugin | What it does |
|--------|--------------|
| `glass-ui` | Glassmorphism / Liquid Glass-style translucent UI — calibrated opacity/blur/border values per theme and density, ambient-background requirements, performance budgets, reduced-transparency fallbacks. |
| `lucide-icons` | Lucide icon selection that never hallucinates a name — searchable index of all icons with keywords, verify-before-use workflow, vanilla JS/React/Vue/Svelte usage. |
| `primer-colors` | GitHub Primer semantic color tokens as a ready-to-paste CSS file — dark, dark-dimmed, and light themes for admin panels, internal tools, dashboards. |
| `wp-ops` | Safe WordPress operations via WP-CLI, local or over SSH — per-project install registry, pre-op DB snapshots, cache-layer purge ordering, dual-row ACF handling, sanitized prod-to-local cloning. |
| `wrap` | End-of-session close-out — sweeps memory, project docs, working tree, lingering processes, and loose ends, then confirms it's safe to close the terminal. |

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
