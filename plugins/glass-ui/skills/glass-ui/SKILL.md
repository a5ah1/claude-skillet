---
name: glass-ui
description: Use when implementing glassmorphism, frosted glass, or Liquid Glass-style translucent UI — glass panels, sticky headers, modals, dropdowns over colorful backgrounds. Triggers on "glass", "glassmorphism", "frosted", "Liquid Glass", "Apple-style translucency", "backdrop-filter", "translucent panels", or requests for modern layered UI with depth. Provides calibrated CSS values per theme and density, ambient-background requirements, performance limits, and accessibility guidance including reduced-transparency fallbacks.
---

# Glass UI / Glassmorphism

Calibrated values and judgment calls for frosted-glass effects (including
Apple "Liquid Glass"-style translucency) in web interfaces. The values here
are tuned and tested — prefer them over improvising opacities and blur radii,
which is where glass UIs usually go wrong (invisible glass, unreadable text,
janky scrolling).

## Core Concept

Glassmorphism creates the illusion of frosted glass using:
1. **Semi-transparent background** — lets content beneath show through
2. **backdrop-filter: blur()** — the essential property; blurs what's behind
3. **Subtle borders** — define edges, often slightly transparent
4. **Soft shadows** — depth and elevation
5. **Optional inner glow** — rim lighting on the top edge

**The #1 failure mode**: glass over a flat dark background is invisible.
`backdrop-filter` can only reveal what's behind the element, so the page
needs ambient color to blur — gradients, images, or colored sections.

```css
/* BAD: glass disappears on pure black */
body { background: #000; }

/* GOOD: ambient gradients give the glass something to blur */
body {
  background:
    radial-gradient(ellipse at 20% 30%, rgba(120, 80, 200, 0.15), transparent),
    radial-gradient(ellipse at 80% 70%, rgba(200, 80, 120, 0.1), transparent),
    #0a0a12;
}
```

## Minimum Viable Glass

```css
.glass {
  /* Fallback for browsers without backdrop-filter (~2-3%) */
  background: rgba(30, 30, 40, 0.95);

  /* blur(1px) is a capability probe — the applied radius is separate */
  @supports (backdrop-filter: blur(1px)) {
    background: rgba(255, 255, 255, 0.08);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);  /* older Safari/iOS */
  }

  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 16px;
}
```

The nested `@supports` relies on native CSS nesting — safe for anything
targeting evergreen browsers (universal since 2023). Flatten it only for
legacy build pipelines or pages that must render in old engines.

## Calibrated Values

These tables are the single source of truth; the component snippets in
`references/component-snippets.md` express the same values as CSS custom
properties.

### Dark theme (background lightness 8–30%; ambient color required)

| Property | Light glass | Medium glass | Dense glass | Opaque glass |
|----------|-------------|--------------|-------------|--------------|
| Background | `rgba(255,255,255,0.05)` | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.12)` | `rgba(255,255,255,0.18)` |
| Blur | 6px | 10px | 16px | 20px |
| Border | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.12)` | `rgba(255,255,255,0.15)` | `rgba(255,255,255,0.18)` |
| Use case | Tags, small elements | Cards, panels | Modals, hero elements | Max contrast that still reads as glass |

Dark-*tinted* glass (for surfaces needing real text contrast — headers,
modals): `rgba(20,20,30,0.75)` standard, `rgba(15,15,25,0.85)` dense.

Text on dark glass: primary `rgba(255,255,255,0.95)`, secondary
`rgba(255,255,255,0.7)`, muted `rgba(255,255,255,0.5)`.

### Light theme (background lightness 70%+; glass reads as frosted white)

| Property | Light glass | Medium glass | Dense glass | Opaque glass |
|----------|-------------|--------------|-------------|--------------|
| Background | `rgba(255,255,255,0.4)` | `rgba(255,255,255,0.6)` | `rgba(255,255,255,0.75)` | `rgba(255,255,255,0.85)` |
| Blur | 8px | 12px | 20px | 20px |
| Border | `rgba(255,255,255,0.3)` | `rgba(255,255,255,0.4)` | `rgba(255,255,255,0.5)` | `rgba(255,255,255,0.5)` |
| Use case | Subtle overlays | Standard panels | High-contrast modals | Max contrast |

