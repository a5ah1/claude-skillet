---
name: tidy
description: Pre-clear housekeeping. Use when the user says /tidy, "I'm about to clear", "prepare for /clear", "clearing context", "switching tasks", "starting something else now", or otherwise signals they are about to clear the context and move to unrelated work. Not for ending the session (that is wrap) and not for tidying code or files.
---

# Before the context is cleared

The user is about to run `/clear` and start something unrelated. The terminal
stays open, but this conversation will be gone: the next turn will know only
what memory, CLAUDE.md, and the repo say. Nobody warns the agent before a
clear, which is how memory goes stale and half-finished work gets left for a
future session to rediscover. Sweep for exactly that.

- **Memory** — persist what this session taught that isn't already recorded
  (preferences, corrections, project state, decisions and their why). Fix or
  delete entries this session proved wrong. If memory is already current, say
  so; don't invent a low-value entry.
- **Project docs** — if the session changed how the project works, make sure
  CLAUDE.md and project docs say so.
- **Working tree** — commit real work or say what is deliberately left
  uncommitted, so the next task doesn't inherit unrelated changes in
  `git status`. Remove scratch files that landed in the project.
- **In flight** — background subagents, loops, or promises made earlier
  ("I'll do X later"). Finish them or surface them; a subagent's result has
  nowhere to land once the context is gone.

Leave dev servers and other processes running: the session continues, and
`wrap` handles those at the end. Close with a two-line note of what changed,
then **"Safe to clear."** — or "Not yet:" with what remains.
