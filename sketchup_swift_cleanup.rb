# frozen_string_literal: true
#
# Swift Cleanup
# Fast coplanar-face merging for imported CAD/Revit geometry. Collapses the
# triangulated "flat" surfaces that bloat imported models into single faces,
# in one batched pass per component definition — far faster than per-edge
# cleanup, while leaving genuinely curved surfaces untouched.
#
# This is the SketchUp Extension registration stub. Extension Warehouse
# requires a top-level .rb file next to the extension's folder; the real code
# lives in swift_cleanup/.

require "sketchup.rb"
require "extensions.rb"

module UniteIdeas
  module SwiftCleanup
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(
        "Swift Cleanup",
        File.join(File.dirname(__FILE__), "swift_cleanup", "main")
      )
      ex.version     = "0.1.0"
      ex.creator     = "Unite Ideas"
      ex.copyright   = "© #{Time.now.year} Unite Ideas"
      ex.description = "Fast batched coplanar-face merge for imported " \
                       "Revit/CAD geometry. Flattens triangulated flat " \
                       "surfaces, keeps curves, one pass per component."

      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
