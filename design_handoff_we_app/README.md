# Handoff: WE — a shared operating layer for two people

## Overview

WE is a mobile app for a couple. It is not a chat app, a shared calendar, or a chore-splitter. It is an
intelligence layer that learns two people from the things they tell it, and then does three jobs:

1. **Life** — runs the practical week (tasks, food, money, care, calendar).
2. **WE / Today** — the permanent home. Holds *nothing* of its own. Each time you open it, the
   intelligence has selected the single most useful thing from Life or Us, or it tells you nothing
   needs you.
3. **Us** — the long-term reason any of it matters: what the couple is heading toward, and the plain
   evidence that ordinary weeks are getting them there.

The routing rule that governs all content placement:

| If the thing is… | It lives in… |
| --- | --- |
| an obligation, upkeep, or coordination | **Life** |
| relevant right now | surfaced by **WE** (never stored there) |
| an intention, aspiration, or progress | **Us** |
| an appetite — a film, a restaurant, a place, a craving | **Ours** (a shared library inside Us) |

**The moat is the intelligence, and the product's job is to make the intelligence visible.** Almost every
surface carries a short "why this, now" explanation in the app's own voice. When it guesses wrong, the
user corrects it in one tap, and the app later reports what that correction changed about *its own*
behaviour.

### Hard product constraints — do not violate these

- **No bottom tab bar.** Navigation is horizontal swipe plus a persistent WE mark.
- **No scorekeeping of any kind.** No streaks, points, relationship scores, completion percentages,
  leaderboards, or any metric that compares the two partners' contributions. An earlier iteration had a
  "who's carrying more" balance bar and it was cut deliberately: friction between partners is the
  antithesis of this product. Per-person colour identifies *ownership*, never *volume*.
- **No chat thread with the AI, and no feed.** The intelligence speaks in short declarative statements
  attached to real objects.
- **One notification per day, maximum.** See "One moment a day" below.
- **The app never invents plans.** Suggestions are assembled only from things the users actually said.

---

## About the design files

The file bundled here — `WE - Visual Directions.dc.html` — is a **design reference created in HTML**. It
is a prototype demonstrating intended look and behaviour. **It is not production code to copy.**

The task is to **recreate these designs in the target codebase's existing environment** (React Native,
Swift/SwiftUI, Flutter, etc.) using that codebase's established patterns, component library, navigation,
and state management. If no codebase exists yet, choose the most appropriate framework for a
production iOS app and implement the designs there.

Notably, the HTML prototype fakes several things that must be real in the app:

- Horizontal zone navigation is a CSS scroll-snap container. In the real app this should be a proper
  pager/`PagerView`/`TabView(.page)`-style component with gesture-driven transitions.
- The "tell WE anything" field cycles through four canned phrases via buttons. In the real app it is a
  live text input whose contents are classified by the model.
- All content is hardcoded for one fictional couple (see "Sample data" below).

### How the prototype is organised

The HTML file is a **design canvas** containing six numbered rounds of exploration, newest at the top.
Each round is a `<section class="dv-turn">`; each option inside has a stable id badge (`1a`, `2c`, `4c`…).
Only some of these are the accepted design. **Build from the accepted set only:**

| Accepted | id | What it defines |
| --- | --- | --- |
| ✅ | **3a** | The visual system: colour, type, spacing, the Life page, the blend rules |
| ✅ | **4c** | Reminders — immersive takeover overlay |
| ✅ | **5a** | The centre capture field and its routing receipt |
| ✅ | **5b** | Ours — the shared lists, and the idea it produces |
| ✅ | **5c** | Us — the simplified version. **This supersedes the Us page in 1a–4d.** |
| ✅ | **6a–6f** | The six behavioural features |
| ❌ | 1a–1d, 2a–2d, 4a, 4b, 4d | Rejected explorations. Reference only. |

Note that **2a** is 3a's direct ancestor and is visually near-identical; where they differ, **3a wins**.
Also note that 1a–4d contain an analytical Us page with a path diagram and a legend — that direction was
rejected for being too analytical. **5c is the Us page.**

---

## Fidelity

**High-fidelity.** Colours, typography, spacing, and copy are final and should be reproduced precisely.
Every hex value, font size, weight, letter-spacing, and string in this document is the intended value.

Two exceptions where lower fidelity is expected:

- **Transition choreography** was not designed in detail. Durations and easings given below are a
  starting point; use platform-native feel.
