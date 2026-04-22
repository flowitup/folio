# Design Guidelines

**Last Updated:** 2026-01-28
**Design System:** Fintech Minimalist
**Version:** 1.0

## Design Philosophy

**Fintech Minimalist** design emphasizes clarity, trust, and efficiency through:
- Clean, uncluttered layouts
- Generous whitespace
- Clear information hierarchy
- Professional color palette
- Accessible, readable typography
- Consistent, predictable interactions

**Target Audience:** Construction professionals (managers, supervisors)
**Use Cases:** Project management, team coordination, resource planning
**Accessibility:** WCAG 2.1 AA compliance (target)

---

## Color Palette

### Primary Colors

| Name | Light | Dark | Usage |
|------|-------|------|-------|
| **Accent Blue** | #3B82F6 | #60A5FA | Buttons, links, highlights |
| **Background** | #FFFFFF | #0F172A | Page backgrounds |
| **Foreground** | #0F172A | #FFFFFF | Text, dark elements |

### Extended Palette

| Purpose | Light | Dark | Accessibility |
|---------|-------|------|---|
| **Text Primary** | #0F172A | #FFFFFF | WCAG AAA |
| **Text Secondary** | #64748B | #CBD5E1 | WCAG AA |
| **Border Default** | #E2E8F0 | #334155 | Subtle, non-intrusive |
| **Status Positive** | #22C55E | #22C55E | Green (success, data growth) |
| **Status Negative** | #EF4444 | #EF4444 | Red (errors, issues) |
| **Status Warning** | #FBBF24 | #FCD34D | Amber (caution) |
| **Status Neutral** | #6B7280 | #9CA3AF | Gray (info, neutral) |

### Semantic Color Usage

```css
--primary: #3B82F6;           /* Accent (buttons, links) */
--primary-foreground: #FFFFFF; /* Text on primary */
--secondary: #F1F5F9;          /* Secondary actions, hover states */
--muted: #F1F5F9;              /* Disabled, inactive elements */
--accent: #EFF6FF;             /* Highlight backgrounds */
--destructive: #EF4444;        /* Delete, error actions */
--border: #E2E8F0;             /* Card borders, dividers */
--input: #E2E8F0;              /* Form input backgrounds */
--ring: #3B82F6;               /* Focus states, outlines */
```

### Dark Mode

Dark mode uses `@media (prefers-color-scheme: dark)` with CSS variable overrides:

```css
@media (prefers-color-scheme: dark) {
  :root {
    --background: #0F172A;
    --foreground: #FFFFFF;
    --border: #334155;
    --input: #1E293B;
    /* ... other dark overrides ... */
  }
}
```

---

## Typography

### Font Family

| Category | Font | Usage | Weights |
|----------|------|-------|---------|
| **Headings** | Outfit | H1-H6, titles, labels | 600, 700 |
| **Body** | Inter | Paragraph text, UI labels | 400, 500, 600 |
| **Code** | JetBrains Mono | Code blocks, technical text | 400, 600 |

### Font Scale

| Level | Size | Line Height | Letter Spacing | Usage |
|-------|------|-------------|---|---|
| **H1** | 32px | 1.2 | -0.5px | Page titles |
| **H2** | 24px | 1.3 | -0.25px | Section headers |
| **H3** | 20px | 1.4 | 0px | Subsections |
| **H4** | 18px | 1.4 | 0px | Card titles |
| **Body** | 16px | 1.5 | 0px | Main text |
| **Small** | 14px | 1.5 | 0px | Labels, captions |
| **Tiny** | 12px | 1.4 | 0.25px | Footnotes, timestamps |

### Accessibility

- Minimum text size: 14px for body text
- Minimum line height: 1.5 for readability
- Maximum line length: 80 characters (measure) for optimal reading
- Color contrast minimum: WCAG AA (4.5:1 for body, 3:1 for large text)

---

## Spacing System

### Space Scale (Tokens)

Based on 8px base unit:

```
0px   (0)    → xs
4px   (0.5)  → sm
8px   (1)    → base
12px  (1.5)  → lg
16px  (2)    → xl
24px  (3)    → 2xl
32px  (4)    → 3xl
48px  (6)    → 4xl
64px  (8)    → 5xl
```

### Usage Guidelines

| Element | Padding | Margin | Gap |
|---------|---------|--------|-----|
| **Button** | 8-12px V, 16px H | 8px | - |
| **Input** | 8-10px V, 12px H | 8px | - |
| **Card** | 24px | 16px | 16px |
| **Section** | - | 48px | - |
| **Grid** | - | - | 16px |

