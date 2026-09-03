# frozen_string_literal: true
#
# Swift Cleanup — core geometry logic.
#
# The one operation that matters for imported Revit/CAD models: merging the
# coplanar triangle-soup back into flat faces. We do it the fast way —
# collect every removable edge in a definition, then erase them all in a
# single `erase_entities` call, so SketchUp's geometry kernel heals the whole
# definition in one pass instead of re-healing after every single edge.

module UniteIdeas
  module SwiftCleanup
    module Core
      # Two faces count as coplanar when their normals point the same way to
      # within this dot-product tolerance. 0.9999 ≈ 0.81°, tight enough to
      # keep curved surfaces (whose facets differ by more) fully intact.
      NORMAL_DOT_TOLERANCE = 0.9999

      # Update the status bar at most this often (every N scopes) so progress
      # reporting never becomes its own bottleneck.
      PROGRESS_EVERY = 100

      module_function

      # --- Public entry points ------------------------------------------------

      # Merge coplanar faces across the whole model: every in-use definition
      # plus the model root. Returns a stats hash. Wrapped in a single undoable
      # operation with the UI disabled for speed.
      def clean_model(match_materials: true)
        run_cleanup(gather_model_scopes, match_materials)
      end

      # Same, but limited to the definitions reachable from the current
      # selection. Handy for benchmarking on a single component.
      def clean_selection(match_materials: true)
        scopes = gather_selection_scopes
        return nil if scopes.empty?

        run_cleanup(scopes, match_materials)
      end

      # Dry run: scan and report what a cleanup *would* do, changing nothing.
      def report_model(match_materials: true)
        scopes = gather_model_scopes
        edges = 0
        faces = 0
        removable = 0
        scopes.each_with_index do |ents, i|
          progress("Swift Cleanup — scanning", i, scopes.size)
          edges += ents.grep(Sketchup::Edge).size
          faces += ents.grep(Sketchup::Face).size
          removable += removable_edges(ents, match_materials).size
        end
        Sketchup.status_text = ""
        {
          scopes: scopes.size,
          edges: edges,
          faces: faces,
          removable: removable
        }
      end

      # --- Cleanup core -------------------------------------------------------

      def run_cleanup(scopes, match_materials)
        model = Sketchup.active_model
        start = Time.now
        faces_before = count_faces(scopes)
        edges_removed = 0

        model.start_operation("Swift Cleanup", true)
        begin
          scopes.each_with_index do |ents, i|
            progress("Swift Cleanup — merging", i, scopes.size)
            edges = removable_edges(ents, match_materials)
            next if edges.empty?

            ents.erase_entities(edges)
            edges_removed += edges.size
          end
          model.commit_operation
        rescue StandardError => e
          model.abort_operation
          Sketchup.status_text = ""
          raise e
        end

        faces_after = count_faces(scopes)
        elapsed = Time.now - start
        Sketchup.status_text =
          "Swift Cleanup: removed #{edges_removed} edges / " \
          "#{faces_before - faces_after} faces in #{elapsed.round(1)}s"

        {
          scopes: scopes.size,
          edges_removed: edges_removed,
          faces_before: faces_before,
          faces_after: faces_after,
          seconds: elapsed
        }
      end

      # Every edge in `ents` whose two bordering faces are coplanar (and, when
      # match_materials is on, share front and back material). Edges with any
      # other face count — 0 (stray), 1 (a real boundary/hole) or 3+
      # (non-manifold) — are left alone.
      def removable_edges(ents, match_materials)
        result = []
        ents.grep(Sketchup::Edge).each do |edge|
          faces = edge.faces
          next unless faces.size == 2

          f1, f2 = faces
          next unless coplanar?(f1, f2)

          if match_materials
            next unless f1.material == f2.material
            next unless f1.back_material == f2.back_material
          end

          result << edge
        end
        result
      end

      # Faces sharing an edge are coplanar when their normals are parallel and
      # point the same direction. Opposite normals mean back-to-back faces
      # (zero-thickness) — never merged.
      def coplanar?(face1, face2)
        face1.normal.dot(face2.normal) >= NORMAL_DOT_TOLERANCE
      end

      # --- Scope gathering ----------------------------------------------------

      # Entities collections to process. Iterating every in-use definition
      # covers nested groups/components too (each is its own definition), so
      # no manual recursion is needed. The model root is added for the rare
      # bits of loose top-level geometry.
      def gather_model_scopes
        model = Sketchup.active_model
        model.definitions.purge_unused

        scopes = []
        model.definitions.each do |d|
          next if d.image?
          next if d.count_used_instances.zero?

          scopes << d.entities
        end
        scopes << model.entities
        scopes
      end

      # Definitions reachable from the current selection, walked recursively so
      # nested components are included. Deduped so a definition used many times
      # is cleaned once.
      def gather_selection_scopes
        model = Sketchup.active_model
        seen = {}
        scopes = []
        walk_instances(model.selection.to_a, seen, scopes)
        scopes
      end

      def walk_instances(entities, seen, scopes)
        entities.each do |ent|
          definition = definition_of(ent)
          next if definition.nil?
          next if seen[definition.entityID]

          seen[definition.entityID] = true
          ents = definition.entities
          scopes << ents
          walk_instances(ents.to_a, seen, scopes)
        end
      end

      # The definition behind a group or component instance, or nil for
      # anything else. Group#definition exists on modern SketchUp; guard it.
      def definition_of(ent)
        if ent.is_a?(Sketchup::ComponentInstance)
          ent.definition
        elsif ent.is_a?(Sketchup::Group)
          ent.respond_to?(:definition) ? ent.definition : nil
        end
      end

      # --- Helpers ------------------------------------------------------------

      def count_faces(scopes)
        scopes.sum { |ents| ents.grep(Sketchup::Face).size }
      end

      def progress(label, index, total)
        return unless (index % PROGRESS_EVERY).zero?

        Sketchup.status_text = "#{label}: #{index}/#{total}…"
      end
    end
  end
end
