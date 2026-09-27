# Shared conversation

The readiness ritual is retired. Today’s mark opens conversation; Chat is also available across the main zones. Legacy queued readiness taps decode and drain without sending or opening the old ceremony.

## Behavior

- One couple-scoped conversation, immutable messages, idempotent client IDs, durable outbox, visible pending/retry states, chronological history and keyset pagination.
- Attach shared Life items or Us goals. Private items are excluded in the UI and checked server-side. Links open only when tapped; no background preview fetching.
- Sending a non-decision message now keeps every distinct HTTP(S) link in Life → Saved. Drafts remain unsaved. The message, new references, and an attached Us goal’s link connections are staged in one durable local write; sync status is visible per link.
- Reuse an active shared Life item with the same URL without overwriting its title, notes, or plan. Private items never participate in matching. URL identity preserves queries/fragments and normalizes host case, default ports, and an empty root path. Simultaneous first saves from two offline devices can still create duplicates; this client change does not introduce a server URL uniqueness constraint.
- Link rows open the original and the saved Life item. Remove a reference from Saved without deleting the conversation, or keep it again. Older messages offer “Keep in Life” per link. Tasks and decisions remain explicit choices.
- Life items and Us goals open a focused conversation with “Show all” to return to the full history. Related messages are matched by attached context and shared URLs. Older related messages require “Load earlier messages”; focusing a subset does not clear the full conversation’s unread marker.
- The attachment picker searches shared Life items and Us goals. Domain/path previews are local; no background metadata fetching.
- Propose a decision from a message; the other partner must confirm before it appears in Decisions. Search applies to loaded decisions; load earlier for older history.
- Both partners explicitly opt in before on-device recurring-topic suggestions run. Shared-plan signal settings also gate suggestions. This is topic recognition, not generative synthesis or reading outside messages. Suggestions remain outside message history and need explicit acceptance. Existing dated, connected Life items may appear as one contextual reminder.
- No visible read receipts, presence tracking, automatic assignments, or unsolicited AI messages. The server read watermark supports unread indicators and suppresses unnecessary push.

## Deployment

Applied migrations: 20260908021737_shared_conversation, 20260908022211_conversation_notifications, 20260908022340_chat_source_integrity.

`notify-conversation` is deployed with dedicated secret-key authentication, generic notification text, and coalescing by recipient. The existing vault references `arrival_worker_key` and `arrival_worker_url` are absent, so scheduling was intentionally not enabled. APNs configuration also needs verification. Background notifications are therefore unavailable and the app says so. After credentials exist, install the schedule from the notifications migration and validate delivery on physical devices; do not rerun the whole migration. Push is best effort; message storage is durable independently.

## Verification

September 13 link update: conversation/goal/outbox tests passed, including queued-goal dependency ordering after repeated offline sends, then conversation/action-workspace regressions and the simulator round trip passed (22 tests, overlapping the first run). UI coverage also exercises multiline composition with the keyboard visible and the largest in-app Dynamic Type setting. Screenshots were inspected; the composer uses a bottom safe-area inset to preserve navigation, with a compact accessibility layout. Outbox compaction keeps pending Life/Us context writes ahead of the earliest message that depends on them. These checks use fictional preview data and do not send couple messages to the service.


57 tests passed across conversation, goal, action-workspace, and outbox suites. Database transaction checks passed for sender isolation, immutable text, idempotent retries, partner-only confirmation, pagination, read/preference preservation, and account isolation. All test rows rolled back. The notification worker rejects unauthenticated POSTs. Security advisor flags only the deliberately service-only notification queue as RLS-without-policy (INFO) among the new objects.

Simulator: checked the empty state, composed/sent a fictional linked message, kept it in Life, and verified the menu then opened the saved item. No real couple messages were sent during verification.

## Current limits

No background push until infrastructure configuration; no general conversational AI synthesis. Draft text stays in memory until sending; sent messages are durably queued. Savings and goals retain the previously documented whole-plan last-write-wins semantics. Beta feedback additions remain parked.
