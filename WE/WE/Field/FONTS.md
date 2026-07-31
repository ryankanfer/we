# Fonts

The handoff specifies two families and no others:

- **Newsreader** — 300, 400, italic 400. All content.
- **IBM Plex Mono** — 400, 500. Labels, dates, counts, buttons. Always
  uppercase, always letter-spaced.

Both are Google Fonts and both are **bundled with the app, not loaded at
runtime**. The design uses almost no icons — coloured dots, hairlines, and
typography carry the meaning — so the faces are load-bearing in a way they
usually are not.

## What is already wired

`FieldType` in `FieldTokens.swift` resolves every role to a concrete face and
size. It checks availability once at launch:

```swift
private static let hasSerif: Bool = isAvailable(serifFamily)
```

Until the files are added it falls back to the system serif and the system
monospaced face, so every screen still lays out and every size, tracking, and
line height is already correct. The fallback is visibly wrong — the system
serif is heavier at 300 and its italic is not Newsreader's — but nothing
breaks, and no layout has to change when the real faces land.

## What actually shipped

Ten faces in `WE/WE/Field/FONTS/`, listed under `UIAppFonts` in
`WE/Config/WE-Info.plist`. The target uses a file system synchronized group, so
the files needed no project edit.

```
Newsreader_14pt-Light.ttf        Newsreader_36pt-Light.ttf
Newsreader_14pt-LightItalic.ttf  Newsreader_36pt-LightItalic.ttf
Newsreader_14pt-Regular.ttf      Newsreader_36pt-Regular.ttf
Newsreader_14pt-Italic.ttf       Newsreader_36pt-Italic.ttf
IBMPlexMono-Regular.ttf          IBMPlexMono-Medium.ttf
```

**There is no plain "Newsreader" family.** Google ships it as optical-size cuts
— 9, 14, 24, 36, 60pt — each its own family, and the variable file registers as
`Newsreader 16pt`. Nothing is named `Newsreader-Light`. So `FieldType.serif`
picks the cut by size:

```swift
let opsz = size >= 20 ? "Newsreader36pt" : "Newsreader14pt"
```

which is what `font-optical-sizing: auto` did in the browser the handoff was
drawn in. The 42pt hero and 44pt horizon get the display cut and stay thin at
weight 300; labels get the text cut.

Two traps, both of which cost a build here:

- **The availability probe needs the exact family name.**
  `UIFont.fontNames(forFamilyName:)` returns empty for `"IBMPlexMono"` — the
  real family is `"IBM Plex Mono"`, with spaces. Get it wrong and every screen
  silently renders the system fallback with no error anywhere.
- **Two `OFL.txt` files collide.** Resources flatten into the bundle root, so
  Newsreader's and Plex's licences cannot both keep the name. They ship as
  `Newsreader-OFL.txt` and `IBMPlexMono-OFL.txt`.

`WEWidgets-Info.plist` deliberately does **not** list them. Nothing in
`WEWidgets/` or `WEShared/` references `FieldType` or `FieldPalette` — the
ambient widget draws its own type. Add them there if that changes.

To verify registration rather than assuming it:

```swift
UIFont.fontNames(forFamilyName: "Newsreader 36pt")
```

## Licensing

Both are OFL 1.1. Bundling and redistribution inside an app binary is
permitted; the licence text should ship in the app's acknowledgements.

## Dynamic Type

`FieldType` uses `.custom(_:fixedSize:)` deliberately. The design is drawn
against a fixed 393 × 852pt frame and its hierarchy depends on exact ratios
between 44pt, 42pt, 38pt, and 25pt — scaling them independently collapses the
distinction between a horizon and a headline.

Accessibility is served instead by the alpha ramp (every step clears contrast
on `#16211D`), by VoiceOver labels on every composed element, and by honouring
Reduce Motion and Reduce Transparency throughout. If Dynamic Type support is
added later, it should scale the whole canvas rather than individual roles —
`.custom(_:size:relativeTo:)` per role will break the layout.
