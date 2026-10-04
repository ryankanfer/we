# Walkthrough fixes · October 2026

Source: Ryan's simulator walkthrough at `59778e4` (7/10), plus three asks of his own:
Trips needs adjusting, some notes belong on the calendar, and Mark complete and
Write the next step read as confusing.

## The idea that holds this together

**Read it back before it lands, then say where it went.**

Every finding below is the same failure seen from a different angle: WE decides what a
sentence means, and the person does not see that decision until it is too late to
argue with it. "Remind me to call mom tomorrow" silently becomes a search. "Bermuda
nov 1 to 5" silently becomes a film and loses its dates. A shared card silently looks
reversible. A save silently lands below the fold.

So three rules, written into code and tests:

1. **A sentence that starts a plan is never turned into a search.** Search is the
   exception and must be unmistakable.
2. **A date someone typed is never thrown away.** Whatever list it lands in, it
   reaches the calendar.
3. **The tutorial only demonstrates rules the app actually keeps.** If the tutorial
   shows it, the real app does it, in the same order.

## Phase 1 · Correctness (one PR) · implemented

### 1.1 "Remind me to" saves, "remind me what" searches

Cause: `FieldLookupEngine.lookupOpeners` contains bare `"remind me"`
(`WE/WE/Field/FieldDayConversation.swift:62`), so every reminder is read as retrieval.
`FieldPhrasing` already knows `"remind me to"` is a capture opener; the two lists
disagree.

Change:
1. Replace `"remind me"` with interrogative forms only: `remind me what`, `remind me
   when`, `remind me where`, `remind me who`, `remind me how`, `remind me if`,
   `remind me whether`, `remind me about what`.
2. Add a guard in `isLookup`: a sentence containing a task verb (`FieldClassifier.taskVerbs`)
   **and** a day phrase is never a lookup, whatever it opens with.
3. Composer (`FieldChatComposer.swift:59`, `FieldCaptureField.swift:194`): when a
   lookup is detected, keep a secondary **Save instead** control so a wrong guess costs
   one tap, not a retype.

Tests (`WETests/FieldDayConversationTests.swift`, `FieldTests.swift`):
`remind me to call mom tomorrow` → not a lookup, Care, due tomorrow ·
`remind me what we got dad` → lookup · `remind me about the vet friday` → capture ·
`find the hotel we liked` → lookup.

### 1.2 Account crash in seeded, demo, gallery and sparse launches

Cause confirmed: only the `.live` branch of `WEApp.swift` injects
`.environmentObject(externalSurfaces)`; `FieldAccountView` requires it
(`Field/FieldAccountView.swift:15`). Inject the same controller in every preview
branch. Add a UI test in `WEUITests/WEAccountSurfaceUITests.swift` that launches with
`WE_FIELD=seeded` and opens Account.

### 1.3 Dates are never thrown away; Trips carry a span

Today the model forbids it: `LifeCategory.dateless = [.watchlist, .trips, .talk]`
(`Field/FieldModel.swift`), and `FieldStore` erases `dueOn` when a receipt moves into
one of them (`FieldStore.swift:1325`, `:1339`). That is why a trip only kept its date
when Ryan moved it by hand, and why some notes never reach the calendar: the parser
only understands weekday words, so "dinner with the Parks oct 18" has no date to keep.

Change:
1. **Parser.** Extend `FieldPhrasing` to read absolute dates and spans: `nov 1`,
   `november 1st`, `11/1`, `the 14th`, `nov 1 to 5`, `nov 1-5`, `nov 28 to dec 3`,
   `11/1-11/5`. A date already past this year rolls to next year. `Result` gains
   `timing: WEObjectTiming?` (the type already supports `startDay` and `endDay`), with
   `dueOn` kept as its start for existing callers.
2. **Model.** Trips leave `LifeCategory.dateless`; Watchlist and Talk stay in it, so
   a film is still never due on Thursday. Any date typed into Trips, Notes or a task
   list now survives to the calendar.
3. **Trips specifically.** A dated Trips item lives in three places at once, each a
   reading of the same record: the Trips list, the calendar (across every day of its
   span), and Us as a horizon. See 1.4.
