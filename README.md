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

## Two real people, one shared space

WE runs on a Supabase backend. Each partner makes their own email + password sign-in, then one
**creates a shared space** (getting a 6-character join code) and the other **joins with the
code** — two real devices, one continuity. Realtime keeps both sides in sync as the consent loop
moves.

The consent invariants are enforced in the **database**, not just the UI (see
`supabase/migrations/0001_we_init.sql`): row-level security makes a partner's private reflection
and un-revealed answer unreadable even with a raw API key, and every state transition runs
through a `SECURITY DEFINER` function that mirrors `lib/consent.ts`.

## Running it

```bash
npm install
cp .env.example .env.local   # fill in your Supabase URL + publishable key
npm run dev                  # http://localhost:3000
npm test                     # consent state machine + privacy invariants
```

Launch runs a brief **splash** (two circles settling into one), then a three-beat **intro**
(arrival → one shared place → the promise) on first run, then sign-in and pairing.

**Preview without a backend:** add `?demo=1` to any URL (e.g. `localhost:3000/?demo=1`) to explore
the whole app on sample data — no Supabase, no login. Use Profile → "Experience as" to flip
between the two partners and feel both sides of a reveal.

**PWA:** WE ships a manifest, icons, and a service worker, so it installs to the home screen and
runs full-bleed (mobile bottom-nav, desktop sidebar — a true responsive layout, not a phone
frame).

> Note: the app talks to Supabase directly from the browser, so it must run somewhere that can
> reach `*.supabase.co` (your machine, or a deployment). For the prototype, turn **off**
> "Confirm email" in Supabase → Authentication → Providers → Email so password sign-up is instant.

## What this slice deliberately excludes

Calendars, tasks, finances, and real AI — those remain future. The intelligence is still seeded
and rule-based (four insights per couple), organized under the Today / Life / Us lenses.
