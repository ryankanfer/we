# Native app polish · 13 September 2026

Scope: a focused pass across Today, Life, Us, Calendar, search, capture, saved-item review/recovery, Chat, Yours, and Account/authentication. Existing typography and canvas tokens remain the design foundation. This is a polish pass, not release certification.

Changes:
- Label Yours offer fields and held-writing editor for VoiceOver.
- Give Chat tabs selected traits and 44-point targets; distinguish empty search results and clear decision filters when returning to Conversation.
- Make search wording accurately describe its eligible content and use consistent “Needs attention” entry copy.
- Count dated private objects and overlapping ranges in Calendar; keep active private dots visible.
- Make Calendar accessibility children individually discoverable, allow long agendas to scroll, and keep Done/Today reachable. Vertical scrolling replaces vertical dismissal; horizontal month navigation remains.
- Use readable semantic type for Us concepts at accessibility sizes.
- Give saved-item forms the Life cream canvas and a valid Saved category selection.
- Save established design context in .impeccable.md.

Verification is recorded below after the final run. Physical-device VoiceOver, small-phone coverage, and the existing intelligence deployment/archive/two-phone release gates remain unexecuted. No release flag or backend deployment changed in this pass.

Executed on iPhone 17 Pro simulator (iOS 26.3, deployment target 26.2):
- Account sign-in, creation/reset, and largest-text exits: 3 passed.
- Capture persistence/search and recovery/source review: 2 passed, repeated after form styling.
- Us evidence and ghost completion: 1 passed.
- Main surfaces/exits and largest-text navigation: 2 passed after correcting Calendar accessibility.
- Chat link capture, saved-item navigation, and largest-text composer: 2 passed.
- Intelligence and relationship portrait model regressions: 12 passed.
- Screenshot inspection included Life, Us, Calendar, Yours, auth, and saved-item forms; source review additionally covered search/Chat accessibility labels and states. A separate reviewer identified the Yours and Chat issues.
- Initial smoke failure: Calendar’s container identifier replaced descendants’ identifiers. Corrected with an explicit accessibility container and rerun successfully.
- git diff --check passed.

Artifacts: /tmp/we-polish.xcresult (initial), /tmp/we-polish-final.xcresult (navigation/Chat), /tmp/we-polish-forms.xcresult (forms/model checks). Final Us long-concept bounds verification is in /tmp/we-polish-type.xcresult.
- Final Us bounds regression passed at accessibility5: every concept remains within screen width; final screenshot inspected.
