# WE

WE is a private relationship product for two people. It helps a couple hold what is personal,
coordinate what they carry, and open sensitive things only by mutual consent—without becoming a
score, chatbot, or task manager.

The native SwiftUI app is the active product. The frozen web implementation remains reference
material only; native development has no parity or maintenance obligation to it.

## Native product

The iPhone app has two places and one way in, fixed at the bottom: **Today · + · Life**.

- **Today** is a short brief, not a transcript. It reads top to bottom and stops: the one thing that matters now (a serif headline, one factual sentence, one action, and the item's own picture when it came from a link); something your partner kept this week; one dated thing coming up, with the calendar a tap away; anything still waiting to be decided together; then **Keep something** and **Ask WE**. On a quiet day what your partner kept can lead. Anything else that needs attention today is one line away ("Two more things today"), so the page is never short by hiding something. Every section is read from Life on each view; nothing is stored for Today.
- **Ask WE** answers questions about what is already written down ("what did we get for dad?") with links to real records only, on this phone only. A plan is never read as a question: "remind me to call mom tomorrow" is saved, "remind me what we got dad" is asked, and the card offers **Save instead** when it guesses wrong.
- **+** (Keep something) opens a card in the middle of the screen: write something, or paste a link. WE reads a link on the phone (title, site, picture) and says where it will go, and on what day, before it goes ("Goes to Trips · Nov 1 to 5"). Two circles send it to both of you; one circle keeps it Only me. After sending, a line above the bar says where it went and who can see it, with **Open**.
- **Life** is where everything lives. It opens on search, in the middle of the screen. Below that is **Where we're headed** (goals), then an icon bar: All, then each group (Care, Food, Trips, Watchlist, Buys…). Calendar is in the header.
- **Dates** are read as people type them: weekdays, "oct 18", "11/1", "the 14th", and spans like "Bermuda nov 1-5". A date someone typed is kept in every list except Watchlist and Talk, so it reaches the calendar. A dated trip is three readings of one row: an item in Trips, a span on the calendar, and (when shared) a horizon under **Coming up** in Where we're headed. Nothing is copied, so moving or removing the trip moves or removes all three.
- **Finishing** something is the circle beside its title. It fills, says the item's own verb (Called, Bought, We went), and can be undone for a few seconds.

**Only me** is a property of any item, not a place. Anything can be kept private, and sharing it later is one way: private can become shared, never the reverse. Nothing your partner sees is shaped by it. Yours, the separate private space, is retired; its writing moved into Life as private notes (`docs/archive/CIRCLE.md`).

**Decide on this together** turns a shared item into a proposal the other person agrees to. That agreement is the one thing stored as a message; everything else typed is filed into Life.

**Account** is the same screen before and after pairing, reached from the top of each place.

The first run is Welcome, sign in, pair or wait for your partner, then the Promise. Colours are fixed by role (the first person burgundy, the second sage); there is no colour step. The walkthrough never opens by itself: "See how it works" on the welcome and "See how WE works" in Account play it, and it never writes to a real account.

Retired words stay retired: `WELexiconTests` fails if one comes back into on-screen text.

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

There are two, and neither says what happened:

1. **Arrival**, once per space: the moment the second person joins, both phones
   receive the same fixed sentence, which names nobody and reports nothing.
2. **A decision is waiting**, opt-out in Account ("Tell me when … suggests a
   decision"): when your partner suggests deciding on something, your phone
   receives "Something is waiting for you both in WE." Nothing else — not what,
   not who. It is sent only within an hour of the proposal and only if Today
   has not already shown it.

No badge, no sound, no payload beyond the sentence. Local moments follow the
same rule. The permission is asked once, after the Promise.

Refusing notifications is a first class path, not a degraded one. The ceremony
is driven by persisted state and an aggregate that reveals no timing, so a
declined permission, a dropped push, or a project with no APNs credentials at
all costs a convenience and never correctness — the arrival is simply there
when the app is next opened. Nothing is retried, and nothing ever reports that
the other person was or was not notified.

See `supabase/functions/announce-arrival/README.md` and
`supabase/functions/notify-conversation/`.

## Deliberate exclusions

AI chat, advertisements, A/B infrastructure, external calendar accounts, finance integrations,
relationship scores, recurrence, priorities, reminders, and Mac adaptation
are outside this milestone.


## Private beta implementation

The current beta work and verification gates are tracked in [docs/PRIVATE_BETA.md](docs/PRIVATE_BETA.md). The walkthrough is five beats: hello, the three buttons, who sees it (chosen before anything is saved, because shared stays shared), saying it (the real classifier files a practice sentence, and the card opens the real list picker), and the promises. It is offered, never automatic, replayable, and never writes to an account.

The main places are Today and Life, with + between them; see Native product above.
