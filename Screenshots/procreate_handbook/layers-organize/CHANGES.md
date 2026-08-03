# Layers Panel — Procreate Parity Report (updated)

Status of the app against the Procreate **Layers → Organize** handbook page.
Reference screenshots are in this folder.

Legend: ✅ done · 🟡 partial · 🔴 missing · ⚠️ present but not enforced

UI: `ProcreatePOC.swiftpm/ContentView.swift` (`LayersPanel`, `LayerRow`,
`LayerDropDelegate`, `LayerOptionsMenu`) + `PaintModel.swift`.
Core: `Sources/ProcreateCore/LayerStack.swift` + `LayerOperations.swift`.

---

## Summary

**~90% of the handbook page is now implemented.** Every interaction on the page has
a working path except cross-canvas nuances and one enforcement gap. This is a large
jump from the prior report (was ~45%: model solid, UI thin).

| # | Feature | Reference | Prev | Now |
|---|---------|-----------|------|-----|
| 1 | Swipe-left Lock/Duplicate/Delete | `08_lock_duplicate_delete_swipe.png` | 🔴 | ✅ |
| 2 | Primary vs Secondary selection | `01_select_layers_primary_secondary.png` | 🔴 | ✅ |
| 3 | Group rendering + collapse | `04_group_layers.png` | 🟡 | ✅ |
| 4 | Grouping from selection | `04_group_layers.png` | 🟡 | ✅ |
| 5 | Ungroup | `05_ungroup.png` | 🔴 | ✅ |
| 6 | Drag-to-reorder | `06_move_reorder.png` | 🟢 | ✅ |
| 7 | Real thumbnails | (any) | 🔴 | ✅ |
| 8 | Move between canvases | `07_move_between_canvases.png` | 🔴 | 🟡 |
| 9 | Layer Select gesture | `02`/`03` | 🔴 | 🟡 |
| — | **Full Layer Lock enforcement** | `08_...swipe.png` | ⚠️ | ⚠️ |

---

## What's now working

**#1 Swipe-left quick actions** — `LayerRow` has a `DragGesture` that reveals a
trailing Lock / Duplicate / Delete strip (grey / grey / red), latching open and
wired to `toggleLayerLock` / `duplicateLayer` / `deleteLayer`. Delete is now
reachable (was the big hole). `ContentView.swift:1141`, gesture at `:1221`.

**#2 Primary/Secondary selection** — `PaintModel.secondarySelection: Set<LayerID>`,
swipe-right toggles it, `LayerRow` tints Primary bright (`PC.active`) vs Secondary
dim navy (`PC.activeDim`). Matches the two-blue treatment in the reference.
`PaintModel.swift:31/45`, tint at `ContentView.swift:1121`.

**#3 Group rendering + collapse** — `displayRows` now recurses the tree, emitting
indented child rows with a chevron; collapsed groups hide children
(`collapsedGroups`, `toggleCollapsed`). Group rows show a folder icon.
`ContentView.swift:919`.

**#4 Grouping** — panel button calls `model.groupSelection()` over the selected ids.
`ContentView.swift:810`, `PaintModel.swift:66`.

**#5 Ungroup** — `LayerStack.ungroup(_:)` splices children back to the parent;
"Ungroup" appears in the reduced menu for group rows. `LayerStack.swift:165`,
menu at `ContentView.swift:983`.

**#6 Drag-to-reorder** — `.onDrag`/`.onDrop` with `LayerDropDelegate` calling the
tested `LayerStack.move(_:above:)` (reparents across groups). `ContentView.swift:856`.

**#7 Thumbnails** — real downscaled previews via `model.layerThumbnail(id)` with a
checkerboard for transparency; `invalidateThumbnail` refreshes them.
`ContentView.swift:1180`, `PaintModel.swift:603/611`.

---

## Remaining gaps

### ⚠️ Full Layer Lock is not enforced — highest priority

**Reference:** `08_lock_duplicate_delete_swipe.png`

`isLocked` is toggled and drawn as a badge, but **nothing in the paint pipeline
consults it**. `beginStroke` (`MetalCanvasRenderer.swift:366`) has no lock guard;
the only grep hit for `isLocked` outside the model/badge is the display row. So a
"locked" layer can still be painted, cleared, transformed, and deleted.

Note: *Alpha* lock is correctly enforced (folded into the per-stroke paint mask at
`MetalCanvasRenderer.swift:392`). This gap is specifically the **full Layer Lock**.

Procreate spec §6.4: Layer Lock = cannot edit, move, cut, paste, transform, or
delete. Fix: guard `beginStroke` / `clear` / `fillActiveLayer` / transform / delete
on `layerProperties(activeLayerID)?.isLocked`, and skip the swipe-Delete for locked
rows.

### 🟡 #8 Move layers between canvases

`PaintModel.moveLayer(_:toCanvas:)` and `moveTargets()` exist (`:250/268`), so the
data move works. What's missing vs. the reference is the **drag-out-to-Gallery**
interaction — the handbook shows dragging a layer thumbnail onto the Gallery to
spawn/target a canvas. Currently reachable only via a target list, not the drag.

### 🟡 #9 Layer Select gesture

`PaintModel.layerSelect(atX:atY:)` exists (`:582`) — the canvas-based pick works.
Not yet bound to a gesture/Pencil-squeeze or surfaced as the floating list shown in
`03_layer_select_list.png`. Depends on gesture-binding work; low priority.

---

## Suggested next steps

1. **Enforce full Layer Lock** (correctness — currently a silent no-op). Verify by
   locking a layer and confirming a stroke does nothing.
2. #8 drag-out-to-Gallery, if cross-canvas is in scope.
3. #9 bind Layer Select to a gesture + floating list (optional/polish).
