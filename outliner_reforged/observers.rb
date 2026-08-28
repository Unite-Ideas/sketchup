# frozen_string_literal: true

module UniteIdeas
  module OutlinerReforged
    # Observers translate model events into two debounced signals on the
    # controller: "selection changed" (cheap highlight) and "structure changed"
    # (rebuild the tree). The controller sets #suspended? during its own
    # operations so our writes don't ricochet into rebuild loops.
    module Observers
      class SelectionWatcher < Sketchup::SelectionObserver
        def initialize(controller)
          @controller = controller
        end

        def onSelectionBulkChange(_sel);  notify; end
        def onSelectionCleared(_sel);     notify; end
        def onSelectionAdded(_sel, _e);   notify; end
        def onSelectionRemoved(_sel, _e); notify; end

        def notify
          return if @controller.suspended?
          @controller.schedule_selection_sync
        end
      end

      class EntityWatcher < Sketchup::EntitiesObserver
        def initialize(controller)
          @controller = controller
        end

        def onElementAdded(_entities, _entity);    dirty; end
        def onElementRemoved(_entities, _id);      dirty; end
        def onElementModified(_entities, _entity); dirty; end

        def dirty
          return if @controller.suspended?
          @controller.schedule_rebuild
        end
      end

      class AppWatcher < Sketchup::AppObserver
        def initialize(controller)
          @controller = controller
        end

        def onNewModel(_model);  @controller.on_model_switched; end
        def onOpenModel(_model); @controller.on_model_switched; end
        # Fired right before SketchUp activates a model on some platforms.
        def onActivateModel(_model); @controller.on_model_switched; end
      end
    end
  end
end
