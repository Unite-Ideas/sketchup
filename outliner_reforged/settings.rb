# frozen_string_literal: true

module UniteIdeas
  module OutlinerReforged
    # Per-user preferences (color scheme, show-everything, window bounds) live
    # in SketchUp's registry via read_default/write_default. Per-model state
    # (which rows are expanded) lives in a model attribute dictionary so it
    # follows the .skp file.
    module Settings
      PREFS = "UniteIdeas_OutlinerReforged"
      MODEL_DICT = "OutlinerReforged"

      DEFAULTS = {
        "color_scheme"  => "by_tag",   # by_tag | by_type | by_state | none | custom
        "show_all"      => false,      # include loose geometry / dims / etc.
        "sort"          => "model",    # model | name | type | count
        "ui_font"       => "nexa",     # nexa | nexabook | source | system (cosmetic)
        "win_w"         => 340,
        "win_h"         => 600,
      }.freeze

      module_function

      def get(key)
        val = Sketchup.read_default(PREFS, key, DEFAULTS[key])
        val.nil? ? DEFAULTS[key] : val
      end

      def set(key, value)
        Sketchup.write_default(PREFS, key, value)
      end

      def all
        DEFAULTS.keys.each_with_object({}) { |k, h| h[k] = get(k) }
      end

      # ---- per-model expanded-row set (stored as an array of pid strings) ----

      def expanded_ids(model = Sketchup.active_model)
        return [] unless model
        raw = model.get_attribute(MODEL_DICT, "expanded", nil)
        raw.is_a?(Array) ? raw.map(&:to_s) : []
      end

      def set_expanded_ids(ids, model = Sketchup.active_model)
        return unless model
        # Guard: writing model attributes is a model change; callers wrap this
        # so it does not trip our own observers into a rebuild loop.
        model.set_attribute(MODEL_DICT, "expanded", Array(ids).map(&:to_s))
      end

      # ---- custom color rules (stored per user as a JSON-ish array) ----
      # Each rule: { "field" => "tag|type|locked|hidden|unique|material",
      #              "op" => "eq|neq|is|isnot", "value" => "...",
      #              "color" => "#rrggbb" }

      def custom_rules
        raw = Sketchup.read_default(PREFS, "custom_rules", nil)
        raw.is_a?(Array) ? raw : []
      end

      def set_custom_rules(rules)
        Sketchup.write_default(PREFS, "custom_rules", Array(rules))
      end
    end
  end
end
