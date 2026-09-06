# WE

Private relationship product for two people. The native SwiftUI iPhone app in `WE/` is the
active product; the Next.js implementation is frozen reference material with no parity
obligation. See `README.md` for the trust model and `CIRCLE.md` for product principles.

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
