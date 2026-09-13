# Us: a shared future

Us holds longer-term possibilities and goals. Life holds the linked actions, links, and references.

- Exploring: either person can create and shape a possibility.
- Building together: two individual approvals for the current scope. Either person can withdraw their choice. Editing purpose, timing, kind, currency, or target requires renewed agreement; savings updates, notes, milestones, and linked items preserve it.
- Goal tools: manual target/progress, milestones, shared thoughts, connection to existing Life items, and explicit next steps that remain in Plans even without a date.
- Existing shared conversations remain reachable from the bottom of Us.

## Intelligence in this version

On-device NaturalLanguage place recognition and explicit aspiration rules group three distinct shared Life items, including saved-link notes. Initial coverage is trips, getting a dog, and a home/down-payment aspiration. This is explainable topic detection, not general generative synthesis or access to outside messaging apps. Private items are filtered before analysis. Disabling shared-plan signals stops suggestions. Suggestions expose the evidence and connect to an existing matching goal when possible.

Not now pauses a topic for 14 days on this account/device. Don’t suggest this suppresses it on this account/device. Dismissal preferences are cleared on sign-out with other local relationship data.

## Persistence

Horizon `goal_plan` stores goal content through the existing outbox. Authenticated approval rows are separate. The current-approvals view checks revision and the exact goal scope, under row-level security. Clients cannot save approvals inside plan JSON or approve for their partner. Approval requires connectivity; content edits can queue locally. An explicit-task flag keeps goal actions in Life Plans.

Applied migrations: `20260907230816_us_shared_goals` and `20260907231517_explicit_life_tasks`.

## Verification

15 focused Swift tests passed (FieldGoalTests and FieldActionWorkspaceTests). Transactional database checks passed for individual voting, forged-partner denial, two-person approval, unchanged consent during progress updates, invalidation on scope changes, reapproval, withdrawal, and account isolation. Test database rows were rolled back. Supabase security advisor reported no findings against the new goal objects.

## Follow-on work

Broader semantic suggestions and richer dedicated planning tools can build on this structure. Whole-plan progress edits follow the existing last-write-wins outbox model; concurrent changes to the same notes/milestones can overwrite each other. Bank/travel connections are not implemented. Beta ideas/feedback work remains parked per the current Us focus.