---

## Components

### Button Variants

**Default (Primary Action)**
- Background: #3B82F6
- Text: White
- Padding: 10px 16px
- Radius: 6px
- Hover: Darker blue (#2563EB)
- Focus: Ring 2px, offset 2px
- Disabled: Opacity 50%, cursor not-allowed

**Secondary (Alternative Action)**
- Background: #F1F5F9
- Text: #0F172A
- Border: 1px #E2E8F0
- Hover: Lighter background (#E2E8F0)

**Destructive (Delete/Dangerous)**
- Background: #EF4444
- Text: White
- Hover: Darker red (#DC2626)
- Confirm before action

**Ghost (Minimal)**
- Background: Transparent
- Text: #3B82F6
- Hover: Light blue background (#EFF6FF)

**Outline (Secondary)**
- Background: Transparent
- Border: 1px #E2E8F0
- Text: #0F172A
- Hover: Light gray background

### Input & Form Elements

**Text Input**
- Border: 1px #E2E8F0
- Padding: 8px 12px
- Radius: 6px
- Focus: Blue ring (2px), blue border
- Error state: Red border, error message below
- Disabled: Gray background, text opacity 50%

**Select/Dropdown**
- Similar to text input
- Dropdown arrow on right
- Open state: Blue border, dropdown menu appears

**Checkbox & Radio**
- Size: 16x16px
- Checked: Blue background, white checkmark
- Focus: Ring around element

**Label**
- Font: 14px, 500 weight
- Color: #0F172A (light), #FFFFFF (dark)
- Spacing: 4px above input
- Required: Red asterisk after label text

### Card Layout

**Container**
- Background: White (#FFFFFF light), Slate 900 (#0F172A dark)
- Border: 1px #E2E8F0 (light), 1px #334155 (dark)
- Padding: 24px
- Radius: 8px
- Shadow: Soft elevated (0 4px 6px -1px rgba(0,0,0,0.1))

**Sections**
- CardHeader - Top section with title
- CardTitle - Card heading (18px, 600 weight)
- CardDescription - Subheading (14px, secondary color)
- CardContent - Main content area
- CardFooter - Bottom actions/metadata

### Navigation

**Topbar/Header**
- Height: 64px
- Background: White/dark with subtle border
- Items: Logo, breadcrumbs, user menu
- Spacing: 16px horizontal padding

**Sidebar (Future)**
- Width: 256px (collapsed: 64px)
- Background: Subtle shade
- Items: Navigation links with icons
- Active state: Blue highlight + underline

**Breadcrumbs**
- Size: 14px, secondary color
- Separator: "/" slash
- Last item: Bold, current page

---

## Responsive Design

### Breakpoints

| Breakpoint | Width | Usage |
|-----------|-------|-------|
| **Mobile** | 320px | Phone (small) |
| **sm** | 640px | Phone (large) |
| **md** | 768px | Tablet |
| **lg** | 1024px | Desktop |
| **xl** | 1280px | Large desktop |
| **2xl** | 1536px | Ultra-wide |

### Layout Strategy

**Mobile First:**
```css
/* Base styles (mobile) */
.card { width: 100%; padding: 16px; }

/* Tablet & up */
@media (min-width: 768px) {
  .card { width: calc(50% - 8px); }
}

/* Desktop & up */
@media (min-width: 1024px) {
  .card { width: calc(33.333% - 11px); }
}
```

### Common Layouts

**Full Width Container**
- Max-width: 1280px
- Horizontal padding: 16px (mobile), 32px (desktop)
- Centered with margin: 0 auto

**Two Column Grid**
- Mobile: 1 column
- Tablet: 2 columns
- Gap: 16px

**Three Column Grid**
- Mobile: 1 column
- Tablet: 2 columns
- Desktop: 3 columns
- Gap: 16px

---

## Interactive States

### Focus State
- Ring: 2px #3B82F6
- Offset: 2px
- For keyboard navigation (Tab key)

### Hover State
- Opacity adjustment (typically -10%)
- Or background color shift
- Cursor pointer for clickable elements

### Active/Pressed State
- Darker color (15-20% darker)
- May include slight scale (0.98x)

### Disabled State
- Opacity: 50%
- Cursor: not-allowed
- No hover effects

### Loading State
- Spinner animation (60% opacity)
- Or skeleton loading (light gray pulsing)
- Text: "Loading..."

### Error State
- Border: Red (#EF4444)
- Background: Very light red tint (#FEE2E2)
- Error message: Red text below element

### Success State
- Border: Green (#22C55E)
- Icon: Green checkmark
- Message: "Success" or specific confirmation

---

## Animations & Transitions

### Duration Standards

| Speed | Duration | Usage |
|-------|----------|-------|
| **Instant** | 0ms | Immediate feedback |
| **Fast** | 100ms | Hover, focus states |
| **Normal** | 200ms | Menu open/close |
| **Slow** | 300ms | Page transitions |

### Easing Functions

```css
/* Standard easing */
--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1);
--ease-out: cubic-bezier(0, 0, 0.2, 1);
--ease-in: cubic-bezier(0.4, 0, 1, 1);
```

### Common Animations

**Fade In**
```css
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
animation: fadeIn 200ms ease-out;
```

**Slide In**
```css
@keyframes slideInDown {
  from { transform: translateY(-10px); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}
animation: slideInDown 200ms ease-out;
```

**Spinner**
```css
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
animation: spin 1s linear infinite;
```

---

## Dark Mode

### Implementation

**CSS Variables Approach:**
```css
:root {
  --background: #FFFFFF;
  --foreground: #0F172A;
}

@media (prefers-color-scheme: dark) {
  :root {
    --background: #0F172A;
    --foreground: #FFFFFF;
  }
}

/* Usage in components */
background-color: var(--background);
color: var(--foreground);
```

### Manual Toggle (Future)
```html
<html class="dark">
  <!-- Dark mode active -->
</html>
```

### Contrast Adjustments

In dark mode:
- Increase border opacity/brightness
- Use lighter text colors
- Avoid pure black backgrounds (use Slate 900)
- Ensure 4.5:1 contrast for body text

---

## Accessibility Guidelines

### WCAG 2.1 AA Compliance

| Criterion | Implementation |
|-----------|---|
| **Color Contrast** | 4.5:1 for body text, 3:1 for large text |
| **Focus Visible** | Blue ring on all interactive elements |
| **Alt Text** | Descriptive alt text on all images |
| **Labels** | Associated labels on form inputs |
| **Keyboard Nav** | Full functionality via Tab/Enter |
| **ARIA** | Appropriate ARIA roles & attributes |

### Common Patterns

**Skip to Content Link:**
```html
<a href="#main-content" class="sr-only">Skip to main content</a>
```

**Form Validation:**
```html
<input aria-invalid="true" aria-describedby="email-error" />
<span id="email-error" class="error">Invalid email format</span>
```

**Loading State:**
```html
<div role="status" aria-live="polite">Loading...</div>
```

**Modal Dialog:**
```html
<div role="dialog" aria-modal="true" aria-labelledby="dialog-title">
  <h2 id="dialog-title">Confirm Action</h2>
</div>
```

---

## Component Library: Shadcn/UI

All UI components use Shadcn/UI with Radix UI primitives:

### Installed Components
- ✅ Button - Variant-based button system
- ✅ Input - Form text input
- ✅ Label - Associated form labels
- ✅ Select - Dropdown selection
- ✅ Card - Content container
- ✅ Badge - Status indicators
- ✅ Alert - Alert messages
- ✅ DropdownMenu - Context menus
- ✅ Separator - Visual dividers

### Component Usage Example

```tsx
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export function LoginForm() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Sign In</CardTitle>
      </CardHeader>
      <CardContent>
        <Input type="email" placeholder="Email address" />
        <Input type="password" placeholder="Password" />
        <Button className="w-full">Sign In</Button>
      </CardContent>
    </Card>
  )
}
```

---

## Internationalization (i18n)

### Language Support
- **English** (en) - Default
- **Vietnamese** (vi)
- **French** (fr)

### Translation Guidelines

**File Location:** `messages/{locale}.json`

**Example:**
```json
{
  "common": {
    "save": "Save",
    "cancel": "Cancel",
    "delete": "Delete"
  },
  "auth": {
    "login": "Sign In",
    "email": "Email Address",
    "password": "Password"
  }
}
```

**Usage in Components:**
```tsx
import { useTranslations } from 'next-intl'

export function LoginButton() {
  const t = useTranslations('auth')
  return <Button>{t('login')}</Button>
}
```

---

## Design System Evolution

### Future Enhancements
- [ ] Expanded component library (Tabs, Accordion, etc.)
- [ ] Animation library for common patterns
- [ ] Icon system documentation
- [ ] Data visualization guidelines
- [ ] Mobile gesture guidelines
- [ ] Voice & tone guidelines
- [ ] Illustration style guide

### Version History
- **v1.0** (2026-01-28) - Initial fintech minimalist system with core components
