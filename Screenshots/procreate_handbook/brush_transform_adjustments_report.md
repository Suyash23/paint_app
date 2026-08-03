# Parity Report — Brushes, Transform, Adjustments

Compared against the Procreate handbook (help.procreate.com/procreate/handbook).
Focus areas you flagged: brushes, Transform, and the Adjustments UI.

Verdict up front:
- **Transform — barely works: confirmed.** No free rotation, no edge handles, only 2 of 4 modes. This is the weakest of the three.
- **Adjustments — barely works: confirmed.** 4 of ~15 adjustments, and the *defining* Procreate interaction (drag-on-canvas + Layer/Pencil mode) is entirely absent.
- **Brushes — better than it feels.** The stamp engine actually handles grain + wet mix; the gap is Brush Studio depth (5 of ~12 categories) and missing rendering/color-dynamics/dual-brush.

Legend: ✅ works · 🟡 partial · 🔴 missing

---

## 1. Transform  🔴 weakest area

Handbook: `transform/transform-interface-gestures`, `-freeform`, `-uniform`,
`-distort`, `-warp`, `snapping`, `transform-interpolate`.
Code: `TransformSession.swift`, `ContentView.swift` `TransformToolbar` (:1576) +
`TransformGizmo` (:1687).

| Procreate feature | Status | Notes |
|---|---|---|
| Freeform mode | ✅ | works |
| Uniform mode | ✅ | works |
| **Distort mode** | 🔴 | enum case exists but marked "reserved" — not implemented |
| **Warp mode** (mesh) | 🔴 | reserved, not implemented |
| **Free rotation (green node)** | 🔴 | **no rotation handle in the gizmo at all** — you can only rotate in fixed 45° steps via the button. This is the #1 reason it feels broken. |
| Corner scale handles | 🟡 | only the 4 corners are drawn; the 4 **edge/midpoint handles** (top/right/bottom/left) are missing from the gizmo even though `dragHandle` supports them |
| Move (drag inside box) | ✅ | works |
| Pinch-to-scale | 🔴 | no pinch gesture on the gizmo |
| Nudge (tap outside box) | 🔴 | not implemented |
| Flip H / Flip V | ✅ | toolbar buttons work |
| Rotate 45° | ✅ | works |
| Reset | ✅ | works |
| Fit to Screen | 🔴 | missing |
| Snapping / magnetics | 🔴 | missing |
| Interpolation | 🟡 | Nearest + Bilinear only; Procreate also has **Bicubic** |
| Scale/rotation readout | 🟡 | model computes `scalePercent`/`rotationDegrees` but the gizmo doesn't display them |

**Highest-impact fix:** add the rotation handle (a green node above the box that
maps drag angle → `transform.rotate(by:)`), then the 4 edge handles. Those two
changes alone move Transform from "toy" to "usable."

---

## 2. Adjustments  🔴 barely works

Handbook: `adjustments/adjustments-interface` + one page per adjustment.
Code: `Adjustments.swift` (core), `ContentView.swift` `AdjustmentsPanel` (:445).

### Structural gaps (why it feels broken)
- **No Layer vs Pencil mode.** Procreate's whole adjustments model is a top-bar
  toggle between applying to the whole layer vs. *painting* the effect with the
  Pencil. Neither exists — every adjustment is whole-layer only.
- **No drag-on-canvas to set intensity.** The signature Procreate gesture (slide
  finger left/right on the canvas to dial the effect) is absent; only panel sliders.
- **No on-canvas Adjustments actions menu** (preview / apply / reset / cancel on tap).
- **Placeholder rows that do nothing** — "Curves", "Sharpen", "Noise" render as
  tappable rows but have no handler (`ContentView.swift:478`).

