---
name: Octria
description: The viewer's own course, overprinted in magenta on the team's plan.
colors:
  ground: "#F2F5FA"
  ground-dark: "#0E1116"
  ambient-ember: "#FFE8D4"
  ambient-ember-dark: "#2A1406"
  ambient-amber: "#FFF2E4"
  ambient-amber-dark: "#1E0F05"
  ambient-sand: "#FFF6EC"
  ambient-sand-dark: "#170B04"
  glass-thin: "#FFFFFF73"
  glass-thin-dark: "#1C20286B"
  glass-regular: "#FFFFFF94"
  glass-regular-dark: "#1C20288C"
  glass-thick: "#FFFFFFD1"
  glass-thick-dark: "#1C2028D6"
  rim-top: "#FFFFFFE6"
  rim-top-dark: "#FFFFFF47"
  rim-bottom: "#FFFFFF40"
  rim-bottom-dark: "#FFFFFF0F"
  sheen: "#FFFFFF33"
  sheen-dark: "#FFFFFF12"
  node-top: "#FFFFFFE6"
  node-top-dark: "#333945D9"
  node-bottom: "#FFFFFFB8"
  node-bottom-dark: "#272C36B8"
  node-rim: "#1C274433"
  node-rim-dark: "#FFFFFF1F"
  raised: "#FFFFFF"
  raised-dark: "#23272F"
  hairline: "#1C27441F"
  hairline-dark: "#FFFFFF1F"
  outline: "#AAB2C4"
  outline-dark: "#4C5462"
  control: "#1C274414"
  control-dark: "#FFFFFF1F"
  ink: "#1B1F27"
  ink-dark: "#F2F4F8"
  ink-soft: "#474E5C"
  ink-soft-dark: "#C3C8D2"
  ink-faint: "#5C6372"
  ink-faint-dark: "#A2A8B4"
  overprint-magenta: "#C2187A"
  overprint-magenta-dark: "#F2589F"
  on-overprint: "#FFFFFF"
  on-overprint-dark: "#2A0518"
  status-done: "#1F7F4C"
  status-done-dark: "#55BD84"
  status-doing: "#1A67AD"
  status-doing-dark: "#6AB0EA"
  status-review: "#B26A00"
  status-review-dark: "#F5B544"
  status-waiting: "#7E8494"
  status-waiting-dark: "#8B919E"
  status-blocked: "#CE2F26"
  status-blocked-dark: "#F2675D"
  terrain-a: "#FFFFFF38"
  terrain-a-dark: "#FFFFFF0D"
  terrain-b: "#FFFFFF1F"
  terrain-b-dark: "#FFFFFF08"
  float-shadow: "#1B2A4A26"
  float-shadow-dark: "#00000073"
typography:
  next-step:
    fontFamily: "Inter"
    fontSize: "25px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.6px"
    fontVariation: "'wght' 700"
  title:
    fontFamily: "Inter"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.4px"
    fontVariation: "'wght' 700"
  heading:
    fontFamily: "Inter"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.2px"
    fontVariation: "'wght' 600"
  body:
    fontFamily: "Inter"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "-0.05px"
    fontVariation: "'wght' 400"
  label:
    fontFamily: "Inter"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0px"
    fontVariation: "'wght' 500"
  caption:
    fontFamily: "Inter"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0.05px"
    fontFeature: "'tnum'"
    fontVariation: "'wght' 500"
  micro:
    fontFamily: "Inter"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0.05px"
    fontFeature: "'tnum'"
    fontVariation: "'wght' 500"
rounded:
  plate: "11px"
  bar: "6px"
  badge: "8px"
  item: "12px"
  card: "16px"
  panel: "18px"
  sidebar: "24px"
  sheet: "28px"
  pill: "999px"
spacing:
  chip-gap: "6px"
  gap: "8px"
  inset-narrow: "12px"
  inset: "16px"
  panel: "18px"
  section: "22px"
  isolate: "56px"
