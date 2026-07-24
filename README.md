# WE

A private intelligence layer that helps two people care for their relationship without turning
the relationship into work.

This is the first vertical slice: it proves the emotional mechanism —
**"What needs us?" → gentle insight → consent gate → mutual reveal** — before any calendars,
integrations, or AI.

## The mental model

WE is **one continuity, addressed to both partners** — not two accounts with a shared folder.
There are no ownership "rooms." A single shared home organizes the intelligence around three
**lenses** — facets of one life, never boundaries:

> **Today** — what needs the two of you now · **Life** — the life you're building and running ·
> **Us** — time, closeness, attention.

Privacy is a **property, not a place**: a private reflection or an unopened reveal lives *inline*
in the shared stream, gently marked and visible only to its owner, protected by the consent
machine below — never behind a separate tab.

- A reveal request exposes the **topic and the sender** — nothing more.
- Accepting means *"I'm ready to engage,"* not *"I consent to learn this exists."*
- Each person answers **privately**; answers appear only after **both** submit, revealed together.
- A decline is private: the initiator sees quiet waiting either way. "Not ready" is safe.
- A withdrawal leaves **no trace** on the partner's side.
- Disagreement is a first-class state: *"You're not in the same place yet. Nothing has been
  decided."*

The consent state machine lives in `lib/consent.ts` with three independent axes
(`visibility`, `readiness`, `response`) and is covered by tests in `lib/consent.test.ts`.

## Running it

```bash
npm install
npm run dev    # http://localhost:3000
npm test       # consent state machine + privacy invariants
```

The dashed **Demo controls** panel below the phone frame is the research harness, not the
product: switch between Ry and Dylan, advance the demo clock 18 hours to feel the later
waiting treatment, and reset the scenario.

Launch runs a brief **splash** (two circles settling into one), then a four-beat **onboarding**
(arrival → one shared place → the promise → who you are) on first run.

## What this slice deliberately excludes

Calendars, tasks, finances, and real AI. Accounts and a shared backend are the **next** build:
magic-link sign-in with a Supabase-backed couple, so two real phones share one continuity. State
today is local (Zustand + localStorage) behind a service-shaped layer so that backend can replace
it without touching the screens.
