# ○ — the personal space

**Working code name: `circle`. In the product it is a mark, not a word.**

Status: five decisions locked, three resolved, key-service architecture is the one open
investigation. See §14.

---

## 1. Thesis

**Nothing becomes history by accident.**

Every private space ever shipped is a vault. Vaults accumulate, and accumulation is what makes
privacy fragile. This one inverts the default: an entry has a natural life, returns once to ask
whether it should continue, and disappears if the answer is silence.

Continued storage is therefore an act of consent, not a side effect of having once typed something.
Permanence still exists, but it is always chosen, never inherited.

The claim is precise and must stay precise. It is *not* "nothing exists to breach" — deliberately
held entries do exist. It is that nothing enters your history without you putting it there twice.

Three sentences carry the rest of this document:

> Returns wait until they can be shown.
> New words do not inherit permanence.
> One extra week means exactly one extra week.

---

## 2. The mark

The space is identified by a **single circle in the person's own hue**.

This is already half-built. `WEMark` composes two circles, personal hue and partner hue, with a
`joined` parameter governing separation. The personal space is that mark with the partner circle
absent. The visual grammar of the whole product becomes readable at a glance:

| Mark | Meaning |
| --- | --- |
| One circle, personal hue | yours |
| Two circles, apart | invited, not yet joined |
| Two circles, joined | WE |

Because separation is already an animatable parameter, "prepare an offer" has a native motion: the
solitary circle drifts toward the partner circle and stops short of joining. It does not join until
the offer crosses.

### One teaching moment, then silence

A solitary coloured circle reads as profile, presence, or account status to someone who has not been
told otherwise. **A symbol can become wordless after it is learned, not before.**

So the word **Yours** appears exactly twice in a person's lifetime with the product: once during the
Promise, and once on first entry to the space. After that it never appears in the interface again.
No title, no navigation label, no section header, no settings row.

This is a deliberate, bounded exception to the no-word rule, not a loophole to widen later.

### Spoken name

`Yours`, used in the VoiceOver label, in support material, and in App Store copy. A word will exist
whether or not we choose one — VoiceOver must announce the destination, support docs must refer to
it, and two people will say something out loud regardless — so it is chosen deliberately and
confined. `WEMark.accessibilityText` is the mechanism; the personal variant passes `"Yours"`.

Rejected: naming the VoiceOver label after the furniture ("your circle", "your space"). Sighted and
unsighted users would end up with different mental models of the same product.

### State grammar

One shape, five conditions. No badges, no counts, no numerals anywhere.

- **Living** — circle outline, personal hue
- **Nearing return** — the stroke lightens gradually across the final week; legible if you look,
  invisible if you do not. Never a countdown, never a date on the object.
- **Returned** — fully weighted, present, waiting
- **Held** — solid fill, same shape made permanent
- **Let go** — the circle contracts to nothing and the surface returns to empty

---

## 3. Lifecycle

### Intervals — fixed, not configurable

| Stage | Duration | On arrival |
| --- | --- | --- |
| First life | 6 weeks | becomes *ready*; returns when next presentable, then 7 days to answer |
| First renewal | 12 weeks | same |
| Second renewal | — | offered permanence |

Silence at any presented return means the entry goes. The 7-day window is a grace period, not a
deadline: no overdue state, no escalation, no second notice.

**No per-entry duration picker.** A duration control makes someone plan document retention at the
exact moment they are trying to put down a thought. Predictability is part of the trust mechanism.
If evidence later shows six weeks is wrong, the change is one account-level setting, never
per-entry scheduling.

**Keep indefinitely is available from the first save**, visually secondary. Someone who knows on day
one that a thing is permanent should not have to wait eighteen weeks to say so.

### What resets the clock

- **Reading does not reset.** Anxious rereading must not confer permanence. An entry visited eleven
  times is not more significant than one written once; it may be considerably less resolved. If
  reading reset the clock, the mechanism would preserve exactly the material it should let go of.
- **Editing restarts the current interval, not the lifecycle stage.** An entry in its first renewal
  that is edited gets a fresh 12 weeks, not a demotion to 6. Renewal count is preserved.
- Renewal count increments only on an explicit renewal decision. Never on edit, never on read.

### The second-return choice

Three options, no default, no pre-selection:

