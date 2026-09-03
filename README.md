# Outliner Reforged

A drop-in replacement for SketchUp's Outliner — everything the native panel
does, plus the things people have been asking for for years:

- **Move to Top Level** — right-click any deeply nested group/component and
  yank it to the model root in one click, geometry frozen in world space.
  (Plus **Move Up One Level**.)
- **Rule-based color coding** — row text colored by tag, type, state
  (locked/hidden), or your own custom rules.
- **Extended right-click menu** — zoom-to, isolate, select-all-instances,
  make-unique, explode, hide/lock, delete, rename.
- **Show everything** — optional rows for loose geometry (summarized),
  section planes, dimensions, text, guides, and images, not just
  groups/components.
- **Search + filter** — filter by name, type, tag, locked, hidden, or
  "no material," with matched paths auto-revealed.
- **State-at-a-glance badges** — lock, hidden, dynamic, instance count, and
  a tag color chip on every row.
- **Two-way selection sync** — select in the model and the tree reveals and
  scrolls to it; select in the tree and it selects in the model.

## Requirements

SketchUp **2017 or newer** (uses `UI::HtmlDialog`).

## Install

Copy both of these into your SketchUp `Plugins` folder:

```
sketchup_outliner_reforged.rb      # registration stub
outliner_reforged/                 # extension code
```

Then restart SketchUp. Open the panel from **Window → Outliner Reforged**
or the **Outliner Reforged** toolbar.

Plugins folder locations:

- **Windows:** `%AppData%\SketchUp\SketchUp 20XX\SketchUp\Plugins`
- **macOS:** `~/Library/Application Support/SketchUp 20XX/SketchUp/Plugins`

## Architecture

Three tiers (see the [build plan](#) for the full write-up):

| File | Role |
| --- | --- |
| `sketchup_outliner_reforged.rb` | Extension Warehouse registration stub |
| `outliner_reforged/main.rb` | Controller: dialog, message bus, observer wiring |
| `outliner_reforged/tree_builder.rb` | Model → serializable tree + lookups |
| `outliner_reforged/actions.rb` | Undoable model mutations (move, rename, …) |
| `outliner_reforged/observers.rb` | Selection / entities / app observers |
| `outliner_reforged/color_rules.rb` | Color-coding rule engine + presets |
| `outliner_reforged/settings.rb` | Per-user prefs + per-model expand state |
| `outliner_reforged/html/` | The panel UI (HTML/CSS/JS) |

The panel renders in an `HtmlDialog`; JS calls Ruby with
`sketchup.msg(JSON)`, Ruby pushes state back via `execute_script`. Observers
keep the two in sync and our own edits run with observers suspended so they
don't ricochet into rebuild loops. The whole tree serializes lazily — only
children of expanded rows are sent — except while a search/filter is active,
when matched paths are walked and revealed.

## Fonts

The panel uses **Nexa** when it's installed on the machine, and falls back to
**Source Sans 3** (bundled, OFL licensed) everywhere else. Nexa is a
commercial font and is deliberately **not** bundled — it's referenced via CSS
`local()` only, so nothing about a teammate's machine or Extension Warehouse
distribution redistributes it. Source Sans 3's license travels with it in
`outliner_reforged/html/fonts/OFL.txt`.

## Known behavior & limitations (v1)

- **Group → component on move.** The Ruby API has no true "reparent," so
  Move-to-Top recreates the instance from its definition and erases the
  original. A **Group** source therefore comes back as a **ComponentInstance
  sharing the group's definition** — geometry and identity are preserved;
  only the wrapper type changes. Components move as components.
- **The panel floats.** `HtmlDialog` can't dock into the tray beside the
  native panels — a limitation of the SketchUp API, not this extension.
- **Large models.** The tree is virtualized (only on-screen rows are in the
  DOM) and children load lazily, so scrolling stays smooth at scale. The one
  remaining cost is that a model change triggers a debounced *full* rebuild
  rather than a targeted diff — fine for typical edits, and the next perf
  item on the roadmap.
- **New definitions created externally** after the panel opens aren't
  observed until the next rebuild is otherwise triggered.

## Roadmap

- [x] Extension scaffold + Ruby↔JS bridge
- [x] Nested tree, expand/collapse (persisted per model), two-way sync
- [x] Rename, hide/lock, delete
- [x] Move to Top Level / Move Up One Level
- [x] Extended right-click menu
- [x] Color coding (by tag / type / state / custom) + state badges
- [x] Show-everything, search + filter, sorting
- [x] Row virtualization (perf at 10k+ entities)
- [x] Custom color-rule editor UI
- [x] Batch rename (multi-select, `#` counter)
- [x] Toolbar icon (SVG)
- [x] Drag-and-drop reparenting (drop onto a group, or empty space for root)
- [x] Inline visibility dot (solid = shown, hollow = hidden)
- [ ] Diff-based updates (currently a debounced full re-render on change)
- [ ] Keyboard navigation (arrow keys, type-to-find)
- [ ] Group-preserving move (keep a group a group)

## License

© Unite Ideas.
