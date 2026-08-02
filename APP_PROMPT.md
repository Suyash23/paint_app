# Build Prompt — "PaintCoach" (working title)

## Role
You are building a native **iPadOS app in Swift / SwiftUI + Metal** that is a faithful, minimal
clone of Procreate's painting UI, used as the substrate for an **interactive drawing tutorial**.
The first lesson teaches a complete beginner to draw a simple **house outline** (square + trapezoid roof)
and fill it with color.

Ground truth for all UI, naming, gestures, and behavior is the Procreate Beginners Series:
- `ProcreateTools-BeginnersSeries.pdf`
- `part1-the-fundamentals.pdf`
- `part3-editing-tools.pdf`

Where these documents specify a gesture, icon position, or term (e.g. "ColorDrop", "QuickShape",
"Active Color", "Transformation Node"), **match it exactly**. Do not invent alternative UX.

---

## Platform & constraints
- iPadOS 17+, Swift 5.9+, SwiftUI shell + Metal rendering layer.
- Apple Pencil first (pressure + tilt), single-finger touch as fallback.
- Portrait and landscape.
- No third-party dependencies.
- Offline; no accounts, no networking.

---

## Architecture requirements

Keep a hard boundary between **pure, unit-testable core** and **device-risk render/app glue**.

```
Core/          pure Swift, no UIKit/Metal — 100% unit tested
  Geometry/    stroke sampling, QuickShape recognition, snapping, transform math
  Document/    layer model, stroke model, undo stack, command log
  Tutorial/    lesson script model, step state machine, validators
Render/        Metal — brush stamping, layer compositing, flood fill
App/           SwiftUI views, gesture recognizers, HUD, tutorial overlay
```

Rules:
1. Every geometry / shape-recognition / transform / tutorial-validation decision lives in `Core`
   and is provable in a unit test **before** any Metal or SwiftUI code is written for it.
2. `Core` never imports UIKit, SwiftUI, or Metal.
3. Rendering is a pure function of document state: `render(document) -> texture`. No hidden state.
4. Undo is a command log in `Core`, not a snapshot of pixels.

### Delivery discipline
- Small, incremental commits. One capability per commit.
- **Tested core code and unverified app-layer code must be in separate commits.**
- Never commit app-layer / renderer code without explicit go-ahead. State plainly, per increment,
  what is proven by tests versus what is unverified on-device.

---

## PHASE 1 — Procreate-parity canvas

Goal: a user can freehand-draw a house outline and fill it, using a UI that looks and behaves
like Procreate's.

### 1.0 Canvas & chrome
Reproduce the Procreate layout (`part1`, p.4):
- **Top-left:** Actions (wrench), Adjustments, Selection, **Transform (arrow)**.
- **Top-right:** Paint (brush), Smudge, Erase, **Layers** (two squares), **Active Color** (filled circle).
- **Left sidebar:** Brush **Size** slider (top), Brush **Opacity** slider (bottom), Undo / Redo buttons.
- Canvas: "Screen Size" preset, white background layer that cannot be painted on.

### 1.1 Brush — "medium hard" round brush
- Brush Library sheet: sets on the left, brushes on the right (`part1`, p.5).
- Ship one set, **Painting**, with one brush, **Round Brush** (`part3`, p.4) — a hard-edged
  round stamp with slight pressure-driven size and opacity response.
- Default Size ≈ 7%, Opacity 100%. Size % must be visible in the slider preview.
- Stroke pipeline: sample Pencil input → resample to even spacing → stamp along path in Metal.
  Spacing/resampling math is pure and unit tested.

### 1.2 Color — black
- Tap Active Color → Color Panel with hue ring + saturation/brightness disc (`part1`, p.10).
- For Phase 1: default palette contains **black** (plus a placeholder swatch row; a full palette
  will be supplied later — make the palette data-driven from JSON now).
- Selected color updates the Active Color swatch in the top-right.

