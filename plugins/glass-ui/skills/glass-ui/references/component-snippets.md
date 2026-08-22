# Glass UI Component Snippets

Copy-paste-ready code for common glassmorphism patterns. Every snippet
consumes the custom properties defined in the setup block, so components
stay visually consistent and re-theming is a one-block change. The values
match the calibrated tables in SKILL.md.

Accent colors below (`rgba(255, 100, 150, …)` pink) are placeholders —
swap for the project's brand accent.

---

## CSS Custom Properties Setup

Add once to the root stylesheet:

```css
:root {
  /* Dark theme glass tokens */
  --glass-blur-light: 6px;
  --glass-blur-medium: 10px;
  --glass-blur-heavy: 16px;

  --glass-surface-light: rgba(255, 255, 255, 0.05);
  --glass-surface-medium: rgba(255, 255, 255, 0.08);
  --glass-surface-dense: rgba(255, 255, 255, 0.12);
  --glass-surface-opaque: rgba(255, 255, 255, 0.18);

  /* Dark-tinted glass for text-heavy surfaces (headers, modals) */
  --glass-tinted: rgba(20, 20, 30, 0.75);
  --glass-tinted-dense: rgba(15, 15, 25, 0.85);

  --glass-border-subtle: rgba(255, 255, 255, 0.08);
  --glass-border-medium: rgba(255, 255, 255, 0.12);
  --glass-border-strong: rgba(255, 255, 255, 0.15);

  --glass-shadow-soft: 0 4px 24px rgba(0, 0, 0, 0.3);
  --glass-shadow-medium: 0 8px 32px rgba(0, 0, 0, 0.4);
  --glass-shadow-heavy: 0 16px 48px rgba(0, 0, 0, 0.5);

  --glass-inner-glow: inset 0 1px 0 rgba(255, 255, 255, 0.1);

  /* Solid fallback for browsers without backdrop-filter */
  --glass-fallback: rgba(30, 30, 40, 0.95);
}

/* Light theme overrides */
@media (prefers-color-scheme: light) {
  :root {
    --glass-blur-light: 8px;
    --glass-blur-medium: 12px;
    --glass-blur-heavy: 20px;

    --glass-surface-light: rgba(255, 255, 255, 0.4);
    --glass-surface-medium: rgba(255, 255, 255, 0.6);
    --glass-surface-dense: rgba(255, 255, 255, 0.75);
    --glass-surface-opaque: rgba(255, 255, 255, 0.85);

    --glass-tinted: rgba(255, 255, 255, 0.75);
    --glass-tinted-dense: rgba(255, 255, 255, 0.85);

    --glass-border-subtle: rgba(255, 255, 255, 0.3);
    --glass-border-medium: rgba(255, 255, 255, 0.4);
    --glass-border-strong: rgba(255, 255, 255, 0.5);

    --glass-shadow-soft: 0 4px 16px rgba(0, 0, 0, 0.08);
    --glass-shadow-medium: 0 8px 24px rgba(0, 0, 0, 0.12);
    --glass-shadow-heavy: 0 12px 32px rgba(0, 0, 0, 0.15);

    --glass-inner-glow: inset 0 1px 0 rgba(255, 255, 255, 0.5);

    --glass-fallback: rgba(255, 255, 255, 0.95);
  }
}
```

If the site has a manual theme toggle, repeat the light-theme block under
`[data-theme="light"]` (and guard the media query with
`:root:not([data-theme="dark"])`) so the toggle wins over the OS setting.

### Global accessibility override

Users who set "reduce transparency" in their OS get solid surfaces:

```css
@media (prefers-reduced-transparency: reduce) {
  .glass-panel, .glass-header, .glass-modal, .glass-card,
  .glass-dropdown, .glass-btn, .glass-toast, .glass-tag {
    background: var(--glass-fallback);
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }

  /* The modal overlay's blur is transparency too */
  .glass-modal-overlay {
    background: rgba(0, 0, 0, 0.7);
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }
}
```

