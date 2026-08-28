# frozen_string_literal: true

module UniteIdeas
  module OutlinerReforged
    # Walks the active model into a JSON-ready tree of nodes and, as a side
    # effect, records lookups the action layer needs: pid -> entity, pid ->
    # world transform, pid -> parent pid.
    #
    # Two render modes:
    #   * lazy   - only children of expanded rows are serialized (fast default)
    #   * search - a query/filter is active, so the whole tree is walked and
    #              pruned to matches, forcing matched paths open (reveal).
    class TreeBuilder
      TYPE_LABELS = {
        "group" => "grp", "component" => "cmp", "image" => "img",
        "section" => "sec", "dimension" => "dim", "text" => "txt",
        "guide" => "gui", "geometry" => "geo"
      }.freeze

      attr_reader :entity_map, :world_map, :parent_map

      def initialize
        reset!
      end

      def reset!
        @entity_map = {}
        @world_map  = {}
        @parent_map = {}
      end

      # opts: :expanded (Array/Set of pid strings), :show_all (bool),
      #       :scheme, :custom_rules, :query (String), :filters (Hash),
      #       :sort (String)
      def build(model, opts)
        reset!
        return [] unless model
        @opts     = opts
        @expanded = to_set(opts[:expanded])
        @searching = searching?(opts)
        build_children(model.entities, IDENTITY, nil, 0)
      end

      # Ancestor pid path (root-first) for a live entity, or [] if not found.
      # Used to reveal a selected entity by expanding its ancestors.
      def find_path(model, target)
        return [] unless model && target
        path = []
        walk = lambda do |entities, trail|
          entities.each do |e|
            next unless container?(e)
            here = trail + [pid_for(e)]
            if e == target
              path = trail # ancestors only, not the target itself
              return true
            end
            return true if walk.call(child_entities(e), here)
          end
          false
        end
        walk.call(model.entities, [])
        path
      end

      private

      IDENTITY = Geom::Transformation.new unless defined?(IDENTITY)

      def build_children(entities, parent_world, parent_pid, depth)
        containers = []
        aggregate  = { edges: 0, faces: 0, curves: 0 }
        loose      = []

        entities.each do |e|
          if container?(e)
            containers << e
          elsif @opts[:show_all]
            case classify(e)
            when "geometry"
              aggregate[:edges]  += 1 if e.is_a?(Sketchup::Edge)
              aggregate[:faces]  += 1 if e.is_a?(Sketchup::Face)
              aggregate[:curves] += 1 if e.is_a?(Sketchup::Curve)
            else
              loose << e
            end
          end
        end

        nodes = []
        containers.each do |e|
          node = build_container_node(e, parent_world, parent_pid, depth)
          nodes << node if node
        end
        loose.each do |e|
          node = build_leaf_node(e, parent_pid)
          nodes << node if node
        end

        # One synthetic row summarising raw geometry in this context.
        if @opts[:show_all] && (aggregate[:edges] + aggregate[:faces]) > 0
          geo = geometry_node(aggregate, parent_pid)
          nodes << geo if geo
        end

        sort_nodes(nodes)
      end

      def build_container_node(e, parent_world, parent_pid, depth)
        pid   = pid_for(e)
        world = parent_world * e.transformation
        @entity_map[pid] = e
        @world_map[pid]  = world
        @parent_map[pid] = parent_pid

        facts = facts_for(e)
        expanded = @searching || @expanded.include?(pid)

        children = nil
        if expanded
          children = build_children(child_entities(e), world, pid, depth + 1)
        end

        node = base_node(e, pid, facts)
        node[:expandable] = true
        node[:expanded]   = expanded
        node[:children]   = children

        if @searching
          self_match = matches?(facts, e)
          kids       = children || []
          return nil unless self_match || !kids.empty?
        end
        node
      end

      def build_leaf_node(e, parent_pid)
        pid = pid_for(e)
        @entity_map[pid] = e
        @parent_map[pid] = parent_pid
        facts = facts_for(e)
        return nil if @searching && !matches?(facts, e)

        node = base_node(e, pid, facts)
        node[:expandable] = false
        node[:selectable] = true
        node
      end

      def geometry_node(agg, parent_pid)
        bits = []
        bits << "#{agg[:edges]} edges"  if agg[:edges] > 0
        bits << "#{agg[:faces]} faces"  if agg[:faces] > 0
        name = bits.join(", ")
        return nil if @searching && !name.downcase.include?(query.downcase)
        {
          id: "geo:#{parent_pid || 'root'}",
          name: name,
          type: "geometry", typeLabel: "geo",
          color: color_for(type: "geometry"),
          badges: [], locked: false, hidden: false, tag: nil,
          expandable: false, expanded: false, selectable: false
        }
      end

      def base_node(e, pid, facts)
        badges = []
        badges << "lock"          if facts[:locked]
        badges << "hidden"        if facts[:hidden]
        badges << "dyn"           if facts[:dynamic]
        badges << "x#{facts[:count]}" if facts[:count] && facts[:count] > 1
        {
          id: pid,
          name: facts[:name],
          type: facts[:type],
          typeLabel: TYPE_LABELS[facts[:type]] || "?",
          color: color_for(facts),
          badges: badges,
          count: facts[:count],
          locked: facts[:locked],
          hidden: facts[:hidden],
          tag: facts[:tag_name],
          tagColor: facts[:tag_color],
          selectable: true
        }
      end

      # ---- facts -------------------------------------------------------------

      def facts_for(e)
        type = classify(e)
        {
          type: type,
          name: name_for(e, type),
          tag_name: tag_name(e),
          tag_color: tag_color(e),
          locked: (e.respond_to?(:locked?) && e.locked?),
          hidden: (e.respond_to?(:hidden?) && e.hidden?),
          unique: unique?(e),
          count: instance_count(e),
          has_material: has_material?(e),
          dynamic: dynamic?(e)
        }
      end

      def classify(e)
        case e
        when Sketchup::Group             then "group"
        when Sketchup::ComponentInstance then "component"
        when Sketchup::Image             then "image"
        when Sketchup::SectionPlane      then "section"
        when Sketchup::Text              then "text"
        when Sketchup::Edge, Sketchup::Face, Sketchup::Curve then "geometry"
        else
          # Dimensions live under Sketchup::Dimension (2014+); guard for safety.
          return "dimension" if defined?(Sketchup::Dimension) && e.is_a?(Sketchup::Dimension)
          return "guide" if e.is_a?(Sketchup::ConstructionLine) || e.is_a?(Sketchup::ConstructionPoint)
          "other"
        end
      end

      def name_for(e, type)
        case type
        when "group"
          n = e.name.to_s.strip
          n.empty? ? "Group" : n
        when "component"
          n = e.name.to_s.strip
          n.empty? ? e.definition.name : n
        when "image"     then "Image"
        when "section"   then (e.respond_to?(:name) && !e.name.to_s.empty? ? e.name : "Section Plane")
        when "text"      then "Text"
        when "dimension" then "Dimension"
        when "guide"     then "Guide"
        else e.class.name.split("::").last
        end
      end

      def container?(e)
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      def child_entities(e)
        e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
      end

      def tag_name(e)
        return nil unless e.respond_to?(:layer) && e.layer
        n = e.layer.name
        default_tag?(n) ? nil : n
      end

      def tag_color(e)
        return nil unless e.respond_to?(:layer) && e.layer
        return nil if default_tag?(e.layer.name)
        return nil unless e.layer.respond_to?(:color)
        c = e.layer.color
        format("#%02X%02X%02X", c.red, c.green, c.blue)
      rescue StandardError
        nil
      end

      def default_tag?(name)
        name == "Layer0" || name == "Untagged"
      end

      def unique?(e)
        (instance_count(e) || 0) <= 1
      end

      def instance_count(e)
        return nil unless container?(e)
        defn = e.is_a?(Sketchup::Group) ? e.definition : e.definition
        defn ? defn.instances.length : nil
      rescue StandardError
        nil
      end

      def has_material?(e)
        e.respond_to?(:material) && !e.material.nil?
      rescue StandardError
        false
      end

      def dynamic?(e)
        return false unless e.respond_to?(:attribute_dictionary)
        !e.attribute_dictionary("dynamic_attributes").nil?
      rescue StandardError
        false
      end

      def color_for(facts)
        ColorRules.color_for(facts, @opts[:scheme], @opts[:custom_rules] || [])
      end

      # ---- search / filter ---------------------------------------------------

      def searching?(opts)
        q = opts[:query].to_s.strip
        f = opts[:filters] || {}
        !q.empty? || f.any? { |_, v| !v.nil? && v.to_s != "" && v != "any" }
      end

      def query
        @opts[:query].to_s.strip
      end

      def matches?(facts, _e)
        q = query
        unless q.empty?
          return false unless facts[:name].to_s.downcase.include?(q.downcase)
        end
        f = @opts[:filters] || {}
        return false if f["type"] && f["type"] != "any" && facts[:type] != f["type"]
        return false if f["tag"]  && f["tag"]  != "any" && facts[:tag_name] != f["tag"]
        return false if f["locked"] == "true" && !facts[:locked]
        return false if f["hidden"] == "true" && !facts[:hidden]
        return false if f["material"] == "none" && facts[:has_material]
        true
      end

      # ---- sorting -----------------------------------------------------------

      def sort_nodes(nodes)
        case @opts[:sort]
        when "name"  then nodes.sort_by { |n| n[:name].to_s.downcase }
        when "type"  then nodes.sort_by { |n| [n[:type], n[:name].to_s.downcase] }
        when "count" then nodes.sort_by { |n| -(n[:count] || 0) }
        else nodes # model order
        end
      end

      # ---- ids ---------------------------------------------------------------

      def pid_for(e)
        pid = (e.respond_to?(:persistent_id) ? e.persistent_id : 0)
        pid = e.entityID if pid.nil? || pid.zero?
        pid.to_s
      end

      def to_set(list)
        require "set"
        s = Set.new
        Array(list).each { |x| s << x.to_s }
        s
      end
    end
  end
end
