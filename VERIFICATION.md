# Verification status

What is proven, and by what. Kept current so the boundary between tested and
unverified code is never a guess.

## Core — `PaintCoachCore`

165 unit tests, 0 failures. Pure Swift, `Foundation` only — no CoreGraphics,
UIKit, or Metal. Verified by:

```bash
swift test
```

| Area | Tests | Covers |
|---|---|---|
| `DocumentTests` | 6 | initial state, layer invariants, JSON round-trip |
| `DocumentCommandTests` | 22 | undo/redo inverses, command atomicity, layer rules |
| `ResponseCurveTests` | 7 | endpoints, clamping, exponent shaping, monotonicity |
| `StrokePathTests` | 9 | Catmull-Rom passes through inputs, pencil data carried |
| `SeededGeneratorTests` | 8 | determinism, range, distribution |
| `BrushEngineTests` | 21 | spacing, dynamics, jitter stability, degenerate input |
| `RectTests` | 18 | dirty-region algebra, integral growth, clipping |
| `StampGeometryTests` | 16 | stamp bounds, rotation independence, batching |
| `RenderCachePolicyTests` | 31 | invalidation states, frame plans, command effects |
| `FrameCoordinatorTests` | 27 | draw scheduling and cache repair, against a mock |

## Metal backend — `PaintCoachMetal`

**Verified on device: 20/20 checks passed.**

```bash
swift run PaintCoachApp
```

Renders known documents offscreen through the real backend and asserts on
pixels read back from the texture. Exit codes: `0` all passed, `1` some failed,
`2` frame error, `3` no Metal device available.

### Assumptions this retired

Each of these was guesswork when written, and could not be checked by
compilation alone:

- **Clip-space transform** — canvas pixels map to the correct screen position
- **Y flip in `composite_vertex`** — a stroke drawn at y=20 appears at y=20 and
  not at y=108. This was the single most likely thing to be wrong.
- **Scissor rect origin** — Metal's attachment origin agrees with canvas
  coordinates, so incremental repair lands where intended. Confirmed by drawing
  two distant strokes and checking the first survives repair of the second.
- **Premultiplied alpha and blend state** — source factor `.one` with
  `.oneMinusSourceAlpha` destination composites correctly over the background
- **`StampInstanceData` layout** — Swift struct field order and padding match
  the shader's `StampInstance`, so stamps land at the right size and place
- **Erase pipeline** — partial cache clears actually erase, rather than
  compositing transparent over existing pixels and leaving them intact

### What the 20 checks cover

| Group | Checks | Asserts |
|---|---|---|
| Background | 3 | opaque fill, correct colour, covers whole canvas |
| Stroke rendering | 4 | marks appear on path, background survives off-path, no Y flip |
| Stroke geometry | 5 | coverage matches `StampGeometry` bounds, size scales coverage |
| Layer compositing | 3 | upper above lower, hidden not drawn, opacity blends |
| Cache behaviour | 5 | incremental repair preserves distant strokes, live stroke composites, cancel leaves no trace |

## Not yet verified

- **UIKit layer — `PaintCoachUI`.** Written but never run. Builds for iOS
  (`xcodebuild -scheme PaintCoachUI -destination 'generic/platform=iOS'`), which
  proves only that it compiles. `MetalCanvasView`'s touch handling, the
  view-to-canvas coordinate transform, Pencil force/tilt capture, and the
  `MTKView` draw loop are all unexercised. See `IPAD_SETUP.md`.
- **Performance under load** — Option A's cache has never been measured against
  a heavy document. The mock proves zero draw calls while dragging; real frame
  time on device is unmeasured.
- **Brush feel** — `subdivisions: 8` and the pressure-curve exponents were
  chosen by reasoning, not by drawing with a Pencil. Expect both to change.
- **Velocity dynamics** — `StrokePoint.timestamp` is carried and monotonic, but
  nothing consumes it yet.
- **Persistence** — strokes are `Codable`, but no file format or versioning
  exists.

## Environment notes

SwiftPM's sandbox conflicts with some sandboxed shells; tests may need:

```bash
swift test --disable-sandbox --cache-path .build/cache \
  --config-path .build/config --security-path .build/security
```

If `xcode-select` points at CommandLineTools there is no XCTest. Either run
`sudo xcode-select -s /Applications/Xcode.app` or prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

SwiftPM copies `.metal` files into the resource bundle as source rather than
compiling a `metallib`, so `MetalRenderBackend` falls back to compiling the
shader at runtime. An Xcode app target produces a real `metallib` and skips
this, at the cost of a few hundred milliseconds on first launch under SwiftPM.
