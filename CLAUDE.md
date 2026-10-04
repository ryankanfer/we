# WE

Private relationship product for two people. The native SwiftUI iPhone app in `WE/` is the
active product; the Next.js implementation is frozen reference material with no parity
obligation. See `README.md` for the trust model and
`docs/PRIVATE_TO_SHARED_CONTRACT.md` for what may cross from private to shared.
`docs/archive/CIRCLE.md` is the retired personal-space design, kept for its reasoning.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- iOS visual/device QA → invoke /ios-qa or /ios-design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

Note: this repo has no developer-facing product surface (package.json is `private: true`,
no published SDK/CLI/API). /plan-devex-review and /devex-review do not apply.

## The two lights

WE's signature is two soft lights at the bottom edge of the screen, one per
person, drawn by `WELights` (and `WELightsMark` at text size). `personA` is
always the viewer's own light and `personB` their partner's: pass
`store.viewerIdentity`, never the raw slot-ordered `store.identity`.

**The sentence test.** Every light behaviour must be legible as one sentence
about the relationship: "Dylan is here." "This is only yours." "You decided
together." If a moment cannot be captioned that way it is decoration, and it
does not ship. No idle breathing, no ambient drift, nothing that counts,
compares, scores or streaks. The lights react to what happens between the two
people, never to how much either of them does.

Current vocabulary (keep new work inside it or extend it deliberately):
- icon: the app icon itself, large and overlapping; the splash only
- apart: before anything, or not yet decided
- near: the resting state of a shared screen
- lifted: nothing has been added yet
- alone (+ dashed ring for their place): only yours, or waiting for them to join
- leaning: one of you has said yes
- merged / merge pulse: you decided together (kept rare)
- parting: their light going out, only after a partner leaves
- pulseTheirs: they just added something; pulseMine: something is waiting for you
