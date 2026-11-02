---
name: Harbor Modern Personal Finance
colors:
  surface: '#f8f9fd'
  surface-dim: '#d9dade'
  surface-bright: '#f8f9fd'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3f7'
  surface-container: '#edeef2'
  surface-container-high: '#e7e8ec'
  surface-container-highest: '#e1e2e6'
  on-surface: '#191c1f'
  on-surface-variant: '#454655'
  inverse-surface: '#2e3134'
  inverse-on-surface: '#eff1f5'
  outline: '#757687'
  outline-variant: '#c5c5d8'
  surface-tint: '#3848e7'
  primary: '#2a3bdc'
  on-primary: '#ffffff'
  primary-container: '#4858f5'
  on-primary-container: '#eeedff'
  inverse-primary: '#bdc2ff'
  secondary: '#545e77'
  on-secondary: '#ffffff'
  secondary-container: '#d5dffd'
  on-secondary-container: '#58627c'
  tertiary: '#535071'
  on-tertiary: '#ffffff'
  tertiary-container: '#6b688b'
  on-tertiary-container: '#f0ebff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dfe0ff'
  primary-fixed-dim: '#bdc2ff'
  on-primary-fixed: '#000767'
  on-primary-fixed-variant: '#1628d0'
  secondary-fixed: '#d9e2ff'
  secondary-fixed-dim: '#bcc6e3'
  on-secondary-fixed: '#111b31'
  on-secondary-fixed-variant: '#3d465e'
  tertiary-fixed: '#e4dfff'
  tertiary-fixed-dim: '#c7c2e9'
  on-tertiary-fixed: '#1a1836'
  on-tertiary-fixed-variant: '#464363'
  background: '#f8f9fd'
  on-background: '#191c1f'
  surface-variant: '#e1e2e6'
typography:
  display-hero:
    fontFamily: Plus Jakarta Sans
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.025em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: 0.005em
  label-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.03em
  currency-stat:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1.25rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 2rem
  margin-desktop: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.25rem
---

## Brand & Style

The design system projects clarity, emotional reassurance, and effortless mastery over personal finances. Built for design-conscious individuals navigating multi-currency assets and long-term planning, it replaces archaic spreadsheet stiffness with editorial precision and approachable warmth. 

The aesthetic is Modern Editorial Fintech: luminous off-white planes, sculpted high-radius cards, crisp geometric metrics, and disciplined optical density. Visual noise is stripped back to highlight capital movement, net-worth trajectories, and spending insights without overwhelming the user. Micro-interactions should feel tactile yet weightless, delivering instant feedback and reinforcing financial confidence.

## Colors

- **Primary (`#4858F5` - Electric Cobalt):** Serves as the primary operational hue, driving core actions, critical CTAs, chart focus points, and active navigation nodes.
- **Secondary (`#182238` - Deep Midnight Navy):** Establishes structural anchor weight. Applied across deep headers, high-emphasis text, high-value asset banners, and dark-mode anchor moments.
- **Tertiary (`#DCD7FF` - Soft Lavender):** Delivers supportive warmth, serving as primary tint backdrops, selected item states, secondary indicators, and accent highlights.
- **Neutral Canvas (`#F6F7FB` - Soft Cloud):** Grounds the interface with an off-white base layer that reduces eye strain and isolates foreground cards cleanly.
- **Surface & Frame (`#FFFFFF` & `#E5E9F2`):** Pure white modular cards outlined with a whisper-light 1px structural stroke, avoiding muddy drop shadows.
- **Semantic Indicators:**
  - *Positive (`#269B91` - Muted Teal):* Inflows, portfolio gains, and budget surplus.
  - *Highlight / Warning (`#FFBD96` - Warm Apricot):* Budget warnings, upcoming scheduled bills, and pending clearings.
  - *Negative / Alert (`#F05252` - Coral Red):* Outflows, account overdraft alerts, and critical discrepancies.

## Typography

The typography scale utilizes **Plus Jakarta Sans** across all roles to ensure geometric balance, modern technical polish, and open letter counters.

### Financial Value Rules
- **Tabular Figures:** All financial balances, transaction amounts, and percentage changes must enforce tabular numbers (`font-variant-numeric: tabular-nums lining-nums`) to prevent horizontal jitter during real-time value updates.
- **Currency Styling:** For Canadian Dollar entries, render the currency sign (`$`) and cents in a slightly reduced weight or size (e.g., body-md) relative to the integer value (`currency-stat`) to preserve optical focus on significant digits.
- **Negative Balances:** Represent negative amounts using standard minus glyphs (`−`) rather than hyphens, styled strictly with Coral Red.

## Layout & Spacing

A 12-column responsive fluid grid governs desktop and tablet layouts, shifting to an adaptive 4-column column system on mobile. 

