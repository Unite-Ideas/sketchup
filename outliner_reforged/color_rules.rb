# frozen_string_literal: true

module UniteIdeas
  module OutlinerReforged
    # Turns facts about an entity into a row color. Presets cover the common
    # asks; the "custom" scheme runs user-defined rules (first match wins,
    # anything unmatched falls back to default ink in the UI, represented here
    # as nil).
    module ColorRules
      # Type palette — distinct, readable in both themes.
      TYPE_COLORS = {
        "group"     => "#3B7DD8",
        "component" => "#8A63D2",
        "image"     => "#2E9E6B",
        "section"   => "#D9902B",
        "dimension" => "#C77DBB",
        "text"      => "#C77DBB",
        "guide"     => "#79818F",
        "geometry"  => "#79818F",
      }.freeze

      STATE_LOCKED = "#D9902B"
      STATE_HIDDEN = "#79818F"
      STATE_OK     = "#2E9E6B"

      module_function

      # facts: {
      #   type:, tag_name:, tag_color:, locked:, hidden:, unique:,
      #   has_material:, dynamic:
      # }
      def color_for(facts, scheme, custom_rules = [])
        case scheme
        when "by_tag"   then facts[:tag_color]        # nil => default ink
        when "by_type"  then TYPE_COLORS[facts[:type]]
        when "by_state" then state_color(facts)
        when "custom"   then custom_color(facts, custom_rules)
        else nil
        end
      end

      def state_color(facts)
        return STATE_HIDDEN if facts[:hidden]
        return STATE_LOCKED if facts[:locked]
        STATE_OK
      end

      def custom_color(facts, rules)
        Array(rules).each do |rule|
          return rule["color"] if rule_matches?(rule, facts)
        end
        nil
      end

      def rule_matches?(rule, facts)
        field = rule["field"]
        value = rule["value"]
        op    = rule["op"] || "eq"
        actual =
          case field
          when "tag"      then facts[:tag_name]
          when "type"     then facts[:type]
          when "locked"   then facts[:locked]
          when "hidden"   then facts[:hidden]
          when "unique"   then facts[:unique]
          when "material" then facts[:has_material]
          when "dynamic"  then facts[:dynamic]
          end
        case op
        when "eq"    then actual.to_s == value.to_s
        when "neq"   then actual.to_s != value.to_s
        when "is"    then truthy?(actual)
        when "isnot" then !truthy?(actual)
        else false
        end
      end

      def truthy?(v)
        v == true || v.to_s == "true"
      end

      # Descriptor of the built-in schemes, sent to the UI for the picker.
      def scheme_options
        [
          { "id" => "by_tag",   "label" => "By tag" },
          { "id" => "by_type",  "label" => "By type" },
          { "id" => "by_state", "label" => "By state" },
          { "id" => "custom",   "label" => "Custom rules" },
          { "id" => "none",     "label" => "Off" },
        ]
      end
    end
  end
end
