# frozen_string_literal: true
#
# Outliner Reforged
# A drop-in replacement for SketchUp's Outliner: everything the native panel
# does, plus deep-nesting rescue, rule-based color coding, an extended
# right-click menu, show-everything, and search/filter.
#
# This is the SketchUp Extension registration stub. Extension Warehouse
# requires a top-level .rb file next to the extension's folder; the real code
# lives in outliner_reforged/.

require "sketchup.rb"
require "extensions.rb"

module UniteIdeas
  module OutlinerReforged
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(
        "Outliner Reforged",
        File.join(File.dirname(__FILE__), "outliner_reforged", "main")
      )
      ex.version     = "1.0.3"
      ex.creator     = "Unite Ideas"
      ex.copyright   = "© #{Time.now.year} Unite Ideas"
      ex.description = "A better SketchUp Outliner: move-to-top-level, " \
                       "color coding, extended context menu, show-everything, " \
                       "and fast search/filter."

      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
