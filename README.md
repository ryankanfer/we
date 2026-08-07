# WE

WE is a private relationship product for two people. It helps a couple hold what is personal,
coordinate what they carry, and open sensitive things only by mutual consent—without becoming a
score, chatbot, or task manager.

The native SwiftUI app is the active product. The frozen web implementation remains reference
material only; native development has no parity or maintenance obligation to it.

## Native product

The iPhone app has three primary destinations:

- **WE** — shared intelligence, private reflection, consent, and mutual reveal.
- **Life** — responsibilities owned by Me, Partner, or Together.
- **Ahead** — scheduled and unscheduled plans.
- **Profile** — account, appearance, archives, privacy, and Promise replay, opened from the
  avatar rather than a tab.

First use follows:

> Living Confluence Promise → create account or sign in → pair → choose personal hue → enter WE

The Promise introduces three commitments: yours stays yours, nothing crosses without both, and
what opens opens together. It is skippable, shown only on first use, replayable from Profile,
linear under VoiceOver, and uses crossfades when Reduce Motion is enabled.

## Trust model

Privacy is enforced in Supabase as well as Swift:

- A reveal request exposes the topic and sender, never an answer.
- Each person answers privately; answers appear only after both submit.
- A decline is owner-only. The initiator continues to see quiet waiting.
- A withdrawal leaves no partner-side trace.
- Completed mutual-reveal resolutions may enter a sanitized relationship archive.
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

- [x] Build Ahead, Life, Profile, complete Auth, Promise, Pairing, WE, and Insight Detail.
- [ ] Adapt information density for Mac — **deferred / N/A for this iPhone-first milestone**.
- [x] Add loading, empty, offline, inline error/retry, partner-waiting, and
  relationship-ended/archive states.
- [x] Keep the frozen web tag for comparison only.

Pull requests now gate schema/privacy, native build/unit, and serial critical UI flows. Nightly
automation exercises Partner A, Partner B, and an outsider against an isolated live Supabase
stack, then renders small/large/max-accessibility iPhone contracts with reviewable `.xcresult`
and visual-diff evidence. The remaining manual gates are VoiceOver and widget judgment, the
Supabase security-advisor/callback review, and five target-couple usability sessions.

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

## Deliberate exclusions

AI chat, advertisements, A/B infrastructure, external calendar accounts, finance integrations,
relationship scores, push notifications, recurrence, priorities, reminders, and Mac adaptation
are outside this milestone.
