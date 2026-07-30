# WE — accepted screens

Eleven screens, exactly as designed. Every value in these images is intentional — see `README.md` for
the hex codes, type specs, spacing, and copy behind each one.

All frames are **393 × 852pt** (iPhone 15/16 logical size), captured at 2×.

> **One capture artifact to ignore:** the bottom nav bar's scrim is a soft gradient
> (`linear-gradient(to top, rgba(22,33,29,.96) 55%, transparent)`) that the screenshot renderer draws
> more transparently than the live app. In a few frames you can faintly see content behind the
> `LIFE · WE · US` row. In the real app that scrim is nearly opaque at the bar and fades upward. Open
> `WE - Visual Directions.dc.html` in a browser to see it correctly.

---

## The three zones

### 01 · Life — `screens/01-life-3a.png` (option 3a)
The left zone. The AI synthesis block at the top reads the *shape of the week*, followed by the five
categories as single large words. This is the calm state Life must keep — Reminders lives in an overlay
precisely so this page stays this quiet.

### 03 · Today, with the capture field — `screens/03-today-capture-5a.png` (option 5a)
The centre, and the app's home. Shown in the "nothing needs you" state, which is the state to be proud
of. Beneath it, the single input in the whole app: **Tell WE anything**. The receipt below shows where the
text was filed and why, with one-tap correction. Bottom: the week's captures as chips, tinted by who said
them.

### 05 · Us — `screens/05-us-5c.png` (option 5c)
The right zone. One horizon at the largest type size in the app, then plain evidence that ordinary weeks
moved it forward, then one question, then the remaining horizons de-emphasised. **This supersedes the
diagram-based Us page in options 1a–4d** — that direction was rejected as too analytical.

---

## Reminders

### 02 · Immersive takeover — `screens/02-reminders-4c.png` (option 4c)
Pull down on Life. One cluster at a time, full screen, swipe to advance. Grouped by **occasion**, not by
category or date — and the cluster states its own rationale. This is the only surface allowed to cover
the WE mark.

---

## Ours

### 04 · The shared lists — `screens/04-ours-5b.png` (option 5b)
Everything either partner has mentioned. Not to-dos — appetite. Note *Past Lives* carrying the shared
gradient dot: both added it independently, a week apart, and neither knew. The card at the bottom turns
the list into a Friday, citing four separate signals in its reasoning.

---

## The six behavioural features

### 06 · The correction receipt — `screens/06-correction-receipt-6a.png` (6a)
What your corrections taught it. Every statistic here is about the **app's** behaviour, never the users'.

### 07 · Presence — `screens/07-presence-6b.png` (6b)
Ryan is away shooting, so WE asks Dylan alone, holds the both-of-you items until Sunday, and says it will
return them in one go rather than four notifications. Reachability — never availability or effort.

### 08 · One moment a day — `screens/08-daily-moment-6c.png` (6c)
The lock screen. One push, at a learned hour, with the reason given and Earlier / Later / Not today. No
badges, no red dots, no second attempt.

### 09 · Deferral, said out loud — `screens/09-deferral-6d.png` (6d)
Three topics WE is holding, each with its timing rationale, each overridable. Plus standing rules the
couple has given it.

### 10 · A season, closed — `screens/10-season-closed-6e.png` (6e)
A chapter written up from real logged data — including, deliberately, the one thing that didn't happen.
The honesty is what stops this reading as a year-in-review gimmick.

### 11 · Onboarding — `screens/11-onboarding-6f.png` (6f)
Colour first: each partner picks one, and the blend preview updates live. Then three questions and a
calendar. That is the entire cold start.

---

## Not pictured

- **Today's other two states** — "something needs you" (one item, full screen, with actions) and "a
  question toward Us" (two equal choices tinted per person). Both are specified in `README.md` under
  *Screens → WE / Today*; 05 shows the question pattern in its Us context.
- **The other two Reminders treatments** (4a drop-down, 4b slide-up sheet) — explored and not chosen.
  They are in the prototype if you want to see the alternatives.
- **Zone transitions** — swipe the phones in the prototype; the choreography wasn't storyboarded and
  should use platform-native feel.