---

## Base Glass Panel

The foundation class other components extend:

```css
.glass-panel {
  position: relative;

  /* Fallback for unsupported browsers */
  background: var(--glass-fallback);

  @supports (backdrop-filter: blur(1px)) {
    background: var(--glass-surface-medium);
    backdrop-filter: blur(var(--glass-blur-medium));
    -webkit-backdrop-filter: blur(var(--glass-blur-medium));
  }

  border: 1px solid var(--glass-border-subtle);
  border-radius: 16px;
  box-shadow: var(--glass-shadow-soft), var(--glass-inner-glow);

  /* Keep repaints cheap */
  transform: translateZ(0);
  contain: layout style paint;
}

/* Interactive variant */
.glass-panel--interactive {
  transition: background 0.3s ease, border-color 0.3s ease,
              box-shadow 0.3s ease, transform 0.3s ease;
  cursor: pointer;
}

.glass-panel--interactive:hover {
  background: var(--glass-surface-dense);
  border-color: var(--glass-border-medium);
  box-shadow: var(--glass-shadow-medium), var(--glass-inner-glow);
  transform: translateY(-2px) translateZ(0);
}

/* Density variants */
.glass-panel--light {
  background: var(--glass-surface-light);
  backdrop-filter: blur(var(--glass-blur-light));
  -webkit-backdrop-filter: blur(var(--glass-blur-light));
}

.glass-panel--dense {
  background: var(--glass-surface-dense);
}

.glass-panel--heavy-blur {
  backdrop-filter: blur(var(--glass-blur-heavy));
  -webkit-backdrop-filter: blur(var(--glass-blur-heavy));
}
```

---

## Sticky Header

```html
<header class="glass-header">
  <div class="glass-header__inner">
    <a href="/" class="glass-header__logo">Logo</a>
    <nav class="glass-header__nav">
      <a href="/about">About</a>
      <a href="/products">Products</a>
      <a href="/contact">Contact</a>
    </nav>
  </div>
</header>
```

```css
.glass-header {
  position: sticky;
  top: 0;
  z-index: 100;

  background: var(--glass-fallback);

  @supports (backdrop-filter: blur(1px)) {
    background: var(--glass-tinted);
    backdrop-filter: blur(12px) saturate(1.1);
    -webkit-backdrop-filter: blur(12px) saturate(1.1);
  }

  border-bottom: 1px solid var(--glass-border-medium);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.25);

  transform: translateZ(0);
  contain: layout style paint;
}

.glass-header__inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  max-width: 1400px;
  margin: 0 auto;
  padding: 0 1.5rem;
  height: 64px;
}

@media (min-width: 768px) {
  .glass-header__inner { height: 80px; }
}

.glass-header__nav {
  display: flex;
  gap: 0.5rem;
}

.glass-header__nav a {
  padding: 0.5rem 1rem;
  color: rgba(255, 255, 255, 0.7);
  border-radius: 8px;
  transition: color 0.2s ease, background 0.2s ease;
}

.glass-header__nav a:hover {
  color: rgba(255, 255, 255, 1);
  background: rgba(255, 255, 255, 0.1);
}
```

---

## Modal Dialog

```html
<!-- Shown state. When closed, add the `hidden` attribute to the overlay
     (don't use aria-hidden on a visible dialog — it hides it from assistive
     tech). While open: trap focus inside, close on Escape and overlay click. -->
<div class="glass-modal-overlay">
  <div class="glass-modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
    <header class="glass-modal__header">
      <h2 class="glass-modal__title" id="modal-title">Modal Title</h2>
      <button class="glass-modal__close" aria-label="Close">&times;</button>
    </header>
    <div class="glass-modal__body">
      <p>Modal content goes here.</p>
    </div>
    <footer class="glass-modal__footer">
      <button class="glass-btn">Cancel</button>
      <button class="glass-btn glass-btn--accent">Confirm</button>
    </footer>
  </div>
</div>
```

