---
name: lucide-icons
description: Use when selecting, searching for, or implementing icons in any web project using or adopting the Lucide icon library (lucide, lucide-react, lucide-vue-next, lucide-svelte). Triggers on any mention of "icons" or "Lucide", and when building UI that would benefit from icons — navigation, buttons, dashboards, status indicators, action menus, cards, lists. Icon names must come from this skill's bundled index, never from memory — guessed Lucide names are frequently wrong and render as blank icons.
---

# Lucide Icons

The core rule: **never emit a Lucide icon name you haven't verified against
the bundled index.** Plausible-sounding names (`CartIcon`, `Warning`,
`Invoice`) often don't exist, and a wrong name fails silently — the icon
just doesn't render.

## Icon Selection Workflow

The index at `references/lucide-icon-index.json` (relative to this skill
directory) maps every **PascalCase** import name to its `kebab` name and
search `keywords`. It is ~1,800 entries — **search it, don't read it into
context**.

1. **Search by concept** (jq):

```bash
jq -r 'to_entries[] | select(any(.value.keywords[]; test("cart"; "i"))) | "\(.key)  (\(.value.kebab))"' references/lucide-icon-index.json
```

Without jq, grep the pretty-printed file — entry names sit above their
keywords:

```bash
grep -iB 10 '"warning"' references/lucide-icon-index.json | grep -E '^  "[A-Z]'
```

2. **No hits? Try synonyms.** Lucide's vocabulary is opinionated: no
   "invoice" (search `receipt`), errors live under `alert`, and so on.
   Search the concept's neighbors before concluding an icon doesn't exist.

3. **Verify every name you're about to use** — one exact-match grep is
   cheap insurance:

```bash
grep -c '"ShoppingCart"' references/lucide-icon-index.json   # 1 = exists, 0 = stop
```

Use the PascalCase name in JS imports and the kebab-case name in HTML
`data-lucide` attributes and framework `<Icon name="...">` props.

## Vanilla JS

### CDN

```html
<script src="https://unpkg.com/lucide@latest/dist/umd/lucide.min.js"></script>

<i data-lucide="search"></i>
<i data-lucide="shopping-cart"></i>

<script>lucide.createIcons();</script>
```

### npm (tree-shakeable)

```js
import { createIcons, Search, ShoppingCart } from 'lucide';
createIcons({ icons: { Search, ShoppingCart } });
```

### Programmatic creation

```js
import { createElement, Search } from 'lucide';
const el = createElement(Search, { size: 24, color: '#333', strokeWidth: 2 });
document.getElementById('container').appendChild(el);
```

## React / Vue / Svelte

Framework packages export the same PascalCase names as components:

```jsx
// lucide-react
import { Search, ShoppingCart } from 'lucide-react';

<Search size={16} strokeWidth={1.5} />
<ShoppingCart className="text-muted" aria-hidden="true" />
```

`lucide-vue-next` and `lucide-svelte` work the same way. Props mirror the
SVG attributes: `size`, `color`, `strokeWidth`, `absoluteStrokeWidth`.
Decorative icons should carry `aria-hidden="true"`; icons that convey
meaning need a text label or `aria-label` alongside.

## Customization

Defaults: 24×24, stroke-width 2, `currentColor` (inherits text color —
prefer styling the parent's `color` over hardcoding). Override via HTML
attributes or props:

```html
<i data-lucide="search" width="32" height="32" stroke-width="1.5"></i>
```

## Dynamic Icon Updates (vanilla only)

After inserting new `data-lucide` elements into the DOM, call
`lucide.createIcons()` again — it only processes elements present at call
time. Framework packages don't need this.

## Regenerating the Index

Run when Lucide releases new icons (needs network access; falls back to a
locally installed `lucide` package):

```bash
node scripts/generate-lucide-index.mjs references/lucide-icon-index.json
```
