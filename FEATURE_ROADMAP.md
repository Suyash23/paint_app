# Feature Roadmap — Derived from the Procreate PDF Handbooks

**Purpose:** a feature-level backlog extracted from the three PDF handbooks in the
repo root. A fixing agent can work from this **without re-reading the PDFs**.

**Companion document:** `UI_GAPS.md` covers *fidelity* defects — things that exist
but look or behave wrong. This document covers *absent features* — capability the
handbooks teach that the app cannot do at all. Where they overlap, this file
carries the feature framing and cross-references the gap ID.

## Sources

| File | Pages | Covers |
|---|---|---|
| `ProcreateTools-BeginnersSeries.pdf` | 16 | Paint/Smudge/Erase, layers, Color Panel, Palettes, Eyedropper |
| `part1-the-fundamentals.pdf` | 32 | Gallery, brush sliders, Color Panel, gestures, layers, Share |
| `part3-editing-tools.pdf` | 45 | Transform, layer organization, Selections, Clipping Masks, Adjustments |

Illustrations cited below live in `Screenshots/procreate_handbook/` and were
already in the repo.

## Honest scope note

**This is static analysis for everything except F6.** The app has never been run —
`PaintView.swift`, `MetalCanvasView.swift` and the Harness all carry `UNVERIFIED`
markers. Every "missing" claim below means *absent from the source*, not *observed
broken*.

**Exception — F6 (Clipping Masks) is partly done and genuinely verified.** Its
Core layer exists in uncommitted working-tree changes with 13 passing tests; the
full suite runs 213/213 green. See F6 for the exact split between landed and
remaining work.

**Test invocation note:** `swift test` fails out of the box here — `xcode-select`
points at `/Library/Developer/CommandLineTools`, which lacks `XCTest`, and
SwiftPM's sandbox is also blocked. Use:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox`

Current codebase is **3,745 lines** across 26 Swift files. The brush/stroke/render
core is genuinely substantial. Nearly everything below is *additive* — very little
needs rework.

---

# Tier 0 — Blocks the handbooks' very first lesson

