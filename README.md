# WE

A private intelligence layer that helps two people care for their relationship without turning
the relationship into work.

This is the first vertical slice: it proves the emotional mechanism —
**"What needs us?" → gentle insight → consent gate → mutual reveal** — before any calendars,
integrations, or AI.

## The mental model

> **Mine** is private. **Ours** is known. **Between Us** is mutually opened.

- A reveal request exposes the **topic and the sender** — nothing more.
- Accepting means *"I'm ready to engage,"* not *"I consent to learn this exists."*
- Each person answers **privately**; answers appear in Between Us only after **both** submit,
  revealed together.
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

## What this slice deliberately excludes

Calendars, tasks, finances, real AI, accounts/auth, push notifications, and a backend.
State is local (Zustand + localStorage) behind a service-shaped layer so a real backend can
replace it without touching the screens.