For edge definition on light glass, a dark border works better:
`1px solid rgba(0,0,0,0.08)`. Text: primary `rgba(0,0,0,0.9)`, secondary
`rgba(0,0,0,0.65)`, muted `rgba(0,0,0,0.45)`.

### Filter extras

`saturate()` makes the blurred content glow through more vividly — the
signature "liquid" look: `backdrop-filter: blur(10px) saturate(1.2)`.
Use 1.1 (subtle) to 1.2 (standard); 1.5 reads as vibrant/stylized.
`brightness(0.9–1.1)` can compensate when the backdrop is too bright or dim.

## Component Patterns

Copy-paste-ready HTML/CSS for the common cases — tokens setup, sticky
header, modal, featured card, dropdown, buttons, toast, tag, ambient
backgrounds — lives in `references/component-snippets.md`. Read it when
building any of those rather than improvising values. All snippets consume
the same custom properties, so a page-wide look stays consistent.

## Performance

`backdrop-filter` is GPU-intensive; the browser re-blurs on every repaint
of what's underneath. This is the other place glass UIs commonly fail.

1. **Limit glass to 2–3 elements per viewport** — more causes jank on
   mid-range devices. Count every `backdrop-filter`, including a modal
   overlay's low-radius blur. An open-modal state may transiently exceed
   the budget (header + card + modal + overlay); that's acceptable because
   it's short-lived and the modal occludes most of the page — just don't
   make it the resting state, and keep the overlay blur at ≤4px.
2. **Never animate blur radius** — it forces continuous re-blurs and drops
   frames. Animate opacity or transform instead.
3. **Reduce blur on mobile** — 6–8px instead of 10–16px; small screens
   don't benefit from heavy blur anyway.
4. **Avoid glass on large areas** — full-screen glass panels are the most
   expensive single thing you can do with this effect. For static
   backdrops, use a pre-blurred image instead of live blur.
5. **Contain repaints** on glass elements:

```css
.glass {
  transform: translateZ(0);          /* promote to its own layer */
  contain: layout style paint;       /* limit repaint scope */
}
```

Don't blanket-apply `will-change` — reserve it for an element that is about
to animate, and remove it after; a page full of `will-change` layers costs
more memory than it saves.

## Accessibility

- **Contrast still applies**: 4.5:1 for normal text, 3:1 for large text —
  measured against the *worst* backdrop the glass can end up over, not the
  average. If content scrolls beneath the glass, test against its brightest
  and darkest sections; step up a density tier (or use dark-tinted glass)
  when it fails.
- **Respect `prefers-reduced-transparency`** — this OS setting exists
  precisely because translucent surfaces hurt readability for some users:

```css
@media (prefers-reduced-transparency: reduce) {
  .glass {
    background: rgba(30, 30, 40, 0.98);
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }
}
```

- **Respect `prefers-reduced-motion`** for hover-lift and slide-in
  animations on glass elements.

## When to Use Glass

**Good fits** — floating, layered, singular elements:
sticky headers (scrolled state), modals and dialogs, dropdown menus, toast
notifications, a single featured/hero card, floating toolbars and action
sheets.

**Avoid** — where it multiplies or has nothing to blur:
every card in a grid (performance and diminishing returns), large area
backgrounds, elements over flat solid color (invisible), footers (low
priority), more than ~3 glass elements visible at once, animating blur.

## Browser Support

`backdrop-filter` is supported by every evergreen browser (Chrome/Edge 76+,
Firefox 103+, Safari with the `-webkit-` prefix for versions before 18) —
roughly 97–98% global support. Always ship the `-webkit-` prefix alongside
the unprefixed property, and keep the `@supports` fallback: it costs three
lines and covers the long tail.
