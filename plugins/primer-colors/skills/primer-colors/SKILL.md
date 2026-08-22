---
name: primer-colors
description: GitHub Primer semantic color tokens (@primer/primitives) as a ready-to-paste CSS file with complete dark, dark-dimmed, and light themes. Use when the user mentions Primer, wants GitHub-style theming, or asks for a proven off-the-shelf semantic color token system for an admin panel, internal tool, staff UI, or data-dense dashboard. Not for general dark-mode styling or theming questions when the project has its own design system or brand palette.
---

# GitHub Primer Color Tokens

A complete, accessible color system lifted from GitHub's Primer design
system — the value is that every pairing (text on background, border on
surface, status tints) is already tuned and contrast-tested, so no color
decisions are needed. The entire payload is
[references/tokens.css](references/tokens.css): copy it into the project
verbatim, or read it to extract specific values. It is organized by theme
with category comments, so targeted extraction is easy.

## Applying Themes

Set `data-theme` on `<html>` or any container. Each theme block already
sets `color-scheme` so native form controls match.

| Theme | Selector | Page background | Best for |
|-------|----------|-----------------|----------|
| Dark Dimmed | `[data-theme="dark-dimmed"]` | `#212830` | Long working sessions, reduced eye strain |
| Dark | `[data-theme="dark"]` | `#0d1117` | High-contrast dark preference |
| Light | `[data-theme="light"]` | `#ffffff` | Traditional light UI |

## How the Naming Works

`--{category}-{variant}` or `--{category}-{semantic}-{variant}`, with
categories `bgColor`, `fgColor`, `borderColor`, `shadow`. The pairings
that aren't obvious from the names:

- **Background depth runs** `default` (page) → `muted` (recessed:
  sidebars, cards) → `inset` (deepest: code blocks, nested panels).
- **`-emphasis` means solid high-contrast fill** (tooltips, badges,
  status chips) and always pairs with `--fgColor-onEmphasis` for its
  text. **`-muted` means a subtle tint** for banners and highlights, and
  pairs with the matching plain semantic foreground
  (e.g. `--bgColor-attention-muted` + `--fgColor-attention`).
- **Six semantic states**, each with emphasis/muted across bg, fg, and
  border: `accent` (informational/selected), `success`, `attention`
  (yellow caution), `severe` (orange — between attention and danger),
  `danger`, `neutral` (deemphasized).
- **Shadows**: `resting-*` for static depth, `floating-*` for elevated
  elements (dropdowns, modals). `--focus-outline` is the keyboard focus
  ring. `overlay-*`, `header-*`, and `--selection-bgColor` cover modals,
  app headers, and text selection.

## Usage Pattern

```css
.card {
    background: var(--bgColor-muted);
    border: 1px solid var(--borderColor-default);
    color: var(--fgColor-default);
}

.alert-warning {
    background: var(--bgColor-attention-muted);
    border: 1px solid var(--borderColor-attention-muted);
    color: var(--fgColor-attention);
}

.badge-success {
    background: var(--bgColor-success-emphasis);
    color: var(--fgColor-onEmphasis);
}
```

Primer is designed for the system font stack — no webfonts needed:

```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans',
             Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji';
```