- Keep this only for me
- Prepare something I could offer
- Let it go

**Renewal is permission to ask, never permission to infer.** Keeping something twice does not make
it load-bearing. It can mean uncertainty, rumination, avoidance, or simply "I'm not ready." The
system may use the second renewal to *offer* the choice above and for nothing else.

Prohibited, permanently:

- Renewal count exposed to the partner, or to the owner as a number
- Renewal count feeding the shared intelligence layer, ranking, prioritisation, or any suggestion
- Any surface where two people's renewal behaviour could be compared
- Any inference that "this must matter to you" spoken back to the owner

Same rule as the cut balance bar, applied to a subtler quantity.

---

## 4. Held

### No cap

A cap turns deliberate permanence into a storage quota, and at the limit the product would be
pressuring someone to rank or delete private material. That breaks the emotional contract outright.

- No visible cap
- A high, invisible technical safety limit
- No "you have 47 held things", ever
- An owner-initiated **Review what I've held**, never a prompt, never a scheduled audit

Held may accumulate. That is acceptable, because its defining property is that every item in it
entered deliberately.

### Held is a state, not a destination

Permanence must be reversible or people will hesitate to use it. Two actions sit beside each other
on a held entry:

**Let this return**
> This will return in six weeks. If you do nothing then, it will be let go.

- Starts a fresh first-life interval
- Clears prior renewal history
- Does not itself count as a renewal

**Let go now** — immediate, separate, unambiguous.

### Editing a held entry

Held status must not silently transfer to newly written material. New words do not inherit
permanence.

On save after editing a held entry:

> You changed something held. Should this version stay held, or return to a natural life?

- **Update Held** — overwrites, explicitly keeps the new version permanent
- **Let this return** — replaces the held entry with the edited version, starts a fresh six-week
  life, clears previous renewal history
- **Cancel**

**No version history.** The overwritten text is gone. A revision log would be an accumulating,
undeletable record of exactly the material this design exists to let go of.

---

## 5. The return queue

### Collisions

Concurrent timers must never cause an entry to disappear before it was actually shown. Silence can
only mean release *after the question was presented*.

- At the end of its interval an entry becomes **ready**
- The oldest ready entry appears when the owner next opens the space
- **Only then does its seven-day grace period begin**
- Only one entry can be presented at a time
- After it is resolved or expires, the next ready entry appears on the owner's **next visit**, not
  immediately
- No count, no indication of how many are waiting
- Ordering is strictly chronological, never ranked by content, length, or behaviour

An entry can therefore sit ready for a long time without being at risk from the grace period. The
clock that can *release* something only ever runs while the person has been asked.

### The outer bound

Presentation-gating means an entry is only at risk while someone is looking at it, so avoidance
would otherwise preserve everything. A person who uses the shared side daily and never opens this
space would accumulate an unbounded set of ready entries — the exact vault this design exists to
prevent, reached by the one path the mechanism cannot see.

The fix is a bound on the entry, not a rule about the person.

| Field | Value |
| --- | --- |
| `ready_at` | one interval after creation, or after the most recent edit or renewal |
| `unseen_delete_at` | 1 year after `ready_at` |

The interval is the one belonging to the entry's current stage — 6 weeks in first life, 12 in first
renewal — not always 6. §3 is the governing statement: editing restarts the current interval, it
does not demote the stage.

- If the entry is presented before `unseen_delete_at`, the ordinary seven-day decision window
  replaces the unseen bound
- If it is never presented, **server-side deletion occurs at the outer bound**
- Visiting the shared side has no effect
- Opening this space without reaching that queued entry has no effect
- Held entries are exempt
- Editing or renewing recomputes `ready_at`, and `unseen_delete_at` follows it

**Rejected: a space-level dormancy rule.** Keying deletion to whether someone visits this space
turns visiting into maintenance. People would learn that opening it preserves their writing, which
produces checking behaviour and makes absence feel dangerous. That is the opposite of the quietness
the product is for.

This is not "silence means release". It is a separate rule with a separate justification:
**unrenewed private storage has a maximum life, even when the renewal moment cannot reach the
owner.** Describe it that way. Never describe it as one year of inactivity — it follows the entry's
state, not the person's behaviour.

### Snooze — "Give me a week"

One action, one week, once.

