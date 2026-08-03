# Running on an iPad

## Open the app project, not the package

```bash
open App/PaintCoach.xcodeproj
```

Select your iPad and press ⌘R. Signing is already configured.

**Do not open `Package.swift` or this folder directly in Xcode to run the app.**
Opening the package gives you library schemes (`PaintCoachCore`,
`PaintCoachMetal`, `PaintCoachUI`) which declare no platform of their own. Xcode
then falls back to a bogus DriverKit target and you get a confusing cascade:

```
invalid version number in '-target air64-apple-driverkit19.0'
Unable to resolve module dependency: 'Swift'
Unable to resolve module dependency: 'Foundation'
```

Those module errors are downstream noise. The real fault is the DriverKit
triple — DriverKit ships no Swift standard library, so every import fails after
it. Nothing is wrong with the code; it is the wrong scheme for an app.

The package is still the right thing to open for working on Core:

```bash
swift test                # 200 unit tests
swift run PaintCoachApp   # 26 on-device pixel checks
```

The rest of this document explains how the project was assembled, and what to
look for once it runs.


The package builds for iOS but SwiftPM cannot produce an app bundle, so you need
a thin Xcode app target that depends on it. This takes about two minutes.

## 1. Create the app target

In Xcode: **File → New → Project → iOS → App**

| Field | Value |
|---|---|
| Product Name | `PaintCoach` |
| Interface | SwiftUI |
| Language | Swift |
| Location | anywhere *outside* this folder |

## 2. Add this package

**File → Add Package Dependencies… → Add Local…**, then select this directory
(`Painting_app_2`).

When asked which products to add to the app target, tick **PaintCoachUI**. It
pulls in `PaintCoachCore` and `PaintCoachMetal` automatically.

## 3. Replace the app's entry point

Open the generated `PaintCoachApp.swift` and replace its contents:

```swift
import SwiftUI
import PaintCoachCore
import PaintCoachUI

@main
struct PaintCoachApp: App {
    var body: some Scene {
        WindowGroup {
            // Smaller than screen-size while testing: a 2732x2048 canvas needs
            // ~22 MB per layer cache, which is fine on device but slower to
            // iterate on.
            PaintView(document: Document(canvasSize: CanvasSize(width: 1536, height: 1152)))
        }
    }
}
```

Delete `ContentView.swift` — it is unused.

## 4. Run on the iPad

Select your iPad as the destination and build. A simulator works for touch, but
**pressure and tilt need a real Pencil** — the simulator reports neither.

If code signing complains: select the project → target → **Signing &
Capabilities** → set **Team** to your Apple ID.

## What to expect

A dark screen with a floating toolbar: brush picker, five colour swatches, size
and opacity sliders, undo/redo, and a layers button.

Drawing should work with finger or Pencil. With a Pencil, pressure drives stroke
width on Studio Pen, and opacity plus width on Soft Pencil.

## What to look for first

This layer has never run, so these are the things most likely to be wrong:

1. **Marks offset from the Pencil tip.** The view-to-canvas transform in
   `canvasPoint(from:)` assumes an aspect-fit canvas centred in the view. If
   marks appear shifted or scaled, that mapping is wrong.
2. **Nothing appears at all.** Probably the drawable format or the
   `isPaused`/`setNeedsDisplay` draw loop. The renderer itself is verified, so
   suspect the plumbing rather than the shaders.
3. **Pressure doing nothing.** `touch.force / touch.maximumPossibleForce` should
   vary with a Pencil. If width is constant, that normalisation is wrong or the
   touch is not being seen as `.pencil`.
4. **Laggy or chunky strokes.** Coalesced and predicted touches are wired up but
   never measured; `subdivisions: 8` and the pressure curve exponents are
   guesses and will likely need tuning.
5. **Stale marks after undo.** Undo repaints the whole active layer. If a mark
   lingers, the invalidation is not reaching the right layer.

## Verifying the layers underneath

Everything below UIKit is already proven, so if something misbehaves, confirm the
foundation first:

```bash
swift test          # 200 unit tests
swift run PaintCoachApp   # 26 on-device pixel checks
```

If both pass, the bug is in `PaintCoachUI` — not in the renderer, brush engine,
or document model.
