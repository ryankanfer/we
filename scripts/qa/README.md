# QA automation

The scripts in this directory are the only command surface used by GitHub
Actions. Run them from the repository root.

## Required pull-request checks

Configure the default branch's ruleset to require these exact GitHub check
names:

- `Schema + privacy contract`
- `iOS build + unit`
- `Critical UI smoke`

Workflow files can publish stable checks, but GitHub branch protection itself
is repository configuration and cannot be committed here.

## Pinned Apple toolchain

The workflows require:

- GitHub's `macos-26` runner image
- `/Applications/Xcode_26.3.app`
- iOS Simulator runtime `26.2`
- iPhone 17 Pro for pull requests
- iPhone 16e and iPhone 17 Pro Max for nightly rendering

`prepare-simulator.sh` creates a fresh device and deletes only that exact UDID
afterward. The accessibility profile sets the maximum Dynamic Type category,
Reduce Motion, and Reduce Transparency before restarting SpringBoard.

## Isolated live-couple contract

The nightly `Live couple contract` check requires three GitHub Actions secrets:

- `WE_QA_SUPABASE_URL`
- `WE_QA_SUPABASE_ANON_KEY`
- `WE_QA_SUPABASE_SERVICE_ROLE_KEY`

They must point to a dedicated, disposable QA project, never production. The
service-role credential remains in the host coordinator only. Each coordinator
saves it in a non-exported shell variable and unsets
`WE_QA_SUPABASE_SERVICE_ROLE_KEY` before starting `xcodebuild`. XCTest receives
only the URL, anon key, unique run ID, and disposable user credentials; raw
result bundles therefore cannot record the service role. Host traps delete the
exact user IDs and couple created for that run, including on test failure.
Cleanup preserves the original test status, but emits explicit warnings if the
QA stack is unavailable and an exact disposable record cannot be removed.

`run-live-repository-contract.sh` provisions three unpaired users, then runs
`WETests/FieldSupabaseLiveContractTests`. That comprehensive lifecycle keeps
pairing, onboarding, capture/correct/send, privacy, mutual reveal,
restart/offline/reconnect, sign-out, deletion, and archive coverage in one
simulator-hosted app process. Both live paths use the dedicated, serial
`WE Live Contract` test plan, so they do not build or inherit UI-test launch
fixtures.

`run-two-simulator-contract.sh` provisions a separate paired cohort, builds the
host test once, and starts Partner A and Partner B in two app processes on two
distinct simulator UDIDs. A first waits for its Realtime channel's subscribed
callback and writes a unique readiness row. The host observes that exact row
before launching B; B then writes a capture with its own authenticated adapter,
and A must receive a Realtime event, reload, and see that capture as Partner B.
This is a literal two-process, two-simulator seam across the host network. It
does not claim that two UI automation drivers interact or that the simulator
radio stack is being tested.

The workflow deletes each exact ephemeral simulator UDID in `always()` steps.
Neither XCTest command is retried. Override `WE_LIVE_CONTRACT_SELECTOR` only
when intentionally renaming the comprehensive repository suite.

## Evidence and flakes

Every Apple test job uploads the raw `.xcresult`, console log, structured test
summary, XCTest attachments, and diagnostics even when the test command fails.
Golden-test actual images must be attached with names beginning `golden.`.
`export-xcresult.sh` makes them reviewable without Xcode, and
`compare-screenshots.swift` compares decoded sRGB pixels against the committed
PNG with the same attachment name. The reference roots are:

- `WE/WEUITests/ReferenceImages/iPhone-16e/standard`
- `WE/WEUITests/ReferenceImages/iPhone-17-Pro-Max/standard`
- `WE/WEUITests/ReferenceImages/iPhone-17-Pro-Max/accessibility`
- `WE/WETests/ReferenceImages/Widget/iOS-26.2`

The maximum-accessibility reference is the deliberately sparse empty-Us
stress state. Its companion test audits the critical empty Today and Us zones
at Accessibility 5 with Reduce Motion and Reduce Transparency; the standard
small/large lanes carry the full set of launch and seeded-state goldens.

Record and approve references on the same Xcode 26.3 / iOS 26.2 hosted
runtime used by nightly CI. Images recorded on another runtime are useful for
review, but are provisional until the pinned job reproduces them.

The comparator permits a channel delta of 8 and at most 0.1% changed pixels
to absorb encoding noise without hiding layout or rendering regressions. Both
thresholds can be tightened through `WE_QA_MAX_CHANNEL_DELTA` and
`WE_QA_MAX_MISMATCH_RATIO`.

### Widget rendering boundary

`WEAmbientWidgetGoldenTests` renders the system-small and system-medium content
surfaces at fixed point sizes and a fixed 3x scale. The render implementation
lives in `WEShared`, so those tests and the WidgetKit extension compile and draw
the same family branching, typography, continuity mark, copy, and WE-owned
background. The widget result bundle and references are deliberately separate
from the full-screen app bundle so attachment names and reference sets cannot
collide.

This is a contract for pixels WE owns, not for pixels the operating system
owns. SpringBoard and the Lock Screen still supply the outer corner mask,
gallery chrome, system margins, and tinted-rendering transformations. There is
no supported API for installing a widget into a deterministic SpringBoard
layout, so the nightly check does not claim host-composited or accessory-widget
golden coverage. Those remain human release checks on the pinned runtime.

To record the widget-owned references on that runtime, run:

```sh
bash scripts/qa/run-xcode-tests.sh \
  widget-goldens \
  "platform=iOS Simulator,id=<UDID>" \
  artifacts/xcresults/widget-content.xcresult \
  artifacts/DerivedData/widget-content
bash scripts/qa/export-xcresult.sh \
  artifacts/xcresults/widget-content.xcresult \
  artifacts/reports/widget-content
```

Copy the four exported `golden.widget.*` PNG attachments into
`WE/WETests/ReferenceImages/Widget/iOS-26.2` only after reviewing them.

The workflows never retry a test. A quarantined test therefore needs a named
owner, linked defect, and expiry in the same change; there is no permanent
retry or ignore mechanism in this automation.