- The current return disappears immediately
- It returns exactly seven days from the moment of the action
- A fresh and final seven-day decision window begins then
- The exact final deletion date is shown before confirmation
- No second snooze
- No notification
- Silence during the final window means server-side deletion

> This will return on 21 September. If you do nothing, it will be let go on 28 September.

### Dormant accounts

An abandoned account must not quietly become the vault this design exists to prevent.

**If the product has not been opened for 90 days, every unheld entry is deleted, including entries
waiting to return.** Disclosed once in privacy settings; never repeated on individual entries.

---

## 6. Prepared offers

"Prepare" creates a **separate, frozen artifact with exact wording the person approves**. It is not
a pointer to the entry and does not carry the entry's text.

The partner never sees the source entry, the renewal count, the dates, or the fact that anything
matured. From the partner's side, a prepared offer that crosses is indistinguishable from a topic
composed from scratch that morning.

**A prepared offer has its own, shorter life: 2 weeks, one return, send or let go.** No third
option, no permanence. If it did not cross in two weeks, the preparation was the work.

Without this, the design rebuilds the pile one room over, with heavier objects, since an addressed
unsent thing weighs more than a private note.

---

## 7. The surface

The most distinctive version of this does **not** open onto a reverse-chronological journal. A
product that visually celebrates accumulation while claiming to resist it is telling on itself.

It opens onto:

- a quiet place to write
- one returned entry, if one has been presented
- a secondary drawer for held things
- an unobtrusive way to inspect living entries when needed

No feed, no archive aesthetic, no "47 memories", no inbox count, no streak, no overdue state, no
guilt language anywhere.

---

## 8. Copy

| Surface | Copy |
| --- | --- |
| Compose | Write without deciding what it becomes. |
| Saved | This will return in six weeks. |
| Save detail | Returns on 14 September. If it has not reached you, it will disappear by 14 September next year. |
| Return | Still yours? |
| Actions | Keep for now · Let go · Keep indefinitely |
| Second return | Keep this only for me · Prepare something I could offer · Let it go |
| Snooze | Give me a week |
| Snooze confirm | This will return on 21 September. If you do nothing, it will be let go on 28 September. |
| Held drawer | Held |
| Held → living | Let this return |
| Held edit | You changed something held. Should this version stay held, or return to a natural life? |
| Shared path | Prepare an offer |
| Empty | Nothing is waiting for you. |

Forgetting is **invisible to the partner and completely legible to the owner**. The owner always
knows the exact dates — both the return and the outer bound. They are stated at save, available in
entry details, and never displayed as a countdown on the object.

### Deletion copy must promise a measurable outcome

Until the key architecture in §10 is built and verified, the product says **"unrecoverable within 24
hours"**, not "deleted instantly". A promise the infrastructure cannot yet demonstrate is the kind
of footnote that destroys this concept.

---

## 9. Notifications

**Ship with no push notification for returns.**

"Something in Yours is ready for you" on a lock screen, on a phone lying face up on a shared
counter, tells a partner that something private matured today. Timing metadata escapes the device
even though it never touches the database. That is a leak, in exactly the register this product
cannot afford.

Returns surface in app, discovered rather than announced. This also respects the standing constraint
of one notification per day maximum, which the shared experience already spends.

If testing shows the loop dies without a signal, the only acceptable fallback is a notification
**deliberately indistinguishable from every other notification the product sends** — never one that
names or implies the space.

---

## 10. Deletion, and who owns it

The claim "it is gone" has to survive a skeptical reading.

### Why Supabase Vault is not the deletion boundary