components:
  button-prominent:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "44px"
  button-standard:
    backgroundColor: "{colors.control}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
    height: "36px"
  button-standard-hover:
    backgroundColor: "{colors.hairline}"
  button-quiet:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
  button-quiet-hover:
    backgroundColor: "{colors.control}"
  button-quiet-destructive:
    textColor: "{colors.status-blocked}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
  button-my-focus-active:
    backgroundColor: "{colors.overprint-magenta}"
    textColor: "{colors.on-overprint}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
  chip:
    backgroundColor: "{colors.control}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 12px"
  chip-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
  glass-panel:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
  next-step-card:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    typography: "{typography.next-step}"
    rounded: "{rounded.panel}"
    padding: "12px 14px 13px"
    width: "320px"
  step-card:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    typography: "{typography.heading}"
    rounded: "{rounded.panel}"
    padding: "12px"
    width: "180px"
    height: "112px"
  phase-card:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.card}"
    height: "116px"
  list-group:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
  sidebar-item-selected:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "9px 10px"
  tab-bar:
    backgroundColor: "{colors.glass-regular}"
    textColor: "{colors.ink}"
  swipe-to-done:
    backgroundColor: "{colors.control}"
    textColor: "{colors.ink-soft}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    height: "50px"
---

# Design System: Octria

## Overview

**Creative North Star: "The Overprint Course"**

Octria draws a plan the way an orienteering map draws a course: a quiet printed base of terrain and other people, with one magenta line laid over the top that belongs to whoever is holding the map. The viewer's next step is the one thing on the sheet they cannot miss. Everything else stays legible and stays back.

The sheet is calm by default and dense on request. A still, soft-coloured ground, pale translucent bands per phase and hairline lane rules make up the base; quiet ink carries the team; status keeps the colours a map reader already knows. One continuous zoom takes the same sheet from phases, to step rectangles, to full inline cards, and content changes with scale so text never turns to clutter. The chrome around the sheet is Apple-style glass that floats over the map, so the only unfamiliar thing on screen is the map itself, and it earns that.

Steps are rectangles, by the user's decision, because they hold the step's status, date and name in one readable place. What keeps the graph from being a generic board is the magenta route and the member lanes, not the shape of a step. It must not feel overwhelming at first, or gamified or childish.

**The One Look Rule.** Binding decision by the product's owner: Octria wears one Apple-style look on every platform (Android, iOS, web, Windows, macOS, Linux), chosen over per-OS native chrome. There is no Material variant and no per-platform restyle. The look never overrides the platform's behaviour: Android Back and the system's settings for appearance, text size, reduced motion and contrast are always honoured.

**The Glass Rule.** Binding decision by the product's owner: the interface is Apple-style glass, with translucent chrome floating over a canvas that runs underneath it. This replaced the earlier opaque toolbar and the map's contour rings. Performance outranks the material: a device that can't keep up loses real blur, not smoothness.

**Key Characteristics:**
- One magenta overprint, reserved for the viewer's own route and own work.
- Every status is a drawn mark first and a colour second.
- A map running underneath floating glass, on a warm ground with a slow orange globe turning behind it.
- One continuous zoom axis, shared by drawing and hit testing.
- Standard Cupertino controls, spring motion, feedback on the press.
- One workhorse sans with tabular dates.
- Full light and dark, following the system.

## Colors

Warm neutrals on a soft orange-touched ground, with map-convention status hues and a single loud overprint. Each role has a light and a dark value, chosen by the system's appearance; never ship a new colour with only one.

