# WE

WE is a private relationship product for two people. It helps a couple hold what is personal,
coordinate what they carry, and open sensitive things only by mutual consent—without becoming a
score, chatbot, or task manager.

The native SwiftUI app is the active product. The frozen web implementation remains reference
material only; native development has no parity or maintenance obligation to it.

## Native product

The iPhone app has three primary destinations:

- **Life**: practical information, plans and commitments, with visible Search and Calendar.
- **WE / Today**: one relevant next action and a persistent capture entrance.
- **Us**: shared questions, proposals and agreed directions.

**Yours** is a labelled private writing entrance on Today. **Account** is visibly reachable from each main screen.

First use follows a skippable fictional practice story: capture, review visibility and date, correct, save, and retrieve. It never writes to a real account. Registration, invitation entry and sign-in follow; the joint Promise remains at partner arrival. An optional account-scoped first-save guide teaches the same loop with a real item.

The walkthrough can be replayed from Account and preserves pending invitation context. The current beta does not introduce a fourth main destination.

## Trust model

Privacy is enforced in Supabase as well as Swift:

- A reveal request exposes the topic and sender, never an answer.
- Each person answers privately; answers appear only after both submit.
- A decline is owner-only. The initiator continues to see quiet waiting.
- A withdrawal leaves no partner-side trace.
- Departure currently preserves shared records for the remaining member. Relationship archive support and replacement-partner visibility require explicit confirmation before destructive beta tests.
- Private reflections, unrevealed responses, pending requests, declines, and dismissals never
  enter an archive.

Protected database writes use server functions. Active-couple row-level security prevents
outsiders and former members from reading or mutating live relationship data.

### Private intake

The Share Sheet follows one release boundary:

> Private input → private artifact → explicit proposal → exact review → deliberate release

The extension accepts text, HTTPS links, and up to five normalized images. It has no networking
or model dependency. Drafts are encrypted inside the private-intake app group, isolated by a
random account vault, and remain visible only on that person’s side until the containing app
freezes and publishes an exact reviewed revision. Links and images begin excluded.

`From elsewhere` is controlled by `WEShareInboxEnabled`. The Xcode project enables it for Debug
verification and leaves it disabled for Release until the migration, cleanup worker,
accessibility checks, and end-to-end publication tests have passed against the release backend.
The widget is intentionally not a member of the private-intake app group.

LIFE’s “Where to look” is deterministic and purpose-specific. It never runs automatically, and
shows the exact title-based query and destination before anything leaves WE. No private detail,
partner identity, ownership, dates, or history is added to the query.

## Native milestone status

- [x] Build Ahead, Life, Profile, complete Auth, the Threshold walkthrough, Pairing, WE, and
  Insight Detail.
- [ ] Adapt information density for Mac — **deferred / N/A for this iPhone-first milestone**.
- [x] Add loading, empty, offline, inline error/retry and partner-waiting states.
- [ ] Reconcile departure/archive behavior with the private-beta decision and verify it.
- [x] Keep the frozen web tag for comparison only.

Pull requests define schema/privacy, native build/unit, and serial critical UI checks.
For this private beta, additional hosted two-account suites and their QA secrets are deferred.
Their presence in the repository is not proof that they ran. Current executed, skipped, and
pending checks are recorded in [docs/PRIVATE_BETA.md](docs/PRIVATE_BETA.md).
Direct negative authorization and concurrency checks remain release gates; the two-person
UI checklist cannot substitute for them. Existing local contract tools are documented in
[`supabase/probes/dual-sided/README.md`](supabase/probes/dual-sided/README.md).

## Running the iPhone app

Open `WE/WE.xcodeproj`, configure the local Supabase credentials, and run the `WE` scheme on an
iPhone simulator or device. Full setup, migration, preview, callback, and verification guidance
is in [`WE/BACKEND_SETUP.md`](WE/BACKEND_SETUP.md).

For backend-free design and UI testing, set:

```text
WE_REPOSITORY=preview
```

`PreviewRepository` implements the complete repository surface and supports ready, empty,
offline, error, waiting, archived, signed-out, and hue-selection scenarios.

## Frozen web reference

The original Next.js slice remains available for historical comparison:

```bash
npm install
cp .env.example .env.local
npm run dev
npm test
```

It is not the source of truth for native navigation, presentation, or maintenance.

## Notifications

**WE never sends a notification containing news, only ones inviting presence.**

There is exactly one, and it is sent once per space: the moment the second
person joins, both phones receive the same fixed sentence, which names nobody
and reports nothing. No badge, no sound, no payload beyond that sentence. Local
moments follow the same rule.

Refusing notifications is a first class path, not a degraded one. The ceremony
is driven by persisted state and an aggregate that reveals no timing, so a
declined permission, a dropped push, or a project with no APNs credentials at
all costs a convenience and never correctness — the arrival is simply there
when the app is next opened. Nothing is retried, and nothing ever reports that
the other person was or was not notified.

See `supabase/functions/announce-arrival/README.md`.

## Deliberate exclusions

AI chat, advertisements, A/B infrastructure, external calendar accounts, finance integrations,
relationship scores, recurrence, priorities, reminders, and Mac adaptation
are outside this milestone.


## Private beta implementation

The current beta work and verification gates are tracked in [docs/PRIVATE_BETA.md](docs/PRIVATE_BETA.md). The entry walkthrough now follows one fictional thought through capture, date correction and retrieval, followed by a brief explanation of privacy. It is skippable and replayable. After entry, an optional account-scoped guide supports a first real save.

The main destinations remain Life, WE (Today), and Us. Life and practical utilities use warm cream; Today, Us, and Yours retain their dark canvases. Yours and Account have visible routes. A fixed capture entrance opens composition without answering Today’s featured question first.