### F1. Smudge and Erase cannot be represented in the document model
- **Handbook:** ProcreateTools p.5 ("Any Procreate brush can be used not only for
  painting, but also for smudging and erasing"); Part 1 Ch.1 p.8.
- **UI exists:** `PCTool` enum has `.brush, .smudge, .eraser`
  (`ProcreateTheme.swift:91-93`), and the top bar wires all three
  (`PaintView.swift:200-209`).
- **The gap:** `Stroke` (`Stroke.swift:33-40`) stores only
  `brushID, color, size, opacity, points` — **there is no tool or blend field.**
  A smudge stroke and a paint stroke are indistinguishable once committed.
  `MetalCanvasView` never reads `model.tool` at all (zero matches).
- **Also:** `MetalRenderBackend` already has an `erasePipeline`
  (`MetalRenderBackend.swift:31-32, 90`) — the Metal side is half-ready, but
  nothing can select it because the data model can't express the choice.
- **Work:** add a `tool`/`blend` field to `Stroke` (Core, pure, testable), thread
  it through `StrokeSession` → `FrameCoordinator` → backend pipeline selection.
- **Why Tier 0:** two of the three headline painting tools are inert. Highest
  priority in this document.

### F2. No Color Panel — blocks ~15 handbook steps
- Cross-ref: `UI_GAPS.md` finding #6.
- **Handbook:** Part 1 Ch.2 p.10; ProcreateTools p.12-16; Part 3 uses it on
  pp.3, 5, 17, 22, 32, 33, 37, 40, 43.
- **Required sub-features:**
  - Hue ring + saturation/brightness inner disc, both with draggable reticles
  - **Palettes** tab; `...` menu per palette → **Set as default**; default palette
    renders below the disc (Part 3 p.5)
  - **Value** mode with numeric H/S/B sliders (Part 3 p.3 drives Brightness to 25%)
  - Double-tap inner disc corners → pure white / full black (Part 3 pp.32, 40)
  - Panel is **draggable** anywhere on canvas (ProcreateTools p.16)
  - `Done` commits
- **Current:** `panel = .color` is settable (`PaintView.swift:214`) but
  `panelLayer` has no `.color` case — falls to `default: EmptyView()`
  (`PaintView.swift:300-301`).

### F3. No multi-finger gestures
- Cross-ref: `UI_GAPS.md` finding #8. **Part 1 devotes an entire chapter (Ch.3)
  to this.**
- **Handbook (Part 1 pp.13-14), exact spec:**
  | Gesture | Action |
  |---|---|
  | 2-finger tap | Undo |
  | 2-finger tap-and-hold | Undo continuously |
  | 3-finger tap | Redo |
  | 3-finger tap-and-hold | Redo continuously |
  | 2-finger drag | Pan + zoom + rotate |
  | Quick pinch | Fit canvas to screen |
  | 3-finger scrub | Clear layer |
- **Current:** `MetalCanvasView` tracks a single `activeTouch`. Undo/redo exist
  only as sidebar buttons.
- **Note:** Part 3 repeatedly says "tap with two fingers to undo" as the *primary*
  escape hatch for selections and transforms (pp.10, 23). Without this, mistakes
  in those modes are unrecoverable.

---

# Tier 1 — Core models that unblock whole chapters

### F4. Selection subsystem (Part 3 Ch.4, pp.21-28)
- Cross-ref: `UI_GAPS.md` findings #1, #13.
- **Four modes:** Automatic, Freehand, Rectangle, Ellipse.
- **Required behaviours from the handbook:**
  - **Selection mask rendering:** faint diagonal lines mark the *excluded* area
    (p.22) — this is the visual contract users rely on
  - Marching-dashed outline for Freehand/Rectangle/Ellipse (p.22)
  - Automatic mode inverts colors of the selected area (p.23)
  - **Selection Threshold:** drag left/right to grow/shrink, works like ColorDrop
    threshold (p.22)
  - Freehand supports **tap-ahead** for straight-line segments (p.22)
  - **Selections persist across layer switches** (p.24) — select on the planet
    layer, switch to the rings layer, and the mask still constrains the eraser.
    This is load-bearing for the tutorial.
  - Ellipse + one-finger tap → perfect circle (p.43)
- **Current:** no selection state, no mask buffer, no `DocumentCommand` case.

### F5. Transform subsystem (Part 3 Ch.2, pp.8-13)
- Cross-ref: `UI_GAPS.md` findings #5, #14.
- **Reference image:** `Screenshots/procreate_handbook/transform/01_interface_handles_rotation.jpg`
  — shows bounding box, blue corner/midpoint nodes, green rotation node with a
  live `Rotation 20°` readout, and the full bottom bar
  (Freeform/Uniform/Distort/Warp + Snapping, Flip Horizontal, Flip Vertical,
  Rotate 45°, Fit to Canvas, Bilinear, Reset).
- **Four modes:** Freeform (squash/stretch), Uniform (locked ratio), Distort
  (perspective), Warp (mesh push/fold — see `transform/04_warp_mesh.jpg`).
- **Gestures (p.10):** drag nodes to reshape; green node to rotate; drag inside
  *or outside* the box to move; pinch inside to scale.
- **Snapping** toggle showing vertical/horizontal guide lines (p.11) — the
  tutorial depends on these to center objects.
- **Distort shortcut:** tap-and-hold a blue node while in Freeform (p.19).
- **Commit:** tap the blue Transform arrow to apply (p.20).
- **Current:** no transform math anywhere in Core.

### F6. Clipping Masks (Part 3 Ch.5, pp.29-33)
- Cross-ref: `UI_GAPS.md` finding #2.
- **STATUS: Core layer landed and tested — UI still absent.**
  Uncommitted working-tree changes add:
  - `Layer.isClippingMask` (`Layer.swift:22`)
  - `DocumentCommand.setLayerClippingMask` with undo inverse and a
    `layerNotClippable` guard rejecting non-`.paint` layers
    (`DocumentCommand.swift:18, 78-86`)
  - `Document.clippingBase(for:)` resolving the nearest non-mask layer below, so
    stacked masks share one base (`Document.swift:65-77`)
  - `Tests/PaintCoachCoreTests/ClippingMaskTests.swift` — **13 tests, all
    passing** (verified; full suite 213/213 green)
- **Semantics:** the paint on the layer *below* determines visibility of the
  clipping-mask layer — "like a window."
- **Still to do (all UI/render):** enable via Layer Options; the **arrow
  indicator** next to a masked layer pointing at its base (p.31); actually
  *honouring* the mask in the renderer; Blend Modes on mask layers; pinch-merge a
  mask into its base (pp.32, 33).

### F7. ColorDrop fill + threshold
- Cross-ref: `UI_GAPS.md` finding #3.
- **Handbook:** Part 3 pp.17, 18, 26, 33, 43 — used constantly.
- **Required:** drag the Active Color swatch onto the canvas to flood-fill the
  enclosed region on the active layer; a drop **threshold** controlling spread;
  fills must respect an active selection (p.43 drops into ellipse selections).
- **Current:** no fill command in `DocumentCommand`.

### F8. QuickShape
- Cross-ref: `UI_GAPS.md` finding #4.
- **Handbook:** Part 3 pp.6, 37 — used to draw the base circle and the lines.
- **Required:** draw and pause → snap to a perfect primitive (circle/line/rect).
- **Current:** no shape detection in `StrokeBuilder`/`StrokePath`.

---

# Tier 2 — Layer organization (Core is largely ready)

**Reference images:**
`layers-organize/01_select_layers_primary_secondary.png` — primary layer bright
blue, secondaries dimmer blue, `Group` button top-right.
`layers-organize/08_lock_duplicate_delete_swipe.png` — swipe-left revealing
`Lock` / `Duplicate` / `Delete`, plus the per-row `N` badge and a row showing `M`
(a non-Normal blend mode).

### F9. Swipe-left row actions — Lock / Duplicate / Delete
- Cross-ref: `UI_GAPS.md` finding #9. **`setLayerLocked` and `deleteLayer` already
  exist in `DocumentCommand`.** Duplicate needs adding.
- **Handbook:** ProcreateTools p.11; Part 1 p.23; Part 3 pp.12, 16, 36.
- **Applies to layer *groups* too** (Part 3 p.16).

### F10. Multi-select and Grouping
- **Handbook:** Part 3 pp.15-16. Tap primary layer, then **swipe right** on others
  to add as secondary, then tap **Group**.
- **Group Options:** Rename, Flatten (p.26), Duplicate/Delete via swipe (p.16),
  collapse/expand arrow (pp.26, 28).
- **Current:** no group concept in `Layer`. This is the largest Tier-2 model change.

### F11. Blend Modes + Opacity via the `N` badge
- Cross-ref: `UI_GAPS.md` finding #10. **`setLayerOpacity` already exists.**
- **Handbook:** Part 3 pp.26, 39, 40. Badge shows the current mode's initial —
  `N` for Normal, `M` for Multiply (visible in reference image 08).
- **Required:** tap `N` → panel with Opacity slider + blend mode list. Part 3 p.39
  specifically needs **Overlay**.
- **Current:** `ProcreatePanels.swift:168-173` renders static `Text("N")`. No
  blend mode field on `Layer` at all.

### F12. Tap-and-hold to reorder
- Cross-ref: `UI_GAPS.md` finding #9. **`moveLayer` already exists in Core.**
- **Handbook:** Part 1 p.23; Part 3 pp.28, 39.

### F13. Pinch-to-merge / Merge Down
- **Handbook:** Part 3 pp.17-18 (Merge Down via Layer Options), p.32 (pinch two
  layers together), p.33.
- **Current:** no merge command. Needs stroke-list concatenation or rasterization.

### F14. Rename via Layer Options
- **`renameLayer` already exists in Core** — needs only a UI affordance plus
  keyboard entry (Part 3 p.16).

---

# Tier 3 — Adjustments (entirely absent)

**Reference image:** `adjustments/04_menu_list.jpg` — the authoritative menu,
with the top four color adjustments boxed off from the 11 filters.

### F15. Adjustments engine
- **Handbook:** Part 3 Ch.6, pp.34-38.
- **Two semantics that matter:** adjustments affect **only the active layer**, and
  can be applied either to the whole layer **or painted into regions with the
  Apple Pencil** (p.35).
- **Exact menu, in order:**
  - *Color adjustments:* Hue/Saturation/Brightness · Color Balance · Curves · Gradient Map
  - *Filters:* Gaussian Blur · Motion Blur · Perspective Blur · Noise · Sharpen ·
    Bloom · Glitch · Halftone · Chromatic Aberration · Liquify · Clone
- **Interaction model:** drag across canvas to set intensity, with a live
  percentage readout at top (p.36 targets ~7% Gaussian Blur).
- **Liquify** (p.38) is its own sub-system: six warp modes (Twirl Right used in
  the tutorial) with Size / Pressure / Momentum / Distortion sliders and a
  **Reset**.
- **Current:** `PCAdjustmentsPanel` renders menu text only — no implementation
  behind any entry.

---

# Tier 4 — App shell

### F16. Gallery
- **Handbook:** Part 1 Ch.1 pp.2-3 — the app *opens* into the Gallery; `+` creates
  artwork; "Screen Size" preset at top of the list.
- **Current:** `PaintView` has a `Gallery` text label
  (`PaintView.swift:178`, styled by `PC.galleryFont`) that goes nowhere. No
  gallery view, no multi-document model, no persistence.
- **Note:** `Document` is already `Codable`, so serialization groundwork exists.

### F17. Share / Export
- **Handbook:** Part 1 Ch.7 pp.31-32; Part 3 p.45 — Actions → Share → pick format
  (`.PNG` called out) → system share sheet.
- **Current:** Actions panel Share tab renders no content
  (`UI_GAPS.md` finding #11). No export path exists.
- **Partial groundwork:** `OffscreenRenderer` exists and could back a flattened
  export.

### F18. Brush size / opacity sidebar must drive the brush
- **Handbook:** Part 1 pp.6-7 (two sliders control size and opacity); Part 3 p.4
  sets size to 7% and checks opacity is 100%, reading a **live percentage preview
  next to the slider**.
- **Current:** sliders render in `PaintView`, but verify they reach
  `Brush.maxDiameter`/`opacity` at stroke-build time; the percentage preview
  bubble is absent.

### F19. Real brush library content
- **Handbook:** Part 1 p.5 — "over a hundred brushes" across sets named after
  Tasmanian places/flora/fauna. Tutorials require specific brushes: 6B Pencil
  (Sketching), Old Beach (Artistic), Freycinet (Drawing), Chalk (Calligraphy),
  Round Brush (Painting), Medium Nozzle (Spraypaints).
- **Current:** two presets only — `Brush.studioPen`, `Brush.softPencil`
  (`Brush.swift:90-99`). Set filtering is also stubbed
  (`UI_GAPS.md` finding #15).
- **Related:** the `brushes/` reference images document the Brush Studio parameter
  surface (Stroke Path, Rendering, Wet Mix, Color Dynamics, Dual Brush) — a
  brush *editor* is a much larger project and is **out of scope** for parity with
  these three beginner handbooks. Noted only so it isn't mistaken for a gap here.

---

# Suggested sequencing

1. **F1** — smudge/erase in the model. Small, pure, unblocks a third of Part 1.
2. **F3** — gestures. Self-contained in `MetalCanvasView`; makes the app usable.
3. **F2** — Color Panel. Unblocks the most downstream steps.
4. **F9 / F11 / F12 / F14** — layer actions where Core is already done. Cheap wins.
5. **F4 / F5** — selection and transform models (pure Core, testable), then wire
   the existing inert bottom bars.
6. **F6 (UI half) / F7 / F13** — clipping-mask UI and renderer support (Core is
   already landed and tested), ColorDrop, merge.
7. **F15** — adjustments. Start with Gaussian Blur end-to-end as the vertical slice.
8. **F16 / F17** — gallery and export.

Rationale: Tier 0 items are cheap and unblock the most tutorial steps per line of
code; Tier 1 items are expensive but pure Core, so they can be unit-tested with no
device risk before any renderer work.

# Commit guidance

Per project convention: land pure Core model changes (F1, F4, F5, F7, F8) as
tested commits **separate** from unverified app-layer/renderer work (F2, F3, and
all UI wiring), keeping the proven/unproven boundary clean in history. Prefer
small increments. Do not commit app-layer changes without explicit sign-off.

**Immediate note:** the F6 Core work currently sits **uncommitted** in the working
tree alongside these two docs. It is tested and green, so it belongs in its own
Core commit — kept separate from the docs and from any later clipping-mask UI.