4. **Purpose.** `FieldItemPurpose.resolve` treats any `dueOn` as a task. Add `.plan`
   for dated Trips (and dated Watchlist): date first, and the complete icon (2.5)
   appears only once the span has passed.
5. **Calendar.** `FieldCalendarSurface` already draws anything with resolved
   `objectTiming`, so it needs no filtering change, only span rendering (a hairline
   across the days, owner colour, no fill) and small previous and next month arrows
   beside the swipe.

### 1.4 A dated trip is also a horizon

`FieldHorizon` already has the fields this needs: `title`, `window`, `targetDate` and
`linkedLifeItemIDs`, whose comment says a horizon is "a reading of things already
written down, not a new copy." So the dated trip horizon is **derived, not stored**:

1. `FieldStore` exposes horizons as the stored ones plus one derived horizon per
   shared, undone Trips item with resolved timing. Title is the trip title ("Bermuda"),
   `window` is the span ("Nov 1 to 5"), `targetDate` is its first day, and
   `linkedLifeItemIDs` is the item. A stored horizon already linked to that item wins,
   so nothing appears twice.
2. Because it is derived, it cannot drift: change the dates on the trip and the
   horizon and the calendar move together; delete the trip and both are gone. No new
   table, no migration, no second write to sync.
3. **Only me trips do not become horizons.** Us is shared furniture, so a private trip
   appears on the owner's calendar only. The moment it is shared it appears in Us for
   both, which is exactly the one way crossing the privacy contract allows.
4. A derived horizon never takes the primary slot; it appears in Us under its own
   heading, **Coming up**, soonest first, and tapping it opens the trip.
5. After the span ends it leaves Us. The Trips item stays, ready for **We went**.
6. `FieldPromotion` is unchanged: undated trips mentioned twice still get the
   question. Its "a thing with a date is already a plan" rule now has a home: dated
   trips skip the question and go straight to Us.
7. Retire the `LifeCategory.dateless` comment that says "a trip with a date is not a
   list item at all any more"; it now is both.

Tests: shared `Bermuda nov 1-5` produces one horizon with window Nov 1 to 5 and one
calendar span · the same item Only me produces a calendar span and no horizon ·
editing the dates moves both · deleting the trip removes both · a stored horizon
linked to the item suppresses the derived one.

### 1.5 "Bermuda nov 1 to 5" is a trip

Cause: no place word matches, no weekday matches, so `route` falls to
`looksLikeTitle` and files a Watchlist film.

Change, in `FieldClassifier.route` (`Field/FieldIntelligence.swift`):
1. A parsed **span of more than one day** with no task verb routes to Trips. Multi day
   spans are almost always trips; that is a stronger signal than any word list.
2. When any date was parsed, skip `looksLikeTitle`. Films do not come with a date
   range.
3. Fold the grown `travel` domain (flight, hotel, airbnb, passport, itinerary) into
   Trips. Today a couple can end up with both Trips and Travel, which is the exact
   duplication `lifeCategory` exists to prevent.
4. When still unsure, land in Notes, never Watchlist.
5. `FieldSmartClassifier` prompt: add "a place name, especially with dates, is trips."

Tests: `Bermuda nov 1-5` → Trips, Nov 1 to 5 · `Dune` → Watchlist · `Dune opens
friday` → Watchlist, dated · `flight to lisbon dec 3` → Trips, Dec 3 · `dinner with
the Parks oct 18` → Food or Notes, dated, on calendar.

## Phase 2 · Teaching and words

### 2.1 Tutorial privacy is chosen before saving

`WalkthroughView` currently files the card, then offers the switch on the saved card.
Reorder: the draft card carries **Both of us / Only me** while it still reads NOT
SAVED; the person chooses, then saves. After saving a shared card, the switch is gone
and one line says it plainly: *"Shared stays shared. Choose Only me before you save."*
Add the rule to the promises list: *"Private can become shared. Shared never goes
back."* Matches `README.md` and Account, which already say so.

### 2.2 "Wrong spot? Tap it and move it" works

Make the practice card tappable and present the real `FieldCategoryPicker`. Moving it
retitles the card and nothing is recorded. Teaching the real control beats rewriting
the sentence to point somewhere else.

