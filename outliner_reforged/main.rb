# frozen_string_literal: true

require "sketchup.rb"
require "json"
require "set"

module UniteIdeas
  module OutlinerReforged
    PLUGIN_DIR = File.dirname(__FILE__)

    require File.join(PLUGIN_DIR, "settings")
    require File.join(PLUGIN_DIR, "color_rules")
    require File.join(PLUGIN_DIR, "tree_builder")
    require File.join(PLUGIN_DIR, "actions")
    require File.join(PLUGIN_DIR, "observers")

    IDENTITY = Geom::Transformation.new

    # Owns the dialog, the model<->UI bridge, and the observer wiring.
    class Controller
      def initialize
        @builder     = TreeBuilder.new
        @dialog      = nil
        @suspend     = false
        @suspend_sel = false
        @rebuild_timer = nil
        @sel_timer     = nil
        @visible_ids   = Set.new
        @expanded      = Set.new
      end

      def suspended?
        @suspend
      end

      # ---- lifecycle ---------------------------------------------------------

      def toggle
        if @dialog && @dialog.visible?
          @dialog.close
        else
          show
        end
      end

      def show
        create_dialog unless @dialog
        load_model_state
        attach_observers
        @dialog.show
      end

      def create_dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title:    "Outliner Reforged",
          preferences_key: "UniteIdeas_OutlinerReforged",
          scrollable:      true,
          resizable:       true,
          width:           Settings.get("win_w"),
          height:          Settings.get("win_h"),
          min_width:       260,
          min_height:      320,
          style:           UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(PLUGIN_DIR, "html", "panel.html"))
        wire_callbacks
        @dialog.set_on_closed { detach_observers }
      end

      def wire_callbacks
        @dialog.add_action_callback("msg") do |_ctx, payload|
          begin
            handle(JSON.parse(payload))
          rescue StandardError => e
            warn "OutlinerReforged callback error: #{e.message}"
          end
          nil
        end
      end

      # ---- message dispatch --------------------------------------------------

      def handle(msg)
        model = Sketchup.active_model
        return unless model
        case msg["action"]
        when "ready"          then push_settings; build_and_push; push_selection
        when "select"         then do_select(model, msg)
        when "toggle_expand"  then do_toggle_expand(model, msg)
        when "rename"         then guarded(model) { Actions.rename(model, ent(msg["id"]), msg["name"]) }; build_and_push
        when "set_setting"    then set_setting(msg["key"], msg["value"]); build_and_push unless cosmetic?(msg["key"])
        when "search"         then @query = msg["query"]; @filters = msg["filters"] || {}; build_and_push
        when "action"         then do_action(model, msg)
        when "batch_rename"   then do_batch_rename(model, msg)
        when "set_rules"      then Settings.set_custom_rules(msg["rules"] || []); build_and_push
        when "get_tags"       then push_tags(model)
        end
      end

      # ---- selection ---------------------------------------------------------

      def do_select(model, msg)
        e = ent(msg["id"])
        return unless e && e.valid?
        @suspend_sel = true
        sel = model.selection
        sel.clear unless msg["add"]
        if msg["add"] && sel.contains?(e)
          sel.remove(e)
        else
          sel.add(e)
        end
        @suspend_sel = false
        push_selection
      end

      def schedule_selection_sync
        return if @suspend_sel
        @sel_timer && UI.stop_timer(@sel_timer)
        @sel_timer = UI.start_timer(0.05, false) { push_selection }
      end

      def push_selection
        model = Sketchup.active_model
        return unless model && @dialog
        selected = model.selection.to_a
        pids = selected.map { |e| pid(e) }

        # Reveal: if a single selected container isn't visible in the tree,
        # expand its ancestors and rebuild so it scrolls into view.
        if selected.length == 1 && !@visible_ids.include?(pids.first)
          path = @builder.find_path(model, selected.first)
          unless path.empty?
            path.each { |p| @expanded << p }
            persist_expanded
            build_and_push(select_after: pids)
            return
          end
        end
        exec("OR.setSelection(#{pids.to_json})")
      end

      # ---- expand/collapse ---------------------------------------------------

      def do_toggle_expand(_model, msg)
        id = msg["id"].to_s
        if msg["expanded"]
          @expanded << id
        else
          @expanded.delete(id)
        end
        persist_expanded
        build_and_push
      end

      def persist_expanded
        guarded(Sketchup.active_model) do
          Settings.set_expanded_ids(@expanded.to_a, Sketchup.active_model)
        end
      end

      # ---- actions -----------------------------------------------------------

      def do_action(model, msg)
        e = ent(msg["id"])
        return unless e && e.valid?
        name = msg["name"]
        select_after = nil

        case name
        when "move_to_top"
          new_e = guarded(model) do
            Actions.reparent(model, e, model.entities, world(msg["id"]), "Move to Top Level")
          end
          select_after = [pid(new_e)] if new_e.is_a?(Sketchup::Entity)
        when "move_up"
          new_e = move_up_one(model, msg["id"], e)
          select_after = [pid(new_e)] if new_e.is_a?(Sketchup::Entity)
        when "toggle_visible" then guarded(model) { Actions.toggle_visible(model, e) }
        when "toggle_lock"    then guarded(model) { Actions.toggle_lock(model, e) }
        when "delete"         then guarded(model) { Actions.erase(model, e) }
        when "make_unique"    then guarded(model) { Actions.make_unique(model, e) }
        when "explode"        then guarded(model) { Actions.explode(model, e) }
        when "isolate"        then guarded(model) { Actions.isolate(model, e, context_entities(msg["id"])) }
        when "show_all"       then guarded(model) { Actions.show_all(model) }
        when "zoom"           then Actions.zoom_to(model, e); return
        when "select_instances"
          @suspend_sel = true
          Actions.select_all_instances(model, e)
          @suspend_sel = false
          push_selection
          return
        end

        build_and_push(select_after: select_after)
      end

      def do_batch_rename(model, msg)
        ids = Array(msg["ids"])
        ents = ids.map { |i| ent(i) }.compact.select(&:valid?)
        return if ents.empty?
        guarded(model) do
          Actions.batch_rename(model, ents, msg["pattern"].to_s, (msg["start"] || 1).to_i)
        end
        build_and_push
      end

      # Move one level up: recompute the transform relative to the grandparent
      # context and recreate the instance there.
      def move_up_one(model, id, e)
        parent_pid = @builder.parent_map[id.to_s]
        return :noop if parent_pid.nil? # already at top level

        grand_pid = @builder.parent_map[parent_pid]
        if grand_pid.nil?
          target_entities = model.entities
          grand_world     = IDENTITY
        else
          grand_e = @builder.entity_map[grand_pid]
          return :noop unless grand_e && grand_e.valid?
          target_entities = grand_e.is_a?(Sketchup::Group) ? grand_e.entities : grand_e.definition.entities
          grand_world     = @builder.world_map[grand_pid] || IDENTITY
        end
        local = grand_world.inverse * world(id)
        guarded(model) do
          Actions.reparent(model, e, target_entities, local, "Move Up One Level")
        end
      end

      # ---- build & push ------------------------------------------------------

      def build_and_push(select_after: nil)
        model = Sketchup.active_model
        return unless model && @dialog
        nodes = @builder.build(model, build_opts)
        @visible_ids = collect_ids(nodes)
        exec("OR.render(#{nodes.to_json})")
        if select_after
          @suspend_sel = true
          reselect(model, select_after)
          @suspend_sel = false
        end
        push_selection unless select_after
        exec("OR.setSelection(#{select_after.to_json})") if select_after
      end

      def build_opts
        {
          expanded:     @expanded,
          show_all:     truthy(Settings.get("show_all")),
          scheme:       Settings.get("color_scheme"),
          custom_rules: Settings.custom_rules,
          sort:         Settings.get("sort"),
          query:        @query,
          filters:      @filters || {}
        }
      end

      def reselect(model, pids)
        model.selection.clear
        pids.each do |p|
          e = @builder.entity_map[p]
          model.selection.add(e) if e && e.valid?
        end
      end

      def schedule_rebuild
        @rebuild_timer && UI.stop_timer(@rebuild_timer)
        @rebuild_timer = UI.start_timer(0.15, false) { build_and_push }
      end

      # ---- settings & tags ---------------------------------------------------

      def push_settings
        data = Settings.all
        data["schemes"] = ColorRules.scheme_options
        data["rules"]   = Settings.custom_rules
        exec("OR.setSettings(#{data.to_json})")
      end

      def set_setting(key, value)
        return unless Settings::DEFAULTS.key?(key)
        Settings.set(key, value)
      end

      # Cosmetic keys change only CSS in the panel; no tree rebuild needed.
      def cosmetic?(key)
        key == "ui_font"
      end

      def push_tags(model)
        tags = model.layers.map(&:name).reject { |n| n == "Layer0" }
        exec("OR.setTags(#{tags.to_json})")
      end

      # ---- observers ---------------------------------------------------------

      def attach_observers
        return if @observers_attached
        model = Sketchup.active_model
        return unless model
        @sel_obs ||= Observers::SelectionWatcher.new(self)
        @ent_obs ||= Observers::EntityWatcher.new(self)
        @app_obs ||= Observers::AppWatcher.new(self)
        model.selection.add_observer(@sel_obs)
        Sketchup.add_observer(@app_obs)
        observe_entities(model)
        @observers_attached = true
      end

      def observe_entities(model)
        model.entities.add_observer(@ent_obs)
        model.definitions.each { |d| d.entities.add_observer(@ent_obs) }
      end

      def detach_observers
        model = Sketchup.active_model
        if model
          model.selection.remove_observer(@sel_obs) if @sel_obs
          model.entities.remove_observer(@ent_obs) if @ent_obs
          model.definitions.each { |d| d.entities.remove_observer(@ent_obs) } if @ent_obs
        end
        Sketchup.remove_observer(@app_obs) if @app_obs
        @observers_attached = false
      end

      def on_model_switched
        @observers_attached = false
        load_model_state
        attach_observers
        push_settings
        build_and_push
      end

      def load_model_state
        @expanded = Set.new(Settings.expanded_ids)
        @query = nil
        @filters = {}
      end

      # ---- small helpers -----------------------------------------------------

      # Run a block with observers suspended (so our own model edits don't
      # trigger a rebuild mid-operation), then rebuild once at the end.
      def guarded(_model)
        prev = @suspend
        @suspend = true
        yield
      ensure
        @suspend = prev
      end

      def ent(id)
        @builder.entity_map[id.to_s]
      end

      def world(id)
        @builder.world_map[id.to_s] || IDENTITY
      end

      def context_entities(id)
        parent_pid = @builder.parent_map[id.to_s]
        model = Sketchup.active_model
        return model.entities if parent_pid.nil?
        pe = @builder.entity_map[parent_pid]
        return model.entities unless pe
        pe.is_a?(Sketchup::Group) ? pe.entities : pe.definition.entities
      end

      def pid(e)
        return nil unless e.is_a?(Sketchup::Entity)
        p = (e.respond_to?(:persistent_id) ? e.persistent_id : 0)
        p = e.entityID if p.nil? || p.zero?
        p.to_s
      end

      def collect_ids(nodes, acc = Set.new)
        nodes.each do |n|
          acc << n[:id]
          collect_ids(n[:children], acc) if n[:children]
        end
        acc
      end

      def truthy(v)
        v == true || v.to_s == "true"
      end

      def exec(js)
        @dialog.execute_script(js) if @dialog && @dialog.visible?
      end
    end

    # ---- singleton + UI hooks -----------------------------------------------

    def self.controller
      @controller ||= Controller.new
    end

    unless file_loaded?(__FILE__)
      # One command drives both the menu item and the toolbar button.
      cmd = UI::Command.new("Outliner Reforged") { controller.toggle }
      cmd.tooltip = "Outliner Reforged"
      cmd.status_bar_text = "Open the Outliner Reforged panel"
      # SketchUp 2016+ supports vector (SVG) toolbar icons; fall back to PNG.
      svg = File.join(PLUGIN_DIR, "html", "icon.svg")
      png = File.join(PLUGIN_DIR, "html", "icon.png")
      icon = File.exist?(svg) ? svg : (File.exist?(png) ? png : nil)
      if icon
        cmd.small_icon = icon
        cmd.large_icon = icon
      end

      # Put it in the Extensions menu (where users look for plugins).
      UI.menu("Extensions").add_item(cmd)

      tb = UI::Toolbar.new("Outliner Reforged")
      tb.add_item(cmd)
      # Force the toolbar visible on load. get_last_state returns
      # TB_HIDDEN after the user (or repeated reinstalls) has closed it, and a
      # bare restore would keep it hidden -- so show it unless it was never
      # shown, in which case restore lets SketchUp place it sensibly.
      state = tb.get_last_state
      state == TB_NEVER_SHOWN ? tb.restore : tb.show

      file_loaded(__FILE__)
    end
  end
end