Vault stores secrets encrypted on disk, and its own documentation is explicit that **the encryption
key is never stored in the database alongside the data** — Supabase creates and manages the root key
in their backend systems, deliberately kept separate from the project's Postgres instance
([Vault docs](https://supabase.com/docs/guides/database/vault)).

That is excellent disaster recovery and the precise opposite of what this design needs. Because the
root key lives outside the database, a same-project restore brings back ciphertext that the still
live key can decrypt. Restore and branching flows carry the key forward
([backup docs](https://supabase.com/docs/guides/platform/backups)). Recovery is the product goal
there. Forgetting is the product goal here.

The same objection applies to keeping wrapped data keys in an ordinary Postgres table: PITR restores
the ciphertext and the key together, and deleting a row is a deletion *request* with a retention
window attached, not a deletion.

### The boundary

- Supabase stores ciphertext and lifecycle metadata only
- Every entry gets its own data key
- Data keys live in a **dedicated service outside Supabase's backup domain**
- That service keeps **no restorable history for destroyed entry keys**
- Expiry destroys the data key first, **verifies destruction**, then removes the ciphertext
- The user chooses deletion, WE executes it, infrastructure enforces it
- A **named WE security owner** owns the policy, monitoring, failure recovery, and threat model

### The tradeoff, stated plainly

Losing the key service could destroy private entries. For this product, recoverability and
forgetting genuinely conflict, and the design chooses forgetting. That is a decision to make
consciously and in writing, not to discover during an incident.

### Also required

- Raw text never enters analytics, embeddings, logs, crash reports, or the shared intelligence layer
- Expiry is **server-side**, never dependent on the owner reopening the app
- No partner-accessible event is generated for creation, renewal, expiry, or deletion — not a row,
  not a timestamp, not a changed `updated_at` on any shared object
- Private deletion is immediate when the relationship or the account ends
- Written threat model before ship, covering at minimum: backup and PITR scope, replica lag, WAL
  retention, log sinks, crash-reporter payloads, and any Edge Function touching plaintext in transit

---

## 11. Multi-device authority

- The **server holds authoritative state**
- The first successfully saved action wins
- Other devices dismiss their stale copy on reconnect
- Renewal, holding, and snoozing require server confirmation
- **Let go** takes effect locally immediately and queues destruction if offline
- **Nothing can resurrect an entry once destruction has begun**

---

## 12. Phased test

Do **not** launch a generic private space with a "not yet" state. That tests an ordinary notes
feature and teaches nothing about the premise.

Test forgetting on the private proposals the product already creates:

1. Give each private proposal a six-week life
2. Resurface it once
3. Offer keep, release, or prepare an offer
4. Learn whether deletion produces relief or anxiety
5. Expand into general private writing only once that behaviour feels right

Same thesis, far smaller trust surface.

**Interpret a positive result narrowly.** A private proposal is already partner-directed, so
releasing one is avoidance-shaped and will read as relief in the data for reasons unrelated to the
thesis. Free writing about oneself is a different emotional object. Ask people *why* they released,
not just whether it felt good.

---

## 13. Metrics

- Do people write again before the first return
- Does resurfacing feel welcome or intrusive
- Does everyone choose permanent — which would signal fear, and mean the mechanism is being defended
  against rather than used
- Do people explicitly prepare offers
- Do users report trusting the product *more* because things actually disappear
- **Do people write less, or write shallower, once they know entries return and ask to be justified**

The last one matters most and is the only one that catches the real failure mode. Every other
measure tracks what happens to entries after they exist. If knowing about the return stops people
putting the hard thing down in the first place, the feature has inverted its own purpose while
reporting healthy keep and release rates.

**"Let go" is a successful outcome.** Optimising for keep-rate would corrupt the product. Do not
shorten the lifecycle or add nagging to improve engagement graphs; this is a slow trust moat and the
shared experience carries near-term value.

---

## 14. Decision log

### Locked

1. **Spoken name is Yours**, with one bounded teaching moment during the Promise and first entry,
   then wordless permanently
2. **No cap on Held**, high invisible technical limit, owner-initiated review only
3. **Held is reversible** via "Let this return", fresh first life, renewal history cleared
4. **Six weeks fixed**, no per-entry picker; any future change is one account-level setting
5. **Return queue is chronological and presentation-gated** — the grace period starts when the entry
   is shown, never before
6. **Outer bound of one year after `ready_at`** for entries never presented, exempting Held. A
   space-level dormancy rule was rejected because it would make visiting the space feel like
   maintenance
7. **Editing a held entry forces an explicit choice**; no version history
8. **Snooze is one week, once**, exact deletion date shown, no notification
9. **Key destruction is WE-owned and external to Supabase's backup domain**

### Open

- **Which key service, and who owns its destruction path.** Treat as a short architecture
  investigation, not a product question. Deliverables: chosen service, verified destruction
  semantics, restore and branching behaviour, failure and monitoring plan, named security owner.
  Everything else in this document can proceed in parallel; the deletion *copy* cannot ship until
  this closes.
