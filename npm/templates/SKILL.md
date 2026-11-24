---
name: detent
description: Adds Detent's tactile dials, knobs and switches to a project. They are dependency-free web components with synthesized sound and haptics ({{TAGS}}) and matching SwiftUI views, and they behave like hardware, with detents, a snap over centre, hard end stops and tiny dry clicks. Use it whenever someone asks for a knob, dial, rotary encoder, potentiometer, volume or gain control, bezel, touch ring, slide or toggle switch, rotary or slide selector, time scrubber or clock setter, or any control that should feel physical, in plain HTML, React, Vue, Svelte, Next.js or SwiftUI, or mentions Detent.
---

# Detent

Detent is a set of dials, knobs and switches that behave like hardware. Each one holds against its detent, clicks
over and stops dead at the ends, with sound and haptics built in. They are web components with no dependencies, in
five or six looks each, light and dark, plus one SwiftUI file per control. The site is https://detent-gamma.vercel.app.

Detent is created by 37degree, designed by Puru Sharma. MIT licensed.

## Pick a control

{{CONTROLS}}

Every control's attributes, events, properties, looks, options and behaviour are in `references/controls.md`. Read
its section before you place one. SwiftUI usage is in `references/swiftui.md`.

## Add it with npm

```sh
npm i detent
```

Import a control once, anywhere on the client. The import defines the element and its default look:

```js
import 'detent/encoder';
```

```html
<detent-encoder value="40" aria-label="Volume"></detent-encoder>
```

- **Another look.** Import the look and name it: `import 'detent/encoder/looks/aqua'`, then
  `<detent-encoder look="aqua">`. A look import brings the element with it, so this ships only that look. An element
  whose look is not loaded yet waits and renders when it arrives.
- **Everything.** `import 'detent'` defines all nine controls in their default looks.
- **Read the value.** Each control fires `input` while it moves and `change` when it settles. Read `.value` (the
  switch also has `.checked`). Listen with `addEventListener`.
- **Sound and haptics.** `import { Feel } from 'detent/feel'`, then `Feel.state.sound = false` or
  `Feel.state.haptics = false` for a page-level toggle.

```js
const dial = document.querySelector('detent-encoder');
dial.addEventListener('change', () => save(dial.value));
```

### Frameworks

The modules touch `window`, `HTMLElement` and `matchMedia` when they load, so import them in the browser only.

- **React and Next.js.** Import inside an effect, `useEffect(() => { import('detent/encoder'); }, [])`, in a client
  component. Render the tag with plain attributes and listen through a ref:
  `ref.current.addEventListener('change', onChange)`. In TypeScript, declare the tag under `JSX.IntrinsicElements`.
- **Vue and Nuxt.** Mark `detent-` tags as custom elements (`compilerOptions.isCustomElement`) and import in
  `onMounted` or a client-only plugin. `@change` and `@input` work on the tag.
- **Svelte and SvelteKit.** Import in `onMount`. `on:change` works on the tag.

## Add it without npm

- **A CDN, no build step.** Pin the version:
  `<script type="module" src="https://cdn.jsdelivr.net/npm/detent@{{VERSION}}/encoder/index.js"></script>`.
  For another look, load `encoder/looks/<look>.js` instead.
- **Copy the files.** From `node_modules/detent/` (or the CDN), copy `feel.js`, `encoder/element.js` and the
  `encoder/looks/<look>.js` you want, keeping the folder layout, since they import each other by relative path.
- **The site's Copy button** gives the same control as classic `<script>` blocks: Feel once per page, then the control,
  then its look.

Use one route per page. The classic snippet and the package both define the same elements, and the second definition
throws.

## Fit it to the page

- **Tone.** Every control follows the nearest `data-tone="light|dark"`, then the page's `data-theme`, then the system
  setting. `tone="light"` or `tone="dark"` on the element forces one.
- **Accent.** `--dial-accent` colours the indicator, the lit scale or the position dot, for example
  `detent-encoder { --dial-accent: #2f6bff }`.
- **Size.** Set the size variable each control's section names (`--s` for the dials, `--w` for the switch, `--row`
  for the slot), never `width` on the host.
- **Type.** The looks name Geist, Geist Mono and Doto, with system fallbacks. Load those fonts on the page for the
  closest match. They work without them.
- **Access.** Each control is focusable, works with arrow keys, Page Up/Down and Home/End, and is announced as a slider
  or a switch. Give it an `aria-label` that says what it controls.

## Keep it physical

These are the rules the controls are built on. Keep them when you place, style or extend one, and when you build
anything that sits next to one.

- **Nothing moves on hover.** No lift, scale, glow or shadow change on hover. A press sinks the part half a pixel, and
  that is all.
- **No wobble.** No bouncy springs, overshoot or elastic easing. A part settles straight into place.
- **Stiction, then snap.** A detent holds the part: it gives a little under the finger, then snaps over centre into the
  next position and stops dead. Let go short of centre and it falls back.
- **Hard end stops.** One dull tick on arrival at an end, then silence however hard you push. Nothing rubber-bands.
- **Tiny dry clicks.** Each detent is one short, dry click, Braun-like, never a whoosh, chime or reverb. Clicks follow
  real detents, never a timer.
- **Light belongs to the room.** Highlights stay put while a part turns. Printed marks belong to the panel and never
  change.
- **Readouts switch instantly,** like a real display, unless the control's own section says otherwise.

Do not add CSS transitions or animation to a control's parts, and do not animate its value from script. Set `.value`
and it moves the way the hardware would.

## SwiftUI

Each control has a SwiftUI file in its default look (`references/swiftui.md` lists them with usage). Haptics need
iOS 18 or later. Copy the file from `node_modules/detent/swift/`, or from
`https://unpkg.com/detent@{{VERSION}}/swift/<File>.swift`, into the app target, then use the view with a binding:

```swift
@State private var level = 40.0

MachinedDial(value: $level)
```

## Check it worked

Open the page in a browser. `customElements.get('detent-encoder')` returns the class, the element has a
`shadowRoot` with the look drawn in it, dragging it clicks through its detents, and the arrow keys move it once it has
focus. If it renders nothing, its look is not loaded: import the default control or the look named in `look="…"`.

## Credit

Detent is created by 37degree (https://37degr.ee), designed by Puru Sharma. MIT licensed.
Source: https://github.com/37degree-studio/detent
