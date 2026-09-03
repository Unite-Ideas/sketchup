# Swift Cleanup

A fast, focused cleanup for imported **Revit/CAD geometry** in SketchUp.

Imported models arrive as triangle soup: every flat surface is chopped into
triangles with useless diagonal edges, and a whole building carries millions
of them. The usual cleanup plugins grind through this by erasing edges **one
at a time** — each erase forces SketchUp's geometry kernel to re-heal the
surrounding faces — which is why a large model can take half an hour.

Swift Cleanup does the same coplanar-face merge, but **in one batched pass per
component definition**: it finds every removable edge first, then erases them
all in a single call so the kernel heals the whole definition at once.

## What it does (v0.1)

- **Merges coplanar faces** — collapses triangulated flat surfaces back into
  single faces.
- **Keeps curves intact** — only faces whose normals point the same way are
  merged, so cylinders, fillets, and rounded hardware are untouched.
- **Preserves material boundaries** — by default it won't merge two coplanar
  faces that carry different materials.
- **Cleans each unique definition once** — identical windows/mullions that
  share a definition are processed a single time, not per instance.
- **One undo step**, UI disabled during the run, with a status-bar progress
  readout and a before/after face count when it finishes.

Curved surfaces, material zones, and anything that isn't a genuine coplanar
seam are left exactly as they were.

## Menu

**Extensions → Swift Cleanup**

- **Merge Coplanar Faces (whole model)** — the main command.
- **Merge Coplanar Faces (selection only)** — process just the definitions
  used by the current selection; good for benchmarking on one component.
- **Preview — count removable edges** — a dry run that reports how many edges
  *would* be removed, changing nothing.

## Install

Copy both of these into your SketchUp `Plugins` folder:

```
sketchup_swift_cleanup.rb      # registration stub
swift_cleanup/                 # extension code
```

Then restart SketchUp. Or build an installable package with
`./build_swift_cleanup_rbz.sh` and install the resulting `.rbz` via
**Window → Extension Manager → Install Extension**.

## Not in this version yet

- **Definition dedup** — collapsing near-duplicate definitions that came in as
  separate copies (a large additional speedup for Revit imports) is planned as
  a second, opt-in pass once the merge is proven on real models.
- Stray-edge / duplicate-face removal, material merge, and other passes.

## Status

Early prototype (v0.1). Test on a copy of your model and compare against your
current tool before relying on it.