### Coverage: 4 of ~15
| Procreate adjustment | Status | Notes |
|---|---|---|
| Hue, Saturation, Brightness | ✅ | wired |
| Color Balance | ✅ | wired |
| Curves | 🟡 | **exists in core** (`Adjustments.curves`, :59) but **no UI** — only a dead placeholder row |
| Gradient Map | 🔴 | not in core or UI |
| Gaussian Blur | ✅ | wired |
| Motion Blur | 🔴 | missing |
| Perspective Blur | 🔴 | missing |
| Noise | 🔴 | placeholder row only |
| Sharpen | 🔴 | placeholder row only |
| Bloom | 🔴 | missing |
| Glitch | 🔴 | missing |
| Halftone | 🔴 | missing |
| Chromatic Aberration | 🔴 | missing |
| Liquify | 🔴 | missing (needs mesh warp) |
| Clone | 🔴 | missing |

Note: "Brightness & Contrast" in your panel isn't a distinct Procreate adjustment —
Procreate's color set is HSB / Color Balance / Curves / Gradient Map.

**Highest-impact fixes:** (a) wire up **Curves** — the logic already exists, it just
needs the graph UI; (b) add the **drag-on-canvas intensity gesture**, since that one
interaction is what makes adjustments feel native.

---

## 3. Brushes  🟡 engine solid, Studio shallow

Handbook: `brushes/brush-studio-settings`, `paint-smudge-erase`, `dual-brush`.
Code: `BrushStudioView.swift`, `BrushDefinition.swift`, `BrushStampEngine.swift`,
`BrushShaders.metal`.

**Good news — it's more real than it feels.** The Metal stamp shader genuinely
samples **grain** (tiles noise, modulates alpha, `BrushShaders.metal:72`) and does
**Wet Mix** dilution (`:93`), and the engine does spacing, jitter, streamline, and
taper. So those sliders aren't cosmetic.

### Brush Studio categories: 5–7 of ~12
| Procreate category | Status | Notes |
|---|---|---|
| Shape | 🟡 | has Hardness/Roundness/Angle/Randomize; **missing** Scatter, Count, Count Jitter, Flip X/Y, Pressure/Tilt Roundness |
| Grain | 🟡 | Movement/Scale/Depth; **missing** Zoom, Rotation, Blend Mode, Brightness/Contrast |
| Stroke Path | 🟡 | Spacing/Jitter/FallOff/StreamLine; **missing** Jitter Lateral/Linear, Spacing Jitter |
| Taper | ✅ | present |
| Dynamics | 🟡 | present; Procreate splits Speed + Jitter more finely |
| Apple Pencil | 🟡 | tilt sliders; pressure/tilt **response graphs** not surfaced |
| Properties | ✅ | present |
| **Stabilization** | 🔴 | no tab (StreamLine lives under Stroke Path instead) |
| **Rendering** | 🔴 | no rendering modes (Light Glaze → Intense Blending), Flow, Wet Edges |
| **Wet Mix** (as a tab) | 🔴 | shader does wetness, but no dedicated tab for Dilution/Charge/Attack/Pull/Grade |
| **Color Dynamics** | 🔴 | no hue/sat/brightness jitter — a big reason brushes look flat vs. real Procreate |
| Materials (3D) / About | 🔴 | missing (low priority) |

### Why brushes may "not feel great" despite the engine
1. **No Color Dynamics** — real Procreate brushes vary hue/saturation per stamp;
   without it strokes read as flat.
2. **No Rendering modes / Flow** — the blend character (glaze vs. intense) is fixed.
3. **No Dual Brush.**
4. **Default shape is soft-round** with no bundled shape/grain texture assets
   (`sourceID` defaults to nil), so every brush looks similar until textures ship.

**Highest-impact fix:** add **Color Dynamics** (stamp hue/sat/brightness jitter) and
a couple of **Rendering** modes — that's what separates a "dot stamper" from a
Procreate brush.

---

## Suggested priority across all three

1. **Transform rotation handle + edge handles** — biggest "broken → works" jump.
2. **Adjustments: wire Curves (logic exists) + drag-on-canvas gesture.**
3. **Brushes: Color Dynamics + Rendering modes.**
4. Then breadth: more adjustments (Sharpen/Noise handlers already have dead rows),
   Distort/Warp transform modes, Brush Studio tabs.