- **Iconography.** The design deliberately uses almost no icons — coloured dots, hairlines, and
  typography carry the meaning. Do not add an icon set. The only glyph-like elements are the status bar
  indicators (which are the OS's) and two text characters: `✕` and `→`.

---

## Design tokens

### Colour

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#16211D` | The app background. A flat, matte, desaturated deep green. Never a gradient fill. |
| `bg-elevated` | `#1B2723` | Sheets and overlays that sit above the page (Reminders drop-down/sheet). |
| `bg-deep` | `#101A17` | The Reminders full-screen takeover, i.e. *below* the page in perceived depth. |
| `ink` | `#E8E4D9` | Primary text. A warm off-white. Also used as the inverted button fill. |
| `ryan` | `#D98E5A` | Person A. Warm clay. |
| `dylan` | `#79A6B8` | Person B. Cool slate. |

Text and hairlines are `ink` at alpha. The scale in use, in order of prominence:

```
1.00  headlines, primary list items
0.82  secondary headings
0.75  list items in a de-emphasised group
0.72  legend / definition text
0.68  supporting prose in a card
0.62  reasoning ("why") text
0.55  section subtitles
0.52  category summaries
0.50  quiet metadata prose
0.45  de-emphasised list items
0.40  mono section labels
0.38  mono labels, one step quieter
0.35  right-aligned dates and counts
0.32  header-right metadata
0.30  home indicator, most recessive labels
```

Hairlines and borders:

```
rgba(232,228,217,0.16)   primary rule (section dividers, top/bottom of the synthesis block)
rgba(232,228,217,0.14)   rule inside Us sections
rgba(232,228,217,0.13)   list-row divider
rgba(232,228,217,0.11)   list-row divider inside a tinted cluster card
rgba(232,228,217,0.09)   divider inside the "what I'm watching" list
rgba(232,228,217,0.20)   dashed border (standing-rule card)
rgba(232,228,217,0.25)   secondary button border
rgba(232,228,217,0.50)   the WE mark's ring
```

Person-tinted surfaces (used for Reminders clusters and accent cards):

```
Ryan cluster      background rgba(217,142,90,0.10)   left border 2px solid #D98E5A
Dylan cluster     background rgba(121,166,184,0.09)  left border 2px solid #79A6B8
Neutral cluster   background rgba(232,228,217,0.04)  left border 2px solid rgba(232,228,217,0.22)
Plain card        background rgba(232,228,217,0.05)
Chip (Ryan)       background rgba(217,142,90,0.12)
Chip (Dylan)      background rgba(121,166,184,0.12)
Chip (shared)     background linear-gradient(90deg, rgba(217,142,90,.12), rgba(121,166,184,.12))
```

#### The blend — this is the most important rule in the system

The two person colours combine into `linear-gradient(90deg, #D98E5A, #79A6B8)` (or `135deg` /
`120deg` for larger square elements). **The gradient means "this belongs to both of you."** It must
appear *only* where something is genuinely shared. Its scarcity is what gives it meaning.

Where the blend is correct:

- The breathing intelligence mark (the app's avatar for itself).
- A dot on a list item both partners own — "decide dinner," "gift for Marissa & Tom."
- A dot on an item both partners independently added to Ours (e.g. *Past Lives*).
- The shared/joint line in any Us visual.
- The nav indicator segment.
- One hairline under the Today header, purely as a signal that the space is jointly held.

Where the blend is **wrong** — all of these were explicitly rejected:

- As a full-page background gradient. It turns the blend into decoration, after which a shared grocery
  run looks identical to a trip to Japan.
- As a tint wash over the whole screen.
- To indicate any quantity, balance, or comparison between the partners.

A single ambient accent *is* permitted: `radial-gradient(120% 80% at 88% 6%, rgba(121,166,184,.13),
transparent 60%)` layered over `bg`, drifting warm in the morning and cool at night. It tracks the
**hour**, never a person.

Solid dots identify a single owner: `#D98E5A` for Ryan's, `#79A6B8` for Dylan's. Dot sizes: `7px` in
lists, `8px` in prominent lists, `9px` in the takeover, `5px` in chips, `6px` in inline pairs. Always
`border-radius: 50%`, `flex: none`, and nudged down `~6-8px` with `margin-top` to sit on the text
baseline.

Onboarding lets each partner choose from four palettes. The defaults are the first of each:

```
Warm (Ryan)   Clay #D98E5A   Rust #C4633C   Amber #E0A94E   Rose #CF7A70
Cool (Dylan)  Slate #79A6B8  Teal #4E8A86   Indigo #6E7FB0  Sage #8AA98B
```

Every person-coloured element in the app derives from these two choices. Implement them as themeable
values, not literals.

### Typography

Two families only.

**Newsreader** (Google Fonts) — all content. Weights 300, 400, plus italic 400.

| Role | Spec |
| --- | --- |
| Hero statement (Today) | `300 42px/1.12`, `letter-spacing: -0.01em` |
| Page headline | `300 30-34px/1.14-1.18` |
| Us horizon (largest type in the app) | `300 44px/1.06` |
| Life category word | `300 38px/1` |
| Synthesis sentence | `300 25px/1.28` |
| Section title in a card | `400 18-21px/1.2-1.35` |
| List item | `400 15-16px/1.35` |
| Prominent list item (takeover) | `400 21px/1.25` |
| Body / supporting | `400 13.5-15px/1.6` |
| Reasoning ("why") text | `italic 400 12.5-13.5px/1.6-1.65` |
| Anchor quotes | `italic 400 19px/1.55` |
| Metric figure | `400 21-22px/1` |

**IBM Plex Mono** (Google Fonts) — labels, dates, counts, buttons. Weights 400, 500. **Always
uppercase, always letter-spaced.**

| Role | Spec |
| --- | --- |
| Zone label (LIFE / TODAY / US) | `400 10px`, `letter-spacing: 0.22em` |
| Section label | `400 9.5px`, `letter-spacing: 0.18em` |
| Sub-label inside a card | `400 9px`, `letter-spacing: 0.16em` |
| Right-aligned date / count | `400 9.5-10px`, `letter-spacing: 0.08-0.14em` |
| Button label | `400 10.5-11.5px`, `letter-spacing: 0.06-0.08em` |
| Nav LIFE / US | `400 10px`, `letter-spacing: 0.22em` |
| Status bar clock | `500 13.5px` |

Set `text-wrap: pretty` (or the platform equivalent) on every multi-line headline and paragraph.

### Spacing, radius, shadow

```
Screen padding          62px top · 30px sides · 112px bottom   (the bottom clears the nav bar)
Between major sections  26-34px, or 18-20px plus a top rule
Between cards           11-14px
Card padding            15-18px
List row padding        8-15px vertical, divider on top of each row
Radius — cards          3px   (near-square; this is a deliberate, precise look)
Radius — sheets         20-26px top corners only
Radius — pills/chips    999px
Radius — takeover       0 (full bleed)
Shadow — sheet          0 -20px 46px rgba(0,0,0,.42)
Shadow — drop-down      0 22px 50px rgba(0,0,0,.45)
```

Device reference: **393 × 852pt** (iPhone 15/16 logical size). Status bar 54pt, home indicator 5 × 134pt
at 9pt from the bottom.

---

## Navigation

Three zones on one horizontal axis, fixed order:

```
LIFE   ←   WE / Today   →   US
```

- **WE is index 1 and is the home.** Cold launch always lands on Today.
- Horizontal swipe moves one zone at a time, with paging (never free-scrolling).
- Each zone scrolls vertically and independently. Vertical position within a zone should persist while
  the app is alive.
- The **persistent WE mark** sits bottom-centre, above the home indicator, on every zone. Tapping it
  always returns to Today. This is a hard requirement.
- Flanking it, the words `LIFE` and `US` are tappable and jump directly to those zones. The label for
  the zone you are currently on renders at full `ink`; the other two at `0.38` alpha.
- Below the WE mark: a `48 × 1px` track at `rgba(232,228,217,.16)` containing a `16px` segment filled
  with the blend gradient, translated `0 / 16 / 32px` for zone 0 / 1 / 2. Transition
  `transform .34s cubic-bezier(.4,0,.2,1)`.
- The WE mark itself: `40 × 40pt` circle, `1px` border `rgba(232,228,217,.5)`, fill
  `rgba(232,228,217,.06)`, containing the text `WE` in `400 11px` IBM Plex Mono, `letter-spacing .14em`.
- The nav bar sits on `linear-gradient(to top, rgba(22,33,29,.96) 55%, transparent)` so content scrolls
  softly beneath it. Bar padding `16px 30px 30px`; the bar occupies roughly 103pt.

The Reminders takeover is the **only** surface permitted to cover the WE mark, and only while open.

---

## Screens

### 1. Life — "run life"

**Purpose:** everything that keeps the week moving. Never the first thing you see.

**Layout,** top to bottom:

1. Zone label `LIFE`.
2. **The synthesis block** — bordered top and bottom with `rgba(232,228,217,.16)`, `18px 0 20px`:
   - A `14 × 14pt` circle filled with `linear-gradient(135deg,#D98E5A,#79A6B8)`, animating
     `opacity .34 → .70 → .34` over 7s, `ease-in-out`, infinite. This is the intelligence's avatar and it
     appears anywhere the app speaks in its own voice.
   - Beside it, the mono label `THE SHAPE OF THIS WEEK`.
   - The synthesis sentence, `300 25px/1.28`: *"Front-loaded. Three things land before Sunday, then it
     opens right up."*
   - A three-column metric row, columns divided by `1px` left borders with `14px` left padding:
     `3 / BEFORE SUN` · `$540 / COMMITTED` · `Friday / THE ONE TO SETTLE`.
   - The reasoning line, italic, indented `12px` behind a `1px solid rgba(217,142,90,.45)` left border:
     *"Because Friday, Sunday and the 22nd all sit in one nine-day stretch. After that it stays clear
     until September."*
3. **The five categories**, stacked with `26px` gaps. Each is a category word in `300 38px/1` Newsreader,
   an optional count in `400 10px` mono beside it (`#D98E5A` when something is time-pressured,
   `rgba(232,228,217,.35)` otherwise), and a one-line summary in `400 14px/1.5` at `0.52` alpha.
   Categories with nothing pressing render the word itself at `0.62` alpha and the summary at `0.40`.

   Fixed order and copy:

   | Category | Count | Summary |
   | --- | --- | --- |
   | Food | 2 (warm) | Delivery closes 9pm · Friday still open |
   | Care | 3 (warm) | Dylan's birthday Sun · Ryan's dad Fri · Miso |
   | Calendar | 4 | Wedding 22 · Hamptons 28–31 |
   | Money | 2 (dim) | Japan fund paid · gift undecided |
   | Home | 2 (dim) | Filter overdue · insurance Sep 1 |

   The intelligence orders these by attention needed, not alphabetically or by a fixed taxonomy.

**Note:** Life must stay this calm. An early version put the full Reminders list inline and it swamped
the page; that is why Reminders became an overlay.

---

### 2. Reminders — the immersive takeover (from 4c)

**Purpose:** the full picture of what's outstanding, grouped so it can be acted on.

**Entry:** pull down anywhere on Life. A small affordance sits in the Life header:
`↓ PULL FOR REMINDERS`, `400 9px` mono, `letter-spacing .14em`, `rgba(232,228,217,.30)`.

**The organising idea — this is the feature, not the list.** Reminders are grouped by **occasion**, not
by category and not by date, and **every cluster states why it exists.** Categories are a filing system;
occasions are how people actually think.

**Layout:** full-bleed over the page, background `#101A17`, padding `62px 26px 30px`.

1. Header row: `REMINDERS` label left, `DONE ✕` button right.
2. A three-segment progress bar, `2px` tall, `5px` gaps. The active segment is the blend gradient;
   inactive are `rgba(232,228,217,.14)`.
3. **One cluster fills the screen.** Vertically centred:
   - `CLUSTER 1 OF 3 · FRIDAY` in `400 9.5px` mono, `#D98E5A`.
   - Title `300 40px/1.1`: **Before your dad lands**.
   - The grouping rationale, italic `400 14.5px/1.6` at `0.55`: *"These four only matter because of
     Friday. Clear them together and Friday takes care of itself."*
   - The items — `15px` vertical padding, `1px` divider above each and below the last, a `9pt` owner dot,
     the item in `400 21px/1.25`, and an optional detail line in `400 11.5px/1.5` at `0.42` (or `#D98E5A`
     when time-critical).
4. Footer above the home indicator, divided by a rule: `NEXT CLUSTER / Wedding week →` on the left,
   `SWIPE TO ADVANCE` right-aligned in mono at `0.30`.

**Swipe horizontally to advance clusters.** Exit via `DONE ✕` or a downward swipe. While open, the
nav bar is hidden — that is the point of this treatment. On close, the nav bar returns.

**The three clusters:**

**Before your dad lands** — Ryan-tinted, `FRI`
*"These four only matter because of Friday."*
| Item | Owner | Detail |
| --- | --- | --- |
| Decide dinner | shared | out, or at Dylan's — both of you |
| Send the grocery list | Dylan | window closes 9pm tonight (warm) |
| Clear the guest room | Ryan | — |
| Air filter | Ryan | two months over — he notices |

**Wedding week** — Dylan-tinted, `17–22`
*"Dylan's birthday and Marissa's wedding are five days apart. Same clothes, same drive, one gift budget
— one cluster."*
| Item | Owner | Detail |
| --- | --- | --- |
| Dylan's birthday — Sunday | Ryan | 4 days |
| Gift for Marissa & Tom | shared | $200? |
| Rhinebeck — drive or train | shared | — |
| Suit to the cleaner | Dylan | by 20 |

**Quiet upkeep** — neutral, `NO DATE`
*"Nothing here is urgent. I'll surface each one when its moment comes."*
Renter's insurance · Sep 1 — Miso's teeth · September — Ryan's passport · before Nov

---

### 3. WE / Today

**Purpose:** the intelligent clearing. **Nothing is ever stored here.** Every item is drawn from Life or
Us at the moment of viewing.

Three states, all designed:

**(a) Nothing needs you** — the state to be proud of, and the most common one once the app is working.

```
                    ◯ ← 70pt ring, rgba(232,228,217,.16), 1px
                      inner 28pt disc, blend gradient, breathing 7s

            Nothing needs you here.          300 42px/1.12, centred
     Friday's booked. The groceries          400 15px/1.6, 0.55 alpha,
      went out. Dylan's cake is ordered.     max-width 270pt

  ─────────────────────────────────────
  WHAT I'M WATCHING
  — Marissa's wedding is in 9 days with no gift chosen. I'll ask
    Saturday, when you're both free.
  — Japan flights open in November. I need a season by October.
  — The Sunday call has slipped three weeks. Not raising it while
    your dad's here.
  ─────────────────────────────────────
  NEXT ON THE HORIZON            4 mo
  Japan · spring 2027            TO TICKETS
```

The three watching items are left-aligned within a full-width block, each with an owner dot and
`400 14px/1.6` text; the third is dimmed to `0.45` because it is deferred. `4 mo` renders in `#79A6B8`.
This screen must feel like a resolution, not an empty state.

**(b) Something needs you** — one thing, full screen. Label the source (`FROM LIFE`, `FROM LIFE · CARE`,
`TOWARD JAPAN, 2027`), the statement as the headline, the reasoning behind an accent border, then two or
three actions — one filled (`#E8E4D9` on `#16211D`), one outlined, one text-only escape ("Not yet,"
"ask me again tonight").

**(c) A question toward Us** — same shape, but the two choices are equal-weight buttons tinted with the
two person colours (`Spring` in Ryan-warm, `Fall` in Dylan-cool). The reasoning is always present:
*"Asking today because spring fares open in November, Ryan's passport expires that March, and you've
both said 'sometime in 2027' four times."*

Close every Today screen with the honest remainder: *"Three other things are waiting. None of them are
urgent."*

---

### 4. The capture field — "Tell WE anything" (from 5a)

**Purpose:** the single input in the app. The user never has to know where anything goes.

Sits at the bottom of Today, under a rule.

1. Mono label `TELL WE ANYTHING`.
2. The field: `15px 16px` padding, `rgba(232,228,217,.06)` fill, `1px solid rgba(232,228,217,.16)`,
   `3px` radius. Inside: an `8pt` blend dot, the text in `400 17px/1.3` Newsreader, and a `1.5 × 19pt`
   caret in `ink` that pulses at 1.4s.
3. **The receipt** appears below once classified — `rgba(232,228,217,.05)` fill with a `2px` left border
   in the destination's colour:
   - `FILED TO` label left; the destination right, in that colour: `LIFE · CARE`, `OURS · TASTES`,
     `OURS · WATCHLIST`, `US · HORIZONS`.
   - The reasoning, italic `400 13.5px/1.65` at `0.62`.
   - Two buttons: `WRONG PLACE` (outlined) and `FINE ✓` (text-only).
4. Below, `CAUGHT THIS WEEK · 14` and a wrapping row of pill chips, each tinted by who said it, with a
   `5pt` dot. Shared chips use the two-stop gradient tint.

**The four canonical classifications** — use these as the model's few-shot examples:

| Input | Destination | Reasoning shown |
| --- | --- | --- |
| `reminder to call mom sunday` | LIFE · CARE | "A task with a day attached, so it went to Life. I tied it to the Sunday call — the rhythm that has been slipping three weeks." |
| `steak` | OURS · TASTES | "Not a task and not a goal. It went to what you are both hungry for, and it will show up when you are deciding Friday." |
| `fast and furious` | OURS · WATCHLIST | "A film, so it joined the list you share. Nine unwatched now — enough for the Hamptons week." |
| `japan in the fall maybe` | US · HORIZONS | "This is about where you are going, not this week. I filed it against the Japan horizon as a leaning, not a decision." |

The reasoning must reference *this couple's actual state*, not generic category logic. That specificity
is the entire product.

`WRONG PLACE` must be one tap to a corrected destination, and every correction becomes training signal
that surfaces later in the correction receipt (6a).

---

### 5. Ours — the shared lists (from 5b)

**Purpose:** accumulate everything either partner mentions. **These are not to-dos — they are appetite.**
No dates, no completion, no pressure. This is the raw material the intelligence uses when it needs an
idea.

Lives inside Us; written to by the capture field; read by WE.

1. Header: `OURS` · `61 THINGS`. Headline *"Everything you've both mentioned."* Subtitle: *"No dates, no
   pressure. This is the raw material WE uses when it needs an idea."*
2. Filter pills: `WATCHLIST 22` (active — `#E8E4D9` fill, `#16211D` text) · `EATING 19` · `PLACES 14` ·
   `SOMEDAY 6` (inactive — outlined, `0.6` alpha).
3. The list. Each row: `13px` vertical padding, `1px` top divider, a `7pt` owner dot, the title in
   `400 18px/1.25`, and provenance in `400 9.5px` mono at `0.35`.

   | Item | Dot | Provenance |
   | --- | --- | --- |
   | Fast and Furious | Dylan | DYLAN · 2 MIN AGO |
   | The Bear, s4 | Ryan | RYAN · MONDAY |
   | Past Lives | **shared** | BOTH ADDED IT, A WEEK APART |
   | Tokyo Story | Dylan | TAGGED TO JAPAN 2027 (in `#79A6B8`) |
   | Anything but a musical | Ryan | RYAN · A STANDING NOTE |

   *Past Lives* demonstrates the highest-value inference in the app: both partners added it
   independently and neither knew. Surface these prominently. "Anything but a musical" shows that a
   standing negative preference is a first-class entry.

4. **The payoff card** — Ryan-tinted with a `2px #D98E5A` left border:

   > **WE MADE YOU A FRIDAY**
   > Steak at Hometown, then *Past Lives* at Dylan's.
   > *You both wrote "steak" this month. Hometown is nine minutes from Dylan's and has a 7:45.
   > Past Lives is the one film you each added without knowing. Your dad flies out at noon.*
   > `HOLD IT` (filled) · `SOMETHING ELSE` (outlined)

   Every clause of that reasoning cites a different signal: the lists, geography, the coincidence, and
   the calendar. That is the demo.

5. `ALSO POSSIBLE`, in `400 14.5px/1.85` at `0.55` — including *"Nothing at all. That's allowed."*

---

### 6. Us (from 5c) — **this replaces the earlier analytical version**

**Purpose:** the long-term goals, and how everyday life is getting there. Us was originally built as a
path diagram with a legend and it was rejected for being too analytical. **No diagram. No legend. No
metrics.** One horizon and plain evidence.

Background carries a top-centred glow: `radial-gradient(130% 55% at 50% 12%, rgba(217,142,90,.15),
transparent 66%)` over `bg`. Padding `62px 32px 112px`.

1. Zone label `US`.
2. **The horizon,** centred, `44px` from the top of the content:
   - `WHERE YOU'RE HEADED` in mono at `0.40`.
   - `Japan,` / `spring 2027` — `300 44px/1.06`. The largest type in the app.
   - *"Everything in Life is quietly paying for this."* — `400 15px/1.6` at `0.55`. This sentence is the
     thesis of the whole product; keep it.
   - A `56 × 2pt` blend-gradient rule, centred, `22px` below.
3. **`WHAT THIS WEEK DID FOR IT`** — three rows, `15px` gaps, each an `8pt` owner dot and
   `400 19px/1.35` text:
   - $340 went in, without either of you moving it — *shared*
   - Ryan's passport renewal started — *Ryan*
   - You cooked in on Thursday for the 41st week — *shared*

   Then, behind a warm left border, italic: *"Three ordinary things. That's what a horizon is made of."*

   This section is the mechanism that connects Life to Us. It must be plain sentences about real events
   — never a progress bar, percentage, or chart.
4. **`ONE THING TO SAY`** — `Spring or fall?` in `300 25px/1.28`, then *"It's the only thing standing
   between a wish and a date,"* then the two tinted buttons. Us asks at most one question at a time.
5. **`AFTER THAT`** — the remaining horizons as plain rows, deliberately de-emphasised so the primary
   horizon stays primary:
   - One address — `JUNE 2026` — `0.82` alpha
   - Ryan, shooting film again — Ryan dot — `0.62`
   - Dylan, certified — Dylan dot — `0.62`
   - A place upstate — `NO DATE` — `0.45`

   Individual horizons sit in the same list as shared ones, marked only by dot colour. Each partner's
   own ambitions are visible without being separated out.
6. **`YOU'RE IN`** — centred: *Two apartments, one calendar* in `italic 400 21px/1.4`, then
   `SINCE MARCH`. The season is the couple's own name for their current chapter.

The Us vocabulary — keep these words, they are the product's language: **Horizons** (what you're aiming
at) · **Rhythms** (what you repeat to get there) · **Anchors** (what you've already agreed on, so you
don't relitigate it) · **Threads** (conversations still open, with no pressure to finish) · **Seasons**
(the chapter you're in) · **Evidence** (proof it's working). 5c surfaces Horizons, Evidence and Season
prominently and lets the others live one level down.

---

## The six behavioural features

These are the retention argument. Each is WE explaining itself or getting out of the way.

### 6a. The correction receipt

A periodic screen, `WHAT I'VE LEARNED` · `MONTH 5`, headed *"Nine corrections changed how I work."*
Subtitle: *"Every time you moved something, I kept the reason. Here's what's different now."*

Four cards, each `rgba(232,228,217,.05)` with a `2px` left border. Structure: the observed behaviour as a
mono label, the app's changed behaviour in `400 18px/1.35`, and the outcome in italic at `0.48`.

| Observation | What changed | Outcome |
| --- | --- | --- |
| YOU MOVED 3 ERRANDS OUT OF THE MORNING | I stopped putting errands in front of you before 6pm. | Since July 2. Nothing has been moved since. |
| YOU DELETED "PLAN SOMETHING FUN" TWICE | I don't invent plans anymore. I only suggest from what you've actually said. | That's why Friday came out of Ours, not out of thin air. |
| YOU ANSWER ME IN THE MORNING, NOT AT NIGHT | I ask once, at 8:12. | Your reply rate went from 40% to 91%. |
| YOU TOLD ME "NOT A TASK" FOUR TIMES | Food you mention now goes to Ours, not to Life. | "Steak" is an appetite. "Groceries" is a task. I can tell them apart now. |

Close with *"Still getting something wrong? Tell me once and it stops."* and a `SOMETHING'S STILL OFF`
button.

**Critical tonal rule:** every statistic on this screen is about the *app's* behaviour. The app critiques
itself and never the users. "Your reply rate went from 40% to 91%" is framed as evidence that the app
learned the right hour — not as a compliance metric.

### 6b. Presence

The app knows when a partner is away (calendar, location, travel) and reroutes without being asked.

Header banner, Ryan-tinted, with the absent partner's dot at `0.45` opacity: *"Ryan's in the Hamptons
until Sunday."* / *"Shooting, so I'm not sending him anything that can wait four days."*

The day's item is addressed to one person — `FOR DYLAN, ALONE` in `#79A6B8` — with reasoning:
*"You've handled Miso's appointments since March, and this one has a Friday deadline. I'd normally ask
you both."* Actions: `BOOK IT` and `ASK RYAN ANYWAY` — the override is always offered.

`HOLDING UNTIL SUNDAY` lists what was deferred and why (September's Japan payment: *"It's a both-of-you
thing. It can wait four days."*). Closing card: *"Sunday evening, I'll bring him the three things that
waited — in one go, not four notifications."*

Presence is about **reachability**, never availability or effort. Never compare who is more present.

### 6c. One moment a day

A lock-screen design. Background `linear-gradient(170deg,#1E2A24,#16211D 42%,#101A16)` with a slow
280pt radial glow breathing at 11s.

Date in mono, time in `300 80px/1` Newsreader. One notification: `22pt` rounded-`7px` blend-gradient
app tile, `WE`, `now`, the statement in `400 20px/1.35`, and the detail in `400 13px/1.6`. Container is
`rgba(232,228,217,.10)` with a `22px` radius — a translucent iOS notification.

Below: *"That's the only thing I'll send today. Eight others are being watched."*

Pinned at the bottom, a `WHY 8:12` card: *"It's when you both actually reply. I tried evenings for three
weeks and you didn't."* with `EARLIER` / `LATER` / `NOT TODAY` pills.

**One push per day, at a learned hour. No badge counts, no red dots, no second attempt.** The app should
hold a queue and send only the single highest-value item.

### 6d. Deferral, said out loud

`HELD BACK` · `3`, headed *"Things I'm not bringing up yet."* Subtitle: *"Timing is most of tact. You can
override any of these — I'd rather be early than sneaky."*

Each held topic: title, a timing chip, the reasoning in italic, and `RAISE IT NOW` / `LEAVE IT`.

- **The Sunday call** — `3 WEEKS` — *"It's slipped, and it matters. But your dad is here until Sunday and
  this is about your mother. I'll raise it Monday."*
- **The wedding gift number** — `SATURDAY` — *"Money conversations go better when you're in the same
  room. You will be Saturday morning."*
- **One address** — `SPRING` — *"Your leases end in June 2026. Nothing useful happens by discussing it in
  August — I'll bring it back in March."*

Then a dashed-border card, `A STANDING RULE YOU GAVE ME`: *"Never money before coffee." Kept for eleven
weeks.* Standing rules are user-authored constraints on the intelligence's behaviour and should be a
real, editable data type.

### 6e. A season, closed

When a chapter ends, WE writes it up from what actually happened. Background
`linear-gradient(190deg,#1B2723,#16211D 55%,#131E1A)`.

`A SEASON ENDED` · `JUN 2026`. A `44 × 2pt` blend rule, then the season's name in `300 38px/1.1`, then
`MARCH 2025 — JUNE 2026 · 16 MONTHS`.

The narrative in `400 16.5px/1.75` at `0.80` — generated from real logged data:

> *You spent sixteen months learning to run one life out of two addresses. You cooked in on 63
> Thursdays. You saved $6,120 toward a country neither of you had seen. You met each other's parents,
> twice over, and stopped asking whose turn it was to host.*

Then `WHAT YOU DECIDED` (dated decisions pulled from resolved Threads), and — importantly — `THE ONE
THING THAT DIDN'T HAPPEN`: *"Ryan didn't shoot film again. It's still on the horizon, and it's still
his."* The honesty is what makes this land rather than read as a Spotify Wrapped.

Close with `WHAT COMES NEXT` — the next horizon, *"Name it when you're ready. I'll start keeping notes
either way"* — and `NAME THE SEASON` / `KEEP THIS`.

This is retention without a streak, and the one screen a couple would screenshot.

### 6f. Onboarding

`SETTING UP · 1 OF 3`. Headline *"Choose a colour each."* Subtitle: *"From here on, anything of Ryan's is
one colour, anything of Dylan's is the other, and anything you share is both."*

A `104pt` preview block filled with `linear-gradient(120deg, <warm>, <cool>)` containing the word
`Ours.`, with the pair's names beneath (e.g. `Clay and Slate`). Then two rows of four `58pt` swatches,
each row headed by that partner's name and current dot. **The preview updates live on tap.**

Then `THEN THREE QUESTIONS`:

1. Do you live together?
2. What's the one thing you're saving for?
3. Who or what else do you look after?

*"That's all I need. Connect a calendar and I'll work the rest out by watching."* Then `THAT'S US`.

Three questions and a calendar is the entire cold start. Resist adding fields — low barrier to entry is
an explicit product requirement, and the intelligence is supposed to earn its knowledge by observation.

---

## Interactions & behaviour

| Interaction | Behaviour |
| --- | --- |
| Zone swipe | Paged horizontal, one zone per gesture. Snap. |
| Zone tap (`LIFE` / `WE` / `US`) | Animate to that zone, ~300ms, cubic-bezier(.4,0,.2,1). |
| Nav indicator | `transform` translate, `.34s cubic-bezier(.4,0,.2,1)`. |
| Reminders open | Pull down on Life, or tap the affordance. Full-bleed, covers the nav. |
| Reminders cluster advance | Horizontal swipe within the takeover. Progress bar updates. |
| Reminders close | `DONE ✕` or swipe down. Nav bar returns. |
| Capture submit | Classify, then reveal the receipt beneath the field. |
| `WRONG PLACE` | One tap to a corrected destination; log the correction as training signal. |
| Intelligence mark | `opacity .34 → .70 → .34`, 7s, ease-in-out, infinite. Also 9s and 11s variants on larger ambient glows. |
| Caret in the capture field | Same breathing animation at 1.4s. |
| Corner ambient glow | Interpolates warm → cool across the day. Never person-linked. |

Buttons: filled = `#E8E4D9` background with `#16211D` text; outlined = transparent with a
`1px rgba(232,228,217,.25)` border and `0.72`-alpha text; text-only = no border, `0.40`-alpha text, used
for the escape action ("Not yet," "Leave it," "Fine ✓"). Every request the app makes offers a way to
decline it.

**Voice.** First person, plain, declarative, never cute, no emoji, no exclamation marks. The app says
"I" about itself and "you" about the couple. It states reasons unprompted. It admits deferral. It never
congratulates, gamifies, or compares the two partners. Sample register: *"Not raising it while your dad's
here."* / *"Nothing else needs you here."* / *"Nothing at all. That's allowed."*

---

## State management

Persisted domain state:

- `partners[2]` — name, chosen colour, presence/travel windows, standing preferences.
- `lifeItems` — category (home/food/money/care/calendar), owner (`a` | `b` | `shared`), due window,
  occasion cluster id, source (captured, inferred, imported).
- `clusters` — occasion-based groupings with a generated rationale string, ordered by urgency.
- `oursItems` — list kind (watchlist/eating/places/someday), added-by, added-at, cross-partner match
  flag, optional horizon tag.
- `horizons` — title, target window, owner (`a` | `b` | `shared`), linked Life items, linked Ours items.
- `rhythms` — cadence, streak-free health signal (`running` | `slipping`), linked horizon.
- `anchors`, `threads`, `seasons`, `evidence`.
- `heldTopics` — topic, reason, scheduled surface date, override state.
- `standingRules` — user-authored constraints, with an age.
- `corrections` — original classification, corrected destination, timestamp; and the derived
  `behaviourChanges` the receipt renders.
- `dailyMoment` — the learned send hour, the queue, and reply-rate history.

Ephemeral UI state: `activeZone` (0–2, default 1), per-zone scroll offset, `remindersOpen`,
`activeCluster`, `captureDraft`, `lastReceipt`.

Today is **derived, never stored.** Its selection function ranks candidates from Life and Us by
time-pressure, decision-unblocking value, and both partners' reachability, then returns at most one —
or the "nothing needs you" state. Everything it returns must carry a reason string.

---

## Sample data — one fictional couple

All copy in the prototype is built around this couple. Reuse it for seeding and demos; the specificity is
what makes the intelligence legible.

**Ryan, 33** — content creator at a real-estate brokerage. Warm colour.
**Dylan, 30** — brand marketing at a bank. Cool colour. Turns 31 on **Aug 17**.
They **do not live together.** Both leases end **June 2026**. A pet, Miso. "Today" is **Wed 13 Aug**.

- Aug 15 (Fri) — Ryan's dad arrives, lands 4:10pm
- Aug 17 (Sun) — Dylan's birthday
- Aug 22 (Fri) — Dylan's cousin Marissa's wedding, Rhinebeck
- Aug 28–31 — Ryan in the Hamptons for work
- Horizon — Japan, spring 2027 (season undecided); $340/month saved, $2,720 so far
- Rhythms — Thursday cook-in (41 weeks), the Japan payment, the Sunday call to Ryan's mom (slipping)
- Season — "Two apartments, one calendar," since March
- Anchors — "No surprises about money." / "We say the small thing early."
- Open thread — "A weekend wedding, or one night?"

---

## Assets

**None.** There are no images, icons, or illustrations in this design — by intent. Everything is type,
colour, hairlines, and dots.

Fonts, both from Google Fonts:

- **Newsreader** — 300, 400, italic 400
- **IBM Plex Mono** — 400, 500

Bundle both with the app rather than loading them at runtime.

The status bar and home indicator in the prototype are hand-drawn imitations of the OS chrome. Use the
real system chrome.

---

## Files

- `WE - Visual Directions.dc.html` — the full design canvas. Open it in a browser. Six rounds, newest at
  the top; each option carries an id badge. **Build from 3a, 4c, 5a, 5b, 5c, and 6a–6f.** The rounds
  above and below those contain rejected explorations, kept for context on what was tried and why it was
  dropped.

Interactive parts of the prototype worth clicking:

- Any accepted option — swipe the phone horizontally, or tap `LIFE` / `WE` / `US`.
- **4c** — `DONE ✕` closes the takeover; the pull affordance reopens it.
- **5a** — the four sample-phrase pills demonstrate classification and reasoning.
- **6f** — the colour swatches update the blend live.