### 2.3 The waiting handoff says where it goes

`handoffTitle` for `.waiting` becomes **Back to your invitation**, and `finaleTitle`
becomes *"Your invitation is ready."* (a code existing is not delivery). The solo
question is below.

### 2.4 "Share it on a day" becomes "Ask me on a day"

`WEOnlyMeCopy.holdPrompt` (`Field/WEGateCopy.swift:250`). The follow up line already
describes a prompt; the button now does too.

### 2.5 Mark complete and Write the next step

What they actually do today:
1. **Mark complete** sets `isDone` with no undo (there is no reopen in `FieldStore`),
   and on a shared item it finishes it for both people without saying so.
2. **Write the next step** opens a text field whose button says **Save note** and
   appends to `detail`. It is a note wearing a task's name.

Change:
1. **Remove the Mark complete button.** In its place, a **complete icon**: an empty
   circle at the top trailing edge of the item sheet, beside the title, 44pt hit area.
   Tap it and it fills with a check, the title settles to the done style, and a
   five second **Undo** appears, backed by a new `FieldStore.reopen(_:)` through the
   same outbox path as `complete`.
2. The icon is silent but its label is not. VoiceOver reads the item's own verb
   (**Called**, **Booked**, **Bought**, **Watched**, **We went**, falling back to
   **Done**), and on a shared item adds *"for you and Dylan"*, so finishing something
   for both people is never a surprise.
3. It appears on tasks, and on plans once their date has passed. Reference items
   (links, notes, undated Watchlist) have no icon, as they have no button today.
4. Rename Write the next step to **Add a note**, everywhere, so the label matches the
   button and the result. Links keep **Thoughts to share**.
5. For a dated item, the date sits at the top of the sheet and is editable in place
   (`WEObjectTimingEditor` already exists), ahead of external search suggestions.
   Any undated item gets **Add a date**, which is how a note reaches the calendar
   when the parser could not.
6. Replace the generic **Do** action label with the concrete verb from
   `FieldItemPurpose.actionLabel`.

## Phase 3 · Confidence at the moment of saving

### 3.1 The read back line, before sending

Under the draft in the composer, one line built from the receipt: **Trips · Nov 1 to 5
· You and Dylan**. Each part is tappable: list opens the picker, date opens the timing
editor, audience flips the switch. This is the fix for 1.1 and 1.4 that remains
useful after the rules improve, because rules will always miss something and the
person should catch it before it lands.

### 3.2 The receipt, after sending

After `send()`, Today shows a quiet line pinned above the composer for four seconds:
**Saved to Trips · Shared with Dylan** with **Open**. Announced to VoiceOver. No light
behaviour: saving your own thing is not a moment between two people, so it does not
pass the sentence test, and the lights stay out of it.

### 3.3 Documentation drift

Bring `README.md`, `docs/design/US_AND_CAPTURE.md` and the walkthrough UI tests in line
with the current flow, so a reviewer's evidence matches the app.

## Ambitious direction · one structured read on device

Replace the single word answer in `FieldSmartClassifier` with a Foundation Models
`@Generable` struct: `intent` (save or ask), `list`, `place`, `span`, `confidence`. One
on device call returns everything the read back line shows, and the confidence decides
whether the line is quiet or asks for a tap. The rules stay the floor and keep two
absolute authorities the model never overrides: privacy, and turning anything into a
search. It is feasible on iOS 26 today, but it needs a set of test sentences to measure against (the test
sentences above are the start of it) before it ships, and it does nothing on phones
without Apple Intelligence, which is why it sits after Phases 1 to 3 rather than
instead of them.

## Decision taken by default

1. While waiting for a partner the handoff returns to the invitation. Solo adding
   (Only me items before the partner joins) is a product decision, not a copy fix,
   and is left out until Ryan chooses it.

## Order and verification

Phase 1 ships first as one PR: it fixes the two behaviours that lose intent and the
crash, and every change is covered by unit tests. Phases 2 and 3 follow as one PR each.
Each PR runs `WE.xctestplan`, then a simulator pass of the exact sentences in this
document. Real two person sync, notifications and an accessibility audit remain
outside this plan, as the walkthrough noted.