### 1.3 QuickShape — draw a square that snaps perfect
Match Procreate's QuickShape (`part3`, p.7):
- User draws a rough four-sided closed shape and **holds the Pencil down at the end of the stroke**.
- On hold, the stroke snaps to a clean quadrilateral and an **"Edit Shape"** chip appears.
- Tapping it offers `Rectangle` / `Square` — snapping to a true square (equal sides, axis-aligned,
  right angles) is the tutorial's target.
- Recognition rules (pure, unit tested):
  - corner detection from curvature maxima on the resampled polyline,
  - angle + side-length tolerance thresholds,
  - decision: quad → rectangle → square, with explicit tolerance constants.
- While the shape chip is live, dragging a corner adjusts it; any other action commits it.

### 1.4 Trapezoid roof
- Same QuickShape flow recognizes a 4-point shape with one pair of parallel sides → **Trapezoid**.
- It should snap symmetric (isosceles) by default, and align its base to the top edge of the
  existing square when drawn within a snap tolerance of it.
- Result: square + trapezoid = house outline.

### 1.5 Transform
Implement Transform per `part3`, pp. 9–11:
- Enter with the top-left **arrow icon**.
- Modes: **Freeform**, **Uniform**, **Distort**, **Warp** (Phase 1 may ship Freeform + Uniform +
  Distort; Warp may stub with a clear TODO).
- **Bounding box** with marching-dashes border.
- Blue **transformation nodes** at corners and midpoints; green **rotation node** at top.
- Drag anywhere to move; pinch inside to scale.
- **Snapping** toggle → vertical/horizontal guide lines, snap to canvas center and to other layers.
- Tap the blue arrow again to **commit**. Two-finger tap undoes.
- All transform math (affine + perspective/distort homography) is pure and unit tested.

### 1.6 ColorDrop fill
Per `part3`, pp. 17–18:
- Drag the **Active Color circle from the top-right** onto the canvas and release inside a
  closed region → flood fill that region on the active layer.
- After release, keep the finger down and drag left/right to adjust **ColorDrop Threshold**,
  with a live HUD bar showing the threshold value.
- Fill is scanline/flood on the layer's pixel buffer with antialiased edge feathering.
- Fill must respect the closed square and the closed trapezoid as separate regions.

### 1.7 Layers (minimum viable)
- Layers Panel: list, `+` to add, tap to select (blue highlight), visibility checkbox,
  swipe-left for Lock / Duplicate / Delete, drag to reorder (`part1`, p.23).
- Background Color layer pinned at the bottom, non-paintable.

### 1.8 Gestures (`part1`, p.13)
- 1 finger / Pencil: paint.
- 2-finger tap: undo. 2-finger hold: rapid undo.
- 3-finger tap: redo. 3-finger hold: rapid redo.
- 2-finger drag: pan / zoom / rotate canvas. Quick pinch: fit to screen.
- 3-finger scrub: clear layer.
- Tap-and-hold with a finger: **Eyedropper** with magnifier loupe.

### Phase 1 done means
A user can, unassisted: pick the Round Brush, pick black, QuickShape a perfect square,
QuickShape a trapezoid roof on top of it, nudge it with Transform, and ColorDrop fill both shapes.

---

## PHASE 2 — Guided, micro-managed tutorial

Goal: turn Phase 1 into a hand-held lesson: *"Draw a house."*

### 2.1 Lesson model (pure Core, unit tested)
A lesson is declarative data — **JSON**, not code — so new lessons need no recompile:

```json
{
  "id": "house-01",
  "title": "Draw a House",
  "steps": [
    {
      "id": "pick-brush",
      "instruction": "Tap the brush icon to open the Brush Library.",
      "spotlight": { "target": "toolbar.paint" },
      "gate": { "type": "uiState", "path": "brushLibrary.isOpen", "equals": true }
    },
    {
      "id": "draw-square",
      "instruction": "Draw a square. Hold at the end to snap it perfect.",
      "ghost": { "shape": "square", "rect": [0.30, 0.45, 0.40, 0.35] },
      "gate": {
        "type": "shapeMatch",
        "shape": "square",
        "tolerance": { "position": 0.06, "size": 0.10, "rotation": 5 }
      },
      "hint": "Keep your Pencil down when you finish the last side."
    }
  ]
}
```