- **Breakpoints:**
  - *Mobile:* `< 768px` (4 columns, `margin: 1rem`, `gutter: 1.25rem`)
  - *Tablet:* `768px - 1199px` (8 columns, `margin: 2rem`, `gutter: 1.5rem`)
  - *Desktop:* `≥ 1200px` (12 columns, max-width `1440px`, `margin: 3rem`, `gutter: 1.5rem`)

Layout rhythm prioritizes horizontal grouping for balance displays and vertical continuous stacks for ledger activity. Primary stat cards take 4 columns on desktop, 4 columns on tablet (2x2 grid), and 4 columns (full width) on mobile. Micro-stat chips and transaction tiles enforce consistent internal container padding using `space-md` (16px) and `space-lg` (24px).

## Elevation & Depth

Visual hierarchy relies on crisp surface layering combined with ambient tinted shadows rather than dark, opaque drops.

- **Canvas (Layer 0):** `#F6F7FB` baseline screen background.
- **Flat Surface (Layer 1):** `#FFFFFF` cards enclosed with a 1px solid `#E5E9F2` border. This is the default card state, completely flat or using an imperceptible ambient falloff (`0 1px 3px rgba(24, 34, 56, 0.04)`).
- **Elevated Interactive Surface (Layer 2):** Applied to active cards, dropdown panels, and hovered actionable tiles:
  `box-shadow: 0 10px 25px -5px rgba(24, 34, 56, 0.06), 0 4px 6px -2px rgba(24, 34, 56, 0.03);`
  Border shifts slightly to `#DCD7FF` on active card hover.
- **Floating Modals & Overlays (Layer 3):** Bottom sheets, action sheets, and modal sheets:
  `box-shadow: 0 20px 40px -12px rgba(24, 34, 56, 0.12);`
  Combined with a frosted backdrop blur (`backdrop-filter: blur(8px); background: rgba(24, 34, 56, 0.2)`).

## Shapes

The design system adopts a sweeping, tactile pill-inspired shape language (`roundedness: 3`) that feels friendly and ergonomic:

- **Primary Cards & Containers:** Use `24px` (`rounded-2xl`) for mobile containers and `32px` (`rounded-3xl`) for hero balance and portfolio cards on desktop.
- **Interactive Controls:** All standalone CTAs, search bars, segment pill switchers, and input fields utilize continuous pill corners (`9999px` or full radial border-radius).
- **Nested Context Elements:** Micro-stat chips, avatar frames, and category icon backdrops use `12px` to `16px` curvature, establishing structural nesting harmony inside parent cards.

## Components

### Buttons & Interactive Controls
- **Primary Buttons:** High-contrast pill-shaped actions with Cobalt Blue (`#4858F5`) fill, pure white text, zero border, and subtle scale down on click (`transform: scale(0.98)`).
- **Secondary Buttons:** Pill shaped, filled with Soft Lavender (`#DCD7FF`) at 40% opacity, `#182238` text, transitioning to solid tertiary fill on hover.
- **Segment Switches:** Rounded pill-track styled with `#F6F7FB` and a 1px `#E5E9F2` border. The selected segment is a floating pure white pill with an ambient shadow (`0 2px 8px rgba(24, 34, 56, 0.08)`).

### Cards & Ledger Displays
- **Balance & Hero Cards:** `#FFFFFF` or Deep Midnight Navy (`#182238`) inverted variants. Internal padding of 24px/32px, `rounded-3xl`, housing prominent financial figures with CAD designation chips.
- **Transaction List Items:** Borderless, clean horizontal list row. Left side features a 44px rounded container (`rounded-xl`) with soft pastel background and category iconography. Center aligns counterparty title with metadata subtext. Right side anchors the tabular currency figure, colored `#269B91` for inflows or `#182238` for debits.

### Chips & Progress Indicators
- **Micro-Stat Badges:** Pill-shaped tags (`height: 24px`) with `space-xs` vertical and `space-sm` horizontal padding. Uses semantic background tints at 12% opacity with 100% solid text (e.g., Teal base for `+4.2% YTD`).
- **Dual-Tone Progress Bars:** Continuous pill rail (`height: 8px`, `#E5E9F2` track) with dual segmented fills (e.g., `#4858F5` for recurring expenses and `#DCD7FF` for discretionary budget) finished with rounded segment caps.

### Form Inputs & Checks
- **Input Fields:** Pill-shaped (`height: 48px`), pure white background, framed with a 1px `#E5E9F2` border. Focused state replaces border with a 2px `#4858F5` ring and zero-offset highlight.
- **Checkboxes & Radios:** Smooth curved squares (`rounded-md`, 20px) and circles (20px). When active, filled with `#4858F5` featuring clean white geometric vectors.