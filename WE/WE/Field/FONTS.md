# Fonts

V2 §3 specifies two faces and no others:

- **Newsreader** — 300 for display, 400 for text, 400 italic for WE's own
  voice. Carries "everything human".
- **DM Sans** — 400, at 9–11pt with 1.8–2.4pt tracking, always uppercase.
  Carries labels and actions.

Both are Google Fonts and both are **bundled with the app, not loaded at
runtime**. The design uses almost no icons — coloured dots, hairlines, and
typography carry the meaning — so the faces are load-bearing in a way they
usually are not.

## The monospace is gone

V1 used IBM Plex Mono for labels, dates, counts and buttons. §3 cuts it: "There
is no monospace in the product — an earlier typewriter treatment was cut for
reading too retro against the serif."

The roles it carried kept their names and changed face, so `FieldType.zoneLabel`
and friends still exist and still mean the same thing. What changed underneath
is the family and the tracking notation — see below.

## What actually shipped

Nine faces in `WE/WE/Field/FONTS/`, listed under `UIAppFonts` in
`WE/Config/WE-Info.plist`. The target uses a file system synchronized group, so
the files needed no project edit.

```
Newsreader_14pt-Light.ttf        Newsreader_36pt-Light.ttf
Newsreader_14pt-LightItalic.ttf  Newsreader_36pt-LightItalic.ttf
Newsreader_14pt-Regular.ttf      Newsreader_36pt-Regular.ttf
Newsreader_14pt-Italic.ttf       Newsreader_36pt-Italic.ttf
DMSans-9pt.ttf
```

**There is no plain "Newsreader" family.** Google ships it as optical-size cuts
— 9, 14, 24, 36, 60pt — each its own family, and the variable file registers as
`Newsreader 16pt`. Nothing is named `Newsreader-Light`. So `FieldType.serif`
picks the cut by size:

```swift
let opsz = size >= 20 ? "Newsreader36pt" : "Newsreader14pt"
```

which is what `font-optical-sizing: auto` did in the browser the design was
drawn in. The display sizes get the 36pt cut and stay thin at weight 300;
labels get the text cut.

**DM Sans ships only as a variable font.** `ofl/dmsans/` in google/fonts holds
`DMSans[opsz,wght].ttf` and an italic, and no static cuts — the `static/`
directory the older layout had is gone, so fetching `DMSans-Regular.ttf` from
it returns a 404 page that `file` will happily tell you is HTML.

The bundled cut is instantiated from the variable font with fontTools:

```python
instancer.instantiateVariableFont(f, {"wght": 400, "opsz": 9}, updateFontNames=True)
```

Pinned to the **9pt optical design** on purpose: §3 uses this face at 9–11pt and
nowhere else, and the display cuts are drawn with a tighter fit than a 9pt
label wants. `updateFontNames` writes the optical size into the *subfamily* — name ID 17 —
and leaves the typographic family, name ID 16, as plain **`DM Sans`**. Core
Text indexes by the typographic family, so that is what
`FieldType.sansFamily` holds, and the face `.custom` asks for is the
PostScript name **`DMSans-9pt`**.

Newsreader is the other way round: its typographic family is
`Newsreader 36pt` and its subfamily is `Light`. Two Google families, two
conventions, and no way to tell from the outside — which is why
`bothFacesRegisterUnderTheNamesFieldTypeProbes` asserts both rather than
either being reasoned about.

Only weight 400 is bundled, because §3 gives this face one weight for both of
its roles. `FieldType.sans` takes no weight argument, so a second weight has to
arrive as a second bundled cut and a change to the spec rather than by someone
passing `.medium` at a call site.

Three traps, all of which have cost a build here:

- **The availability probe needs the exact typographic family name.**
  `UIFont.fontNames(forFamilyName:)` returns empty for `"DMSans"` and for
  `"DM Sans 9pt"` — the family is `"DM Sans"`. Get it wrong and every screen
  silently renders the system fallback with no error anywhere. This cost a
  build here; the test now catches it.
- **The face name is not the family name.** The family is `DM Sans`; the face
  passed to `.custom` is `DMSans-9pt`.
- **`OFL.txt` files collide.** Resources flatten into the bundle root, so two
  licences cannot both keep the name. They ship as `Newsreader-OFL.txt` and
  `DMSans-OFL.txt`.

`WEWidgets-Info.plist` deliberately does **not** list them. Nothing in
`WEWidgets/` or `WEShared/` references `FieldType` or `FieldPalette` — the
ambient widget draws its own type. Add them there if that changes.

To verify registration rather than assuming it:

```swift
UIFont.fontNames(forFamilyName: "Newsreader 36pt")
UIFont.fontNames(forFamilyName: "DM Sans")
```

## Tracking is in points, not em

§3 specifies DM Sans tracking absolutely — "1.8–2.4px" — where V1 specified
everything in em. `FieldTracking` carries both: `em(_:at:)` for Newsreader's
one tracked role, and `px(_:)` for DM Sans.

Deliberately not converted. At this size the two notations disagree by enough
to matter — +2.2 at 9.5pt is 0.232em, which nobody would have written — and
copying the spec's own units is what makes a hand edit visible in review.

## Licensing

Both are OFL 1.1. Bundling and redistribution inside an app binary is
permitted; the licence text should ship in the app's acknowledgements.

## Dynamic Type

`FieldType` uses `.custom(_:size:relativeTo:)`, anchoring each absolute point
size to the nearest text style. Sizes stay authored as absolute points, because
the ramp is a composition and "body plus two" is not a design decision anyone
made — but the whole thing moves together with the reader's setting.

Display sizes anchor high on purpose: they are already clamped for
accessibility sizes by `WEDisplayScale`, so the two systems meet rather than
fight — the ramp scales the type, and the clamp keeps one thought from becoming
a single word per line.

Accessibility is also served by the alpha ramp (every step is measured against
every ground in `WECanvasTests`), by VoiceOver labels on every composed
element, and by honouring Reduce Motion and Reduce Transparency throughout.