Each step carries: `instruction`, optional `spotlight`, optional `ghost` guide,
a `gate` (completion condition), a `hint` after N seconds idle, and an optional `retryMessage`.

### 2.2 Step gates — validators
Implement as pure functions over document / UI state, each unit tested against
recorded fixture strokes:
- `uiState` — a named UI flag is true (panel open, tool selected).
- `toolSelected` — brush id / color / size within range.
- `shapeMatch` — a committed shape of type X exists within positional, scale and rotation tolerance.
- `regionFilled` — region containing point P has color C, coverage ≥ threshold.
- `transformApplied` — layer transform differs from identity by ≥ delta.

### 2.3 Coaching overlay (App layer)
- **Spotlight:** dim scrim with a cut-out hole over the target control, pulsing ring, arrow, caption.
  Targets are resolved by a stable `TutorialAnchor` id registered by each control — never by
  hardcoded coordinates.
- **Ghost guide:** dashed translucent outline of the target shape drawn on the canvas, in
  normalized canvas coordinates so it survives zoom/rotate. Fades out on success.
- **Live feedback:** as the user draws, the ghost tints green as the match improves.
- **Gating:** non-target controls are dimmed and optionally non-interactive in "strict" mode;
  "free" mode allows exploration but keeps the prompt visible.
- **Progress:** step chip `3 / 11`, back / skip, and a "Show me" button that animates a demo
  of the required gesture.
- **Success:** brief check animation + haptic, then auto-advance.

### 2.4 The house lesson — step list
1. Create a Screen Size canvas.
2. Tap Paint → open Brush Library. *(spotlight: brush icon)*
3. Select **Painting → Round Brush**. *(spotlight: set, then brush row)*
4. Set Brush Size to ~7% with the sidebar slider. *(spotlight: size slider, target band shown)*
5. Tap Active Color → pick **black**. *(spotlight: top-right circle, then swatch)*
6. Draw the **square** body — ghost outline shown, QuickShape hold coached explicitly.
7. Add a **new layer** for the roof. *(spotlight: Layers → `+`)*
8. Draw the **trapezoid** roof on top of the square — ghost outline, edge-snap to the square's top.
9. Enter **Transform**, use Uniform + Snapping to center/adjust the roof, then commit.
   *(spotlight: arrow icon → Uniform → Snapping toggle → commit)*
10. **ColorDrop** the wall: drag the Active Color circle onto the square. *(animated drag hint)*
11. ColorDrop the roof in a second color. Celebrate; offer "Draw it again on your own."

### 2.5 Authoring & QA
- A hidden **Lesson Inspector** debug screen: current step, gate state, live validator output,
  and a "force pass" button.
- Fixture-driven tests: recorded stroke sequences replayed through `Core` must drive the
  lesson state machine start → finish with zero UI.

---

## Non-goals (explicitly out of scope for now)
Brush Studio / custom brushes, Liquify, Adjustments, Clipping Masks, Animation Assist,
Selections beyond what fill needs, cloud sync, export beyond PNG.

---

## Build order (each = its own commit, core before glue)
1. `Core/Document` — layer + stroke model, command-log undo. **Tests.**
2. `Core/Geometry` — resampling, corner detection, QuickShape square/rect/trapezoid. **Tests.**
3. `Core/Geometry` — transform math (affine, distort homography), snapping guides. **Tests.**
4. `Core/Tutorial` — lesson JSON schema, step machine, all validators. **Tests.**
5. `Render` — Metal brush stamping + layer compositing. *(unverified until on-device)*
6. `Render` — flood fill with threshold. *(unverified)*
7. `App` — Procreate-parity chrome and panels. *(unverified)*
8. `App` — gesture layer. *(unverified)*
9. `App` — Transform UI. *(unverified)*
10. `App` — tutorial overlay: spotlight, ghost, progress. *(unverified)*
11. Wire the house lesson JSON; end-to-end pass.

At each step, state clearly what is proven by tests and what is unverified.
Stop and ask before committing anything in layers 5–11.