### Primary
- **Overprint Magenta** (#C2187A light, #F2589F dark): the viewer's course and nothing else. It draws the route line, the heavy outline of the next step, the outline of the viewer's other steps and timeline bars, their lane avatar, their dots on the far view and minimap, the outline of the phase holding their next step, the ring on the next-step card, "Your next step" in the list, and Focus on me while it is active.
- **On Overprint** (#FFFFFF light, #2A0518 dark): text and icons sitting on a magenta fill.

### Secondary
Status colours follow map convention and appear on status marks, dependency arrows and timeline bars.
- **Done Green** (#1F7F4C light, #55BD84 dark): finished steps, arrows leaving finished steps, the unlock sweep and ripple, and the swipe-to-done thumb.
- **Approval Amber** (#B26A00 light, #F5B544 dark): steps waiting for approval.
- **Under-Way Blue** (#1A67AD light, #6AB0EA dark): steps in progress, and arrows leaving them. Also the 2px keyboard focus ring on buttons.
- **Waiting Grey** (#7E8494 light, #8B919E dark): steps waiting on another step, and arrows leaving unstarted steps.
- **Blocked Red** (#CE2F26 light, #F2675D dark): blocked steps, arrows into them, overdue dates, and destructive labels.

A step that is ready to start uses plain ink: an open ring, ready and unremarkable until it is yours.

### Tertiary
The ground and terrain. They give the glass something to pick up, and never carry status.
- **Ambient** (#FFE8D4, #FFF2E4, #FFF6EC light; #2A1406, #1E0F05, #170B04 dark): three large soft warm glows on the ground, behind every view. They never move. High contrast removes them.
- **Orb** (#EA7A1E light, #FF8C2E dark): the globe behind every view, a soft light inside fine lines, like a calm assistant at rest. One turn takes 90 seconds at about 24 frames a second. It holds still under Reduce Motion or on a device that can't keep up, and goes away with more contrast. Orb is used for nothing else.
- **Terrain A and B** (white at 22% and 12% light; 5% and 3% dark): phase bands. Phases cycle A, none, B, none.

### Neutral
- **Ground** (#FBF7F2 light, #0E0B09 dark): the base under the ambient glows, and the fade at the status bar.
- **Glass** thin, regular and thick (white at 45%, 58%, 82% light; #1C2028 at 42%, 55%, 84% dark): how much of a pane is material. Regular for bars, cards and sticky headers; thick for anything read at length.
- **Rim and Sheen** (rim white 90% to 25% light, 28% to 6% dark; sheen white 20% light, 7% dark): light along a pane's top edge, fading down.
- **Node** (white 90% to 72% light; #333945 85% to #272C36 72% dark, with a Node Rim): a step or phase card on the canvas.
- **Raised** (#FFFFFF light, #23272F dark): solid glass in high contrast, and the add-a-dependency handle.
- **Control** (ink at 8% light, white at 12% dark): resting buttons, chips, selected sidebar item, tab highlight, avatars for other members, the progress ring track.
- **Hairline** (ink at 12% light, white at 12% dark): lane rules, list dividers, hover on a standard button.
- **Ink** (#1B1F27 light, #F2F4F8 dark): primary text, prominent buttons, selected states, the minimap frame, the Today line.
- **Soft Ink** (#474E5C light, #C3C8D2 dark): secondary text and the progress ring arc.
- **Faint Ink** (#5C6372 light, #A2A8B4 dark): dates, captions, disabled text.

### Named Rules

**The Overprint Rule.** Magenta means "this is yours". If a mark does not belong to the person looking at it, it cannot be magenta. Generic primary actions are ink, not magenta, and so is selection of someone else's step.

**The Map Colours Rule.** Green, blue, grey and red mean status, plus the few uses named above. They are never decoration, category colours or per-member identity.

**The Terrain Rule.** Terrain bands stay faint enough that all ink and status colours hold on top of them, and they mark phases only.

## Typography

**Display Font:** Inter (bundled variable font; no fallback is declared because the font ships with the app)
**Body Font:** Inter
**Label/Mono Font:** Inter, with tabular figures on captions

**Character:** A single plain workhorse sans, so that all the personality in the product stays on the map. Tracking tightens as text grows; body stays near zero.

### Hierarchy
- **Next step** (700, 25px, 1.2, -0.6px): the "Next: ..." line on the floating card, wide layouts only. It is the largest type in the product because it answers the product's main question. On phones the same line uses Title.
- **Title** (700, 20px, 1.2, -0.4px): classroom name, step name in the panel, phase names in the list.
- **Heading** (600, 16px, 1.25, -0.2px): phase strip names, step names on full cards, panel headings.
- **Body** (400, 14px, 1.4, -0.05px): descriptions and list rows. The next step's row steps up to 600.
- **Label** (500, 13px, 1.25, 0): buttons, chips, sidebar items, section labels, map labels. The viewer's own step labels step up to 600; other people's stay at 500.
- **Caption** (500, 12px, 1.25, 0.05px, tabular figures): dates, counts, member names in the gutter.
- **Micro** (500, 11px, 1.25, 0.05px, tabular figures): only change badges and avatar initials, inside their 16px to 28px shapes.

### Named Rules

**The One Workhorse Rule.** Inter is the only family. Emphasis comes from weight and from the colour of the ink, never a second face.

**The Set The Axis Rule.** Inter is a variable font: whenever weight changes, set the weight axis with it, or the real cut is not used.

**The Tabular Dates Rule.** Dates and counts use tabular figures so they line up down a list or timeline.

## Layout

The graph, called Flowspace, is a pannable map rather than a page. Phases are columns running left to right, members are lanes running top to bottom with the viewer's lane first. The canvas fills the whole window and runs under the floating bars, but it frames, centres and stops scrolling within the part they leave clear. A sticky glass lane column (92px, 44px on phones) and a sticky glass phase capsule (44px, 28 to 34px on phones) hold their places while the map moves beneath.

The shell is one layout with three arrangements:
- **Wide (840px up):** a 232px glass sidebar inset 10px, a 52px glass capsule toolbar with the classroom title, Flowspace/Timeline/List segments, Filter and Focus on me (icon-only under 900px of room). Step details open as a 360px glass panel inset 10px from the right.
- **Narrow:** a 52px capsule with the title, classroom switcher and icon-only controls at 44px, a floating 56px capsule tab bar up to 340px wide, and step details in a bottom sheet with detents at 42% and 8% from the top that covers the tab bar.
- **Short (under 500px tall):** one slim 44px capsule holding the classroom, next step, view switcher and every map control, and no tab bar.

Floating controls sit at the corners of the clear area: the next-step card top right (320px wide) on wide canvases, zoom controls and a 176 by 104 minimap bottom right from 600px of canvas width. Below that, a row above the tab bar holds a fit-and-key capsule and the next step as a pill, and the sticky column stops above that row so glass never sits on glass. The next-step card fades out when it would cover the very step it names, or when a step's panel is open.

The list view is a single column capped at 760px that scrolls under the bars. The timeline pins a 200px name column (136px under 600px) while dates scroll, with a day between 14px and 30px wide, opening on today.

Spacing is hand-set to the element rather than a strict scale: 6px between chips, 8px and 12px between toolbar items, 16px canvas insets (12px on narrow), 18px panel insets, 22px above a panel section, 56px around anything destructive.

**The One Zoom Axis Rule.** Scale runs continuously from 0.16 to 2.6, and every change of content is a function of scale, used for both drawing and hit testing. Phase cards fade out between 0.26 and 0.40. Arrowheads appear above 0.34, badges above 0.42, labels above 0.44, dates above 0.62 (always, for the next step), avatars above 0.72. Full step cards grow from marks between 1.2 and 1.55. The route is drawn at every scale. There are no discrete zoom modes.

**The Words On Top Rule.** A step's words sit inside its rectangle, drawn after every wire and rule, so no line ever runs across them. The rectangle stays at least 72% solid, so the route showing faintly behind it never costs legibility.

## Elevation & Depth

Three layers: a warm ground with its slow globe, the map, and glass floating over it. Glass panes blur what is behind them by 18 sigma with a saturation lift, then add a translucent fill, a sheen fading down from the top, and a 1px rim lit along the top edge. All panes share one backdrop through a `BackdropGroup`, so a pane over another pane never blurs it twice.

Steps and phase cards are drawn glass, not real glass: a lit gradient, a lit rim and two offset shadow shapes, with no blur, so a 600-step plan stays smooth. Below scale 0.34 they lose even that and go flat. The next step adds a soft magenta glow under it.

### Shadow Vocabulary
- **Float** (in Float Shadow, #1B2A4A26 light, #00000073 dark): on glass panes, deeper with weight: `0 4px 12px` thin, `0 6px 20px` regular, `0 10px 28px` thick.
- **Plate** (Float Shadow at half strength, offset 1.5px and 4px, unblurred): on steps and phase cards above scale 0.34.

### Named Rules

**The Solid When Asked Rule.** When the system asks for more contrast, glass goes solid: Raised at full strength, no blur, a full-ink edge, and no ambient glows.

**The Glass Budget Rule.** If over a third of 120 frames take more than 22ms to draw, panes drop real blur for the rest of the session and thicken to stay readable. Nothing else changes.

**The One Pane Rule.** Never place a light translucent surface over another for reading. Thick panes cover what's beneath them; a sheet covers the tab bar rather than sliding under it.

## Shapes

Soft rectangles and capsules over a world of true circles. Circles belong to the marks: status marks, avatars, rings, handles. Capsules belong to anything you press or that runs along an edge: buttons, chips, the toolbar, tab bar, phase strip, next-step pill and swipe track. Rounded rectangles hold content, with radius growing with size: 4px for the minimap frame, 6px for timeline bars, 11px for step rectangles (15px as full cards), 12px for sidebar items, 16px for phase cards, 18px for list groups, map controls and floating cards, 24px for the sidebar and step panel, 28px for the bottom sheet.

Dependency wires leave and enter rectangles at their own fanned-out points and run horizontally, with one vertical run on their own track in the gap before the target's column and rounded corners. They end in a filled arrowhead drawn above the route. Arrows between two finished steps fade to 30%; with a step selected or hovered, its own arrows thicken and the rest fade to 28%. Tapping an arrow draws it in ink above the steps, with a dot where it starts and a large arrowhead where it ends, tags both steps From and To, and dims everything else; a bar names both ends, and tapping a name moves there while the arrow stays highlighted.

## Components

### Buttons
Standard, tactile and quick: feedback lands on the press.
- **Shape:** a capsule. 36px tall on pointer layouts, 44px anywhere it is the touch target; icon-only buttons are round.
- **Prominent:** ink fill with ground-coloured text, for the single main action in a panel ("Start step").
- **Standard:** Control fill with ink text. Hover moves to Hairline.
- **Quiet:** no fill, ink text. Hover moves to Control. Used for icon stacks, menus and secondary actions.
- **Destructive:** Quiet with Blocked Red text. Never filled.
- **Focus on me:** a standard button that turns magenta while active, because it is about the viewer.
- **Press / Focus / Disabled:** scales to 0.97 instantly on press, returning in 160ms; a selection haptic on activation. Keyboard focus draws a 2px Under-Way Blue border. Disabled is half-strength Control with Faint Ink.

### Chips
- **Style:** a compact capsule button, Control fill with ink text, gapped 6px. Chips filter the plan and choose a step's owner.
- **State:** selected is an ink fill with ground-coloured text. They are compact for pointer layouts and must meet the 44px touch rule on touch layouts.

### Cards / Containers
- **Glass panel:** see Elevation. 18px radius by default, capsule for bars.
- **Next-step card:** a glass panel with a magenta open ring, the "Next: ..." line, and one plain sentence saying why it is next and when it is due. It takes you to the step when tapped.
- **List group:** Glass Regular with no blur, because only the still ground is behind it. 18px radius, faint rim, dividers indented 48px past the marks, rows at least 52px tall.

### Navigation
- **Views:** Cupertino sliding segmented control (Flowspace, Timeline, List) on wide layouts; a floating glass capsule of three tabs on narrow, with a sliding Control highlight behind the active one, ink active and Soft Ink inactive.
- **Sidebar items:** 13px label, 12px radius. Selected is Control with ink text at 600; hover is Hairline; rest is Soft Ink with no fill.
- **Home look:** near-black graphite in dark and crisp off-white in light, over a fine dot grid. Solid panels with hairline edges carry the home pages, with glass kept for what floats. Indigo, violet, warm yellow and teal separate kinds of things (task types, activity kinds, stat tiles) in soft icon squares; none of them means status, and magenta stays the viewer's. Rings fill as they appear: a ticked dial on each classroom and concentric rings for the viewer's own steps, always with a key.
- **Lanes:** each person's steps run in due order along the flow, whichever way it runs, joined by dashed arrows. Yours are in the route colour, teammates' in a quiet neutral. A dashed arrow is an order, a solid one a real link.
- **Home:** after sign-in, five destinations: Dashboard, Activity, a small round add button, Timeline and Profile. A floating capsule at the bottom on phones, a side rail from 840px up. The dashboard greets by name, shows three stat tiles and the most pressing step, then a search box over a grid of square classroom cards, each with a progress ring that fills as it appears.
- **Classroom switcher on narrow:** the title with a small chevron opens a Cupertino action sheet that only switches classrooms. Everything else about the classroom is under a More tab in the bottom capsule, beside Profile.
- **Red count:** a red number raised over the corner, like a phone's app icon, marks unseen changes on Since you were away and on the More tab. Red here means "new", the one use outside status. Opening Since you were away clears it; there's no popup.
- **Activity cards:** log entries sit in bordered cards with an icon, the sentence and the time to the second, under a heading for each day, then grouped by hour with a line tying each hour's entries together. Only the latest day starts open. The master can delete an entry or clear the log.
- **Android Back:** dismisses what is open before leaving: context menu, filter panel, selected step.

### Step Marks
Six drawn circles that read in greyscale: **done** a filled disc with a check, **in progress** a half-filled disc, **in review** a ring with a centre dot, **ready** an open ring, **waiting** a thin ring with a tiny centre dot, **blocked** a ring with a diagonal slash. The same drawing is used on the graph, cards, panels, lists, the timeline and the map key, which names every mark and line in one place. 

### Step Rectangles
A step is a rounded rectangle, 176 by 104 at full scale, never narrower than 104px or shorter than 48px unless the column or lane would crowd it. It holds a status mark, the due date and up to three lines of title; below 60px tall or 124px wide it shrinks to the mark and two lines, and below scale 0.44 to the mark alone. Other people's steps add an owner avatar when 150px wide. It grows continuously into the full card on zoom. Outlines carry ownership: a lit 1px rim for others, 2px magenta for yours, 3.4px magenta for your next step, with a 2px ink ring outside when selected. Titles use 12px on narrow rectangles so long words stay whole.

**The Status Colour Rule.** Decided by the product's owner: a step's whole rectangle shows its status in a solid fill, deep rather than bright, with its drawn mark at the top left and the status in words at the bottom. Blue for in progress, amber for waiting for approval, green for done, red for blocked, faint grey for ready. Steps waiting on another stay plain, at 72%. Nothing glows: the owner tried a glow and chose to drop it, so the fill, a coloured edge, the mark and the word carry it. Fills are mixed from an opaque base, and words on them use full ink at 600, so they stay readable. A late date says "Late" in words. Your magenta outline goes around all of it.

**The Drawn Mark Rule.** Every status is a drawn mark as well as a colour, so it reads without colour. On a filled step the mark sits on a small disc of the ground colour, and the status is also written out when the step has room.

### Framing and Short Screens
A classroom opens on the whole plan when it fits at 0.7 scale or better; otherwise on the next step's whole phase when that is readable at 0.5 or closer and shows at least three people; otherwise on the closest view, down to 0.42, that holds the next step and at least three people's steps whole on screen. Rectangles keep a 66px minimum height where the lane allows, and narrow ones give names up to three lines. Tapping a phase's name fits all of it at any size. Turning the device reframes. On phones the member column is 44px of avatars and the phase strip 28 to 34px, and the next step is a one-line pill. Below 500px tall there is one slim bar holding the classroom, next step, an icon view switcher and every map control, with nothing else floating over the map; below 420px of canvas the lane rows tighten to 112 units. Left and right safe-area insets are always respected.

### Background
A moon or sun button in every top bar switches between the white and dark backgrounds, in every view. It follows the system until someone chooses, and the choice lasts until the app closes; it isn't saved yet. The app draws edge to edge, with transparent system bars whose icons follow it.

### Graph Direction
The graph flows left to right by default, and a toggle in the toolbar, or the V key, switches it to top to bottom. Top to bottom makes phases rows and members columns: members stay along the top strip and phase names along the left edge, turning on their side in a phone's slim column. Arrows leave the bottom of a step and enter the top of the next, with their tracks in the gap between rows. Steps glide to their new places on the switch. The choice lasts until the app closes; it isn't saved yet.

### The Route
The signature. A 2.4px to 3.6px round-capped magenta line through the viewer's steps in order, drawn over all other wires and through every zoom level. It only exists for the viewer, so it must never pass for a link everyone shares: where a step really depends on the one before, it's solid with a thin bright core, like a tube of light; elsewhere it's dashed, meaning only the order of their work. Finished stretches drop to 45% alpha, so the course ahead is the strongest thing on the map. The line runs from edge to edge of the viewer's rectangles, so it stays clear of their words.

### Dependency Wires
1.6px curves, coloured by the status of the work they carry and fading with the emphasis of their ends. The critical path is a cased line, like a main road: an ink casing at 42% under the wire, named in the map key.

### Step Cards
Past 1.2 zoom a mark grows into a 180 by 112 world-unit card, scaling with the camera: mark and status at top left, due date at top right, heading, description, then a caption of counts. Other people's cards have the lit rim; yours are 2px magenta, 3.4px for your next step. A selected card that is not yours is outlined in ink.

### Phase Cards and Progress Rings
At the far zoom phases become 116px-tall drawn-glass cards with a name, an "n of m done" caption and a ring. The phase holding the viewer's next step takes a 3px magenta outline.

**The Thin Ring Exception.** Brief-earned, not a licence: the product's plan calls for phases as large cards with a progress ring each. The ring is a 3px stroke of 13px radius, one Soft Ink arc on a Control track, with plain butt ends and no magenta, green or animation. It is a quiet measure of progress, not a reward, and it appears only on phase cards.

### Focus and Filter
Focus on me lifts the viewer's lane by dimming others' steps to 22% and their gutter entries to 40% over 260ms; the route holds and strengthens. On the graph, filtering dims non-matching steps to 14% rather than removing them, so the map's shape stays put.

### Completion Feedback
Marking a step done sends a green sweep along its outgoing wires, one 2.5px ripple from the node, and a brief ring on each step it unlocks, over 900ms, with a medium haptic. A notice then says, in words, what can start now and offers Undo. On touch, in-progress steps complete by sliding a 44px green thumb along a 50px pill track; on pointer layouts by a button.

### Motion
Pages arrive with their parts rising in one after another, and cards give way on the press. A classroom's graph arrives along the flow of its plan, and a small light travels along arrows leaving work in progress. Both are skipped with reduced motion, above 200 steps, and (for the light) on a device short of frame budget.

Motion is spring-based and described in response and damping ratio. Springs keep current value and velocity, so anything moving can be grabbed and redirected without a jump. During a live gesture the camera follows the finger exactly; past a bound it rubber-bands; on release it aims at where the flick was going. Damping is critical by default, with slight overshoot (0.85) only on a sheet flick above 500px/s. When the system asks for reduced motion, the camera arrives without travelling and panels and sheets cross-fade or settle over 160ms instead of springing.

**The Kept Apart Rule.** Destructive actions are isolated by empty space: Delete step sits 56px below the panel's last section, with nothing common near it.

## Do's and Don'ts

### Do:
- **Do** build chrome from the Cupertino set and the shared press button, on every platform, per the One Look Rule.
- **Do** honour Android Back and the system's appearance, text size, reduced motion and contrast settings on every new surface.
- **Do** draw status with the six step marks, and name any new map mark or line in the map key.
- **Do** rest steps as marks, and let cards arrive through zoom along the one continuous axis.
- **Do** make the most important action ink, and keep magenta for what belongs to the viewer.
- **Do** give every new colour both a light and a dark value, and check it on glass over each ambient glow.
- **Do** run content under floating bars, with scroll padding to clear them, rather than reserving a strip for them.
- **Do** make touch targets at least 44px, and hit areas larger than the drawn mark (28px reach on touch, 22px with a mouse).
- **Do** land feedback on the press, and use springs that can be interrupted.
- **Do** keep destructive actions apart by 56px of empty space and offer Undo in a notice.

### Don't:
- **Don't** use magenta for anyone else's work, for decoration, for links, or as a general primary colour.
- **Don't** carry a status by colour alone on any new surface.
- **Don't** make cards the resting form of a step, or let the graph settle into a board of rounded cards and connectors.
- **Don't** use Material widgets, ship a per-OS restyle, or let the Apple-style look override Android Back or a system setting.
- **Don't** add points, streaks, levels, confetti or other rewards; completion feedback stays the one sweep and ripple on the map.
- **Don't** give the progress ring a second ink or a place outside phase cards.
- **Don't** use real blur on anything drawn per step; canvas glass is faked for speed.
- **Don't** stack one translucent pane on another for reading, or let the globe behind everything move faster than one slow turn.
- **Don't** add a blurred surface without its solid high-contrast form.
- **Don't** add a second typeface, or change Inter's weight without setting its weight axis.
- **Don't** let a wire run across words.
- **Don't** place a common action beside a destructive one.
