# frozen_string_literal: true

module UniteIdeas
  module OutlinerReforged
    # Model-mutating operations invoked from the panel. Every mutation is
    # wrapped in a single, undoable operation.
    module Actions
      module_function

      # Re-home a group/component into target_entities using an explicit local
      # transform. Because the Ruby API has no true "reparent", we recreate the
      # instance from its definition, copy its identity across, then erase the
      # original. Returns the new entity (or :noop). NOTE: a Group source comes
      # back as a ComponentInstance sharing the group's definition -- geometry
      # is identical; only the wrapper type changes.
      def reparent(model, entity, target_entities, local_transform, op_name)
        return :noop unless movable?(entity)
        model.start_operation(op_name, true)
        new_e = target_entities.add_instance(entity.definition, local_transform)
        copy_identity(entity, new_e)
        entity.erase!
        model.commit_operation
        new_e
      rescue StandardError => e
        model.abort_operation
        warn "OutlinerReforged reparent failed: #{e.message}"
        :error
      end

      def rename(model, entity, name)
        return unless entity && entity.valid?
        model.start_operation("Rename", true)
        entity.name = name.to_s
        model.commit_operation
      end

      def toggle_visible(model, entity)
        return unless entity && entity.respond_to?(:hidden?)
        model.start_operation("Toggle Visibility", true)
        entity.hidden = !entity.hidden?
        model.commit_operation
      end

      def toggle_lock(model, entity)
        return unless entity && entity.respond_to?(:locked?)
        model.start_operation("Toggle Lock", true)
        entity.locked = !entity.locked?
        model.commit_operation
      end

      def erase(model, entity)
        return unless entity && entity.valid?
        model.start_operation("Delete", true)
        entity.erase!
        model.commit_operation
      end

      # Rename many entities at once. "#" in the pattern is replaced by an
      # incrementing counter starting at `start` (e.g. "Part #" -> Part 1,
      # Part 2, ...). A pattern with no "#" names every item identically.
      def batch_rename(model, entities, pattern, start)
        model.start_operation("Batch Rename", true)
        n = start
        entities.each do |e|
          next unless e.respond_to?(:name=)
          e.name = pattern.gsub("#", n.to_s)
          n += 1
        end
        model.commit_operation
      end

      def make_unique(model, entity)
        return unless entity && entity.respond_to?(:make_unique)
        model.start_operation("Make Unique", true)
        entity.make_unique
        model.commit_operation
      end

      def explode(model, entity)
        return unless entity && entity.respond_to?(:explode)
        model.start_operation("Explode", true)
        entity.explode
        model.commit_operation
      end

      # Hide every sibling in the target's context except the target itself.
      def isolate(model, entity, context_entities)
        model.start_operation("Isolate", true)
        context_entities.each do |e|
          next unless e.respond_to?(:hidden?)
          e.hidden = (e != entity)
        end
        model.commit_operation
      end

      # Unhide everything in the model (undo for isolate / stray hides).
      def show_all(model)
        model.start_operation("Show All", true)
        unhide_all(model.entities)
        model.commit_operation
      end

      def zoom_to(model, entity)
        model.active_view.zoom(entity)
      end

      def select_all_instances(model, entity)
        defn = definition_of(entity)
        return unless defn
        model.selection.clear
        defn.instances.each { |i| model.selection.add(i) }
      end

      # ---- helpers -----------------------------------------------------------

      def movable?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def definition_of(entity)
        return entity.definition if movable?(entity)
        nil
      end

      def copy_identity(src, dst)
        dst.name = src.name if src.respond_to?(:name) && dst.respond_to?(:name=) && !src.name.to_s.empty?
        dst.layer = src.layer if src.respond_to?(:layer)
        dst.material = src.material if src.respond_to?(:material) && src.material
        dst.hidden = src.hidden? if src.respond_to?(:hidden?) && dst.respond_to?(:hidden=)
        dst.locked = src.locked? if src.respond_to?(:locked?) && dst.respond_to?(:locked=)
        if src.respond_to?(:casts_shadows?) && dst.respond_to?(:casts_shadows=)
          dst.casts_shadows = src.casts_shadows?
        end
        if src.respond_to?(:receives_shadows?) && dst.respond_to?(:receives_shadows=)
          dst.receives_shadows = src.receives_shadows?
        end
        copy_attributes(src, dst)
      end

      def copy_attributes(src, dst)
        dicts = src.attribute_dictionaries
        return unless dicts
        dicts.each do |dict|
          dict.each_pair { |k, v| dst.set_attribute(dict.name, k, v) }
        end
      rescue StandardError
        # Attribute copy is best-effort; never fail the whole move over it.
      end

      def unhide_all(entities)
        entities.each do |e|
          e.hidden = false if e.respond_to?(:hidden?) && e.hidden?
          if e.is_a?(Sketchup::Group)
            unhide_all(e.entities)
          elsif e.is_a?(Sketchup::ComponentInstance)
            unhide_all(e.definition.entities)
          end
        end
      end
    end
  end
end
