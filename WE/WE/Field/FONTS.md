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

## Adding them

1. Download from Google Fonts and take the static instances, not the variable
   files. SwiftUI resolves named faces more predictably.

   ```
   Newsreader-Light.ttf
   Newsreader-LightItalic.ttf
   Newsreader-Regular.ttf
   Newsreader-Italic.ttf
   IBMPlexMono-Regular.ttf
   IBMPlexMono-Medium.ttf
   ```

2. Drop them into `WE/WE/Field/Fonts/`. The target uses a file system
   synchronized group, so they are picked up without editing the project file.

3. Add to `WE/Config/WE-Info.plist`:

   ```xml
   <key>UIAppFonts</key>
   <array>
     <string>Newsreader-Light.ttf</string>
     <string>Newsreader-LightItalic.ttf</string>
     <string>Newsreader-Regular.ttf</string>
     <string>Newsreader-Italic.ttf</string>
     <string>IBMPlexMono-Regular.ttf</string>
     <string>IBMPlexMono-Medium.ttf</string>
   </array>
   ```

4. Repeat step 3 in `WE/Config/WEWidgets-Info.plist`. The ambient widget draws
   the same type and will silently fall back otherwise — which is the failure
   mode most likely to ship unnoticed, because the widget is not on screen
   during development.

5. Verify the PostScript names match what `FieldType` asks for. They usually
   do, but Newsreader's italics have been inconsistent across releases:

   ```swift
   UIFont.fontNames(forFamilyName: "Newsreader")
   ```

   If a name differs, correct the string in `FieldType.serif(_:_:italic:)`
   rather than renaming the file.

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
