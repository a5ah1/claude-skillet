---
name: wrap
description: End-of-session close-out. Use when the user says /wrap, "wrap up", "prepare to close", "end the session", "update your memory and do housekeeping", or otherwise signals the session is ending and wants confirmation it's safe to close the terminal.
---

# Wrap up the session

The session is ending. Anything not done or not written down when the user
closes the terminal is gone — sweep for exactly that, using your full
knowledge of what happened this session.

1. **Memory** — persist what this session taught that isn't already recorded
   in the repo or in memory (preferences, corrections, project state,
   decisions and their why). Update or create memory files and the index; fix
   or delete entries this session proved wrong. If memory is already current,
   say so and move on — a forced low-value memory is worse than none.
2. **Project docs** — if the session changed how the project works, make sure
   CLAUDE.md and project docs say so; that's where the next session looks
   first.
3. **Working tree** — check `git status`. Commit and push real work; report
   anything deliberately left uncommitted. Clean up stray scratch files that
   landed in the project.
4. **Loose ends** — background tasks still running, deploys half-done,
   promises made earlier in the session ("I'll do X later"). Finish them or
   surface them. Shut down lingering processes the session started — dev
   servers (python, npm, etc.), Playwright or headless Chrome instances,
   screenshot watchers — so nothing keeps running after the terminal closes.
5. **Confirm** — end the final message with a short close-out: what went to
   memory, tree/deploy state, open items for next time, then an explicit
   **"Ready to close."** — or "Not ready:" with what remains. The user closes
   the terminal on reading that line, so nothing may come after it except
   the truth.
