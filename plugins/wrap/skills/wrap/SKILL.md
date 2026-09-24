---
name: wrap
description: End-of-session close-out. Use when the user says /wrap, "wrap up", "prepare to close", "end the session", "update your memory and do housekeeping", or otherwise signals the session is ending and wants confirmation it's safe to close the terminal.
---

# Wrap up the session

The session is ending. Anything not done or not written down when the user
closes the terminal is gone — sweep for exactly that, using your full
knowledge of what happened this session.

1. **Loose ends** — promises made earlier ("I'll do X later"), deploys
   half-done, background subagents still working. Finish them or surface
   them. Do this first so anything you finish lands in the commit below
   rather than after it.
2. **Memory** — persist what this session taught that isn't already recorded
   in the repo or in memory (preferences, corrections, project state,
   decisions and their why). Update or create memory files and the index; fix
   or delete entries this session proved wrong, including any resume note
   for work that is now done. If memory is already current, say so and move
   on — a forced low-value memory is worse than none.
3. **Project docs** — if the session changed how the project works, make sure
   CLAUDE.md and project docs say so; that's where the next session looks
   first.
4. **Working tree** — check `git status`. Commit real work, and push if the
   branch tracks a remote — after any pre-push step the project requires
   (CLAUDE.md or memory will say). Report anything deliberately left
   uncommitted. Clean up stray scratch files that landed in the project, and
   remove worktrees the session created unless they hold uncommitted work.
5. **Processes and schedules** — shut down what the session started and
   would otherwise outlive the terminal: dev servers (python, npm, etc.),
   Playwright or headless Chrome instances, screenshot watchers, and any
   loops or scheduled jobs, unless the user asked for those to keep running.
6. **Confirm** — end the final message with a short close-out: what went to
   memory, tree/deploy state, open items for next time, then an explicit
   **"Ready to close."** — or "Not ready:" with what remains. The user closes
   the terminal on reading that line, so nothing may come after it except
   the truth.
