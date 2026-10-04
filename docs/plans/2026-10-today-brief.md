# Today as a daily brief · October 2026

Today stops being a chat transcript and becomes a short brief about the couple's
shared life: what matters now, what the other person kept, what is coming, and then a
natural stopping point.

## What shipped

**Hierarchy, top to bottom**

1. **Header.** The two lights at text size, "WE", and the date. No "Today" headline;
   the bar already says where you are, and the greeting bubble is gone.
2. **Lead.** The selector's own moment, unchanged in what it chooses: eyebrow,
   expressive serif headline, one factual sentence built only from what is written on
   the item ("Closes today at 9:00 PM.", "Nov 1 to 5.", "Tomorrow at Lilia."), one
   filled action, the quiet escape, and "Why this?" folded underneath. A question
   keeps its two equal choices and uses its stakes as the sentence.
3. **Lead image.** Only when the item arrived as a link, read on the phone through
   LinkPresentation. The 3:2 frame is reserved before the picture arrives, and if
   it never does the frame holds the site's name: an intentional plate, never a
   broken image, and never a picture looked up by title.
4. **Partner discovery.** "Dylan kept this yesterday." Title, one line of context,
   their light, and a 72pt thumbnail only if it came from a link. On a quiet day it
   leads instead.
5. **Looking ahead.** One dated thing after today, trips first, with a Calendar
   button beside the label, so the month is discoverable from Today too.
6. **To decide together.** Proposals still waiting for an answer, with Agree for the
   partner's and "Waiting for Dylan" for your own. A proposal never becomes a
   decision without the other person.
7. **The rest, and the way in.** "Two more things today" and the held line open what
   the brief did not show, then **Keep something** and **Ask WE** end the page.

**Moved off the page**

1. Look ups open **Ask WE**, a separate sheet, private and in memory, answered only
   with real records. The composer opens it when it reads a question.
2. Saving confirms from the bar (`savedLine`): destination, visibility, Open. The +
   card no longer jumps to Today after sending.
3. The transcript view and its model (`FieldDayConversationView`, `FieldDayEntry`,
   the thread and greeting copy) are deleted. The look up engine and proposal rules
   stay.

**Words.** The + is "Keep something" everywhere, the composer and the tutorial
included, so the tutorial keeps teaching the real control.

## Selection rules (`FieldTodayBrief.swift`, tested in `TodayBriefTests`)

1. The lead is `todaySelection`. Nothing about what needs attention changed.
2. A discovery is the partner's own item, shared, open, a reference or a plan (never
   a chore), with a capture of theirs in the last 7 days. Newest first, id as tie
   break, so the choice is stable across redraws.
3. Looking ahead: open, dated, after today, within 90 days, plans before tasks, then
   soonest.
4. Claim order lead, discovery, ahead: nothing appears twice.
5. A partner's private row is filtered on this page even though it should never be on
   this phone. One's own private upcoming item is shown with "Only me".
6. Everything is derived on each draw: completing, editing or deleting an item
   changes every place it appears. No Today collection exists.

## Lights

No new behaviour. The header mark is static identity; the discovery row uses
`theirs` ("Theirs."), proposals use `leaning` ("One of you has said yes."). Both pass
the sentence test, neither moves.

## Not in this release

1. Recommendations of anything nobody kept. Discovery is deliberately shared items
   only.
2. Images for items without a link, including any venue nobody chose.
3. "Find our spot" style actions. Every button opens a real item or a real choice;
   the lead's action is the existing verb, which opens the item.

## Verify on an iPhone

Active day (seeded), quiet day (empty plus one partner link), empty account, an Only
me upcoming trip, a pending proposal from each side, a 60 character title, a link
whose page has no picture, airplane mode with a cached picture. Then the largest
accessibility text size (thumbnail stacks above text, capture bar stacks), VoiceOver
order (header, lead, discovery, ahead, proposals, more, keep, ask), Reduce Motion and
Reduce Transparency.

Baseline failures before this work: `docs/qa/2026-10-test-baseline.md`.
