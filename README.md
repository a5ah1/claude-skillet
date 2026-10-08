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
| `tidy` | Pre-clear housekeeping — before `/clear` and a switch to unrelated work, updates memory and project docs, commits or reports the working tree, finishes or surfaces anything in flight, then confirms it's safe to clear. |
| `wp-ops` | Safe WordPress operations via WP-CLI, local or over SSH — per-project install registry, pre-op DB snapshots, cache-layer purge ordering, dual-row ACF handling, sanitized prod-to-local cloning. |
| `wrap` | End-of-session close-out — sweeps memory, project docs, working tree, lingering processes, and loose ends, then confirms it's safe to close the terminal. |

## Maintenance model

This repo is the **source of truth**. On the dev machine the skills run
straight from it:

- `scripts/link.sh` symlinks each `plugins/<name>/skills/<name>` into
  `~/.claude/skills/`, so edits here are live immediately and pushing is what
  publishes. Re-run it after adding a plugin; it never overwrites a real
  directory.
- `scripts/link.sh adopt <name>` brings a local-only skill into the repo:
  moves it into `plugins/`, scaffolds its manifest, links it back, and runs
  the privacy check.
- Everything here is public once pushed, so skills hold no machine-local
  private details — those belong in per-project files.
- The dev machine doesn't install this marketplace, to avoid loading every
  skill twice. Other machines do, and never edit their installed copies —
  they are overwritten on every marketplace update.
- `scripts/privacy-check.sh` must pass before any push (wired up as a
  pre-push hook via `git config core.hooksPath .githooks`). It scans tracked
  files for private hostnames, identities, emails, IPs, and secrets;
  personal patterns live in the gitignored `.private-patterns`.
- `archive/` (gitignored, dev machine only) parks retired skills and
  backups.