```css
.glass-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
}

.glass-modal {
  position: relative;
  width: 100%;
  max-width: 500px;
  max-height: 90vh;
  overflow: hidden;

  background: var(--glass-fallback);

  @supports (backdrop-filter: blur(1px)) {
    background: var(--glass-tinted);
    backdrop-filter: blur(var(--glass-blur-heavy)) saturate(1.2);
    -webkit-backdrop-filter: blur(var(--glass-blur-heavy)) saturate(1.2);
  }

  border: 1px solid var(--glass-border-medium);
  border-radius: 24px;
  box-shadow: var(--glass-shadow-heavy), var(--glass-inner-glow);

  transform: translateZ(0);
  contain: layout style paint;
}

/* Top edge highlight */
.glass-modal::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 1px;
  background: linear-gradient(90deg,
    transparent, rgba(255, 255, 255, 0.2), transparent);
}

.glass-modal__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.5rem 2rem;
  border-bottom: 1px solid var(--glass-border-subtle);
}

.glass-modal__title {
  font-size: 1.25rem;
  font-weight: 500;
  margin: 0;
}

.glass-modal__close {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.5rem;
  color: rgba(255, 255, 255, 0.6);
  background: transparent;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  transition: color 0.2s ease, background 0.2s ease;
}

.glass-modal__close:hover {
  color: rgba(255, 255, 255, 1);
  background: rgba(255, 255, 255, 0.1);
}

.glass-modal__body {
  padding: 2rem;
  overflow-y: auto;
}

.glass-modal__footer {
  display: flex;
  gap: 1rem;
  justify-content: flex-end;
  padding: 1.5rem 2rem;
  border-top: 1px solid var(--glass-border-subtle);
}
```

---

## Card (Featured/Hero Only)

**Use sparingly** — a single featured card, never every card in a grid
(see the performance rules in SKILL.md).

```html
<article class="glass-card">
  <div class="glass-card__content">
    <span class="glass-card__badge">Featured</span>
    <h3 class="glass-card__title">Card Title</h3>
    <p class="glass-card__desc">Card description text goes here.</p>
    <a href="#" class="glass-card__link">
      Learn more
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M5 12h14M12 5l7 7-7 7"/>
      </svg>
    </a>
  </div>
</article>
```

```css
.glass-card {
  position: relative;

  background: var(--glass-fallback);

  @supports (backdrop-filter: blur(1px)) {
    background: var(--glass-surface-medium);
    backdrop-filter: blur(var(--glass-blur-medium)) saturate(1.2);
    -webkit-backdrop-filter: blur(var(--glass-blur-medium)) saturate(1.2);
  }

  border: 1px solid var(--glass-border-medium);
  border-top-color: var(--glass-border-strong);  /* light-from-above */
  border-radius: 20px;
  overflow: hidden;
  transition: background 0.4s ease, border-color 0.4s ease,
              box-shadow 0.4s ease, transform 0.4s ease;
  transform: translateZ(0);
  contain: layout style paint;
}

/* Diagonal highlight gradient */
.glass-card::before {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg,
    rgba(255, 255, 255, 0.05) 0%, transparent 50%);
  pointer-events: none;
}

.glass-card:hover {
  background: var(--glass-surface-dense);
  border-color: var(--glass-border-strong);
  box-shadow: var(--glass-shadow-medium),
    0 0 0 1px rgba(255, 255, 255, 0.08);
  transform: translateY(-4px) translateZ(0);
}

.glass-card__content {
  position: relative;
  padding: 2rem;
}

.glass-card__badge {
  display: inline-block;
  padding: 0.375rem 0.875rem;
  font-size: 0.625rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  background: rgba(255, 100, 150, 0.2);
  color: rgba(255, 150, 180, 1);
  border-radius: 100px;
  margin-bottom: 1.25rem;
}

.glass-card__title {
  font-size: 1.5rem;
  font-weight: 500;
  margin: 0 0 0.75rem;
  letter-spacing: -0.01em;
}

.glass-card__desc {
  color: rgba(255, 255, 255, 0.7);
  line-height: 1.6;
  margin: 0 0 1.5rem;
}

.glass-card__link {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 500;
  color: rgba(255, 100, 150, 1);
  transition: gap 0.3s ease;
}

.glass-card__link:hover { gap: 0.75rem; }
```

---

## Dropdown Menu

```html
<div class="glass-dropdown-container">
  <button class="glass-btn">Menu</button>
  <div class="glass-dropdown">
    <a href="#" class="glass-dropdown__item">Option One</a>
    <a href="#" class="glass-dropdown__item">Option Two</a>
    <div class="glass-dropdown__divider"></div>
    <a href="#" class="glass-dropdown__item glass-dropdown__item--danger">Delete</a>
  </div>
</div>
```

```css
.glass-dropdown-container {
  position: relative;
  display: inline-block;
}

.glass-dropdown {
  position: absolute;
  top: 100%;
  left: 0;
  min-width: 200px;
  margin-top: 0.5rem;
  padding: 0.5rem;
  z-index: 100;

  background: var(--glass-fallback);

  @supports (backdrop-filter: blur(1px)) {
    background: var(--glass-tinted-dense);
    backdrop-filter: blur(var(--glass-blur-heavy)) saturate(1.2);
    -webkit-backdrop-filter: blur(var(--glass-blur-heavy)) saturate(1.2);
  }

  border: 1px solid var(--glass-border-medium);
  border-radius: 12px;
  box-shadow: var(--glass-shadow-medium);

  /* Animate opacity/transform, never blur */
  opacity: 0;
  visibility: hidden;
  transform: translateY(-8px);
  transition: opacity 0.2s ease, transform 0.2s ease, visibility 0.2s;
}

/* Show state — toggle via JS */
.glass-dropdown.is-open {
  opacity: 1;
  visibility: visible;
  transform: translateY(0);
}

.glass-dropdown__item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1rem;
  font-size: 0.875rem;
  color: rgba(255, 255, 255, 0.85);
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
}

.glass-dropdown__item:hover {
  background: rgba(255, 255, 255, 0.1);
  color: rgba(255, 255, 255, 1);
}

.glass-dropdown__item--danger {
  color: rgba(255, 100, 100, 0.9);
}

.glass-dropdown__item--danger:hover {
  background: rgba(255, 100, 100, 0.15);
  color: rgba(255, 100, 100, 1);
}

.glass-dropdown__divider {
  height: 1px;
  margin: 0.5rem 0;
  background: var(--glass-border-subtle);
}
```

---

## Button Variants

```css
.glass-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.75rem 1.5rem;
  font-size: 0.875rem;
  font-weight: 500;
  color: rgba(255, 255, 255, 0.9);
  background: var(--glass-surface-medium);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--glass-border-medium);
  border-radius: 100px;
  cursor: pointer;
  transition: background 0.25s ease, border-color 0.25s ease,
              box-shadow 0.25s ease, transform 0.1s ease;
}

.glass-btn:hover {
  background: rgba(255, 255, 255, 0.15);
  border-color: rgba(255, 255, 255, 0.2);
  box-shadow: var(--glass-shadow-soft);
}

.glass-btn:active { transform: scale(0.98); }

/* Accent variant — swap for brand color */
.glass-btn--accent {
  background: rgba(255, 100, 150, 0.2);
  border-color: rgba(255, 100, 150, 0.3);
  color: rgba(255, 200, 220, 1);
}

.glass-btn--accent:hover {
  background: rgba(255, 100, 150, 0.3);
  border-color: rgba(255, 100, 150, 0.4);
}

/* Size variants */
.glass-btn--sm { padding: 0.5rem 1rem; font-size: 0.8125rem; }
.glass-btn--lg { padding: 1rem 2rem; font-size: 1rem; }

/* Icon-only */
.glass-btn--icon {
  width: 40px;
  height: 40px;
  padding: 0;
  border-radius: 50%;
}
```

---

## Toast Notification

```html
<div class="glass-toast glass-toast--success" role="status">
  <svg class="glass-toast__icon"><!-- checkmark --></svg>
  <span class="glass-toast__message">Changes saved successfully</span>
  <button class="glass-toast__close" aria-label="Dismiss">&times;</button>
</div>
```

```css
.glass-toast {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1rem 1.25rem;
  min-width: 280px;
  max-width: 400px;

  background: var(--glass-tinted);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--glass-border-medium);
  border-radius: 12px;
  box-shadow: var(--glass-shadow-medium);

  animation: toastSlideIn 0.3s ease;
}

@keyframes toastSlideIn {
  from { opacity: 0; transform: translateY(-20px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  .glass-toast { animation: none; }
}

.glass-toast__icon {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
}

.glass-toast__message {
  flex: 1;
  font-size: 0.875rem;
  color: rgba(255, 255, 255, 0.9);
}

.glass-toast__close {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.25rem;
  color: rgba(255, 255, 255, 0.5);
  background: transparent;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  transition: color 0.2s ease, background 0.2s ease;
}

.glass-toast__close:hover {
  color: rgba(255, 255, 255, 1);
  background: rgba(255, 255, 255, 0.1);
}

/* Status variants */
.glass-toast--success { border-left: 3px solid rgba(100, 220, 150, 0.8); }
.glass-toast--success .glass-toast__icon { color: rgba(100, 220, 150, 1); }

.glass-toast--error { border-left: 3px solid rgba(255, 100, 100, 0.8); }
.glass-toast--error .glass-toast__icon { color: rgba(255, 100, 100, 1); }

.glass-toast--warning { border-left: 3px solid rgba(255, 200, 100, 0.8); }
.glass-toast--warning .glass-toast__icon { color: rgba(255, 200, 100, 1); }
```

---

## Tag/Badge

```css
.glass-tag {
  display: inline-flex;
  align-items: center;
  padding: 0.375rem 0.875rem;
  font-size: 0.6875rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  background: var(--glass-surface-light);
  backdrop-filter: blur(var(--glass-blur-light));
  -webkit-backdrop-filter: blur(var(--glass-blur-light));
  border: 1px solid var(--glass-border-subtle);
  border-radius: 100px;
  color: rgba(255, 255, 255, 0.8);
}

/* Color variants — tinted glass */
.glass-tag--pink {
  background: rgba(255, 100, 150, 0.12);
  border-color: rgba(255, 100, 150, 0.2);
  color: rgba(255, 180, 200, 1);
}

.glass-tag--blue {
  background: rgba(100, 150, 255, 0.12);
  border-color: rgba(100, 150, 255, 0.2);
  color: rgba(180, 200, 255, 1);
}

.glass-tag--green {
  background: rgba(100, 220, 150, 0.12);
  border-color: rgba(100, 220, 150, 0.2);
  color: rgba(180, 240, 200, 1);
}

.glass-tag--orange {
  background: rgba(255, 150, 100, 0.12);
  border-color: rgba(255, 150, 100, 0.2);
  color: rgba(255, 200, 180, 1);
}
```

---

## Ambient Background (Required for Dark Theme)

Glass over flat dark color is invisible — give it ambient gradients to blur:

```css
body {
  background:
    radial-gradient(ellipse 50% 40% at 20% 30%, rgba(120, 80, 200, 0.15), transparent),
    radial-gradient(ellipse 60% 50% at 80% 70%, rgba(200, 80, 120, 0.1), transparent),
    radial-gradient(ellipse 40% 30% at 60% 20%, rgba(80, 150, 200, 0.08), transparent),
    #0a0a12;
  min-height: 100vh;
}

/* Alternative: section-specific gradients */
.section--ambient {
  background:
    radial-gradient(ellipse 40% 35% at 15% 50%, rgba(255, 100, 150, 0.1), transparent),
    radial-gradient(ellipse 45% 40% at 85% 30%, rgba(150, 100, 255, 0.08), transparent);
}
```
