# frozen_string_literal: true
#
# Swift Cleanup — menu wiring and user-facing commands.

require "sketchup.rb"
require File.join(File.dirname(__FILE__), "core")

module UniteIdeas
  module SwiftCleanup
    module_function

    # Merge coplanar faces across the whole model, then report what happened.
    def run
      stats = Core.clean_model
      UI.messagebox(summary(stats))
    end

    # Merge coplanar faces only within the current selection's definitions.
    def run_selection
      if Sketchup.active_model.selection.empty?
        UI.messagebox("Select one or more groups/components first.")
        return
      end

      stats = Core.clean_selection
      if stats.nil?
        UI.messagebox("Nothing to clean in the selection.")
        return
      end

      UI.messagebox(summary(stats))
    end

    # Dry run: scan and report, change nothing.
    def report
      data = Core.report_model
      UI.messagebox(
        "Swift Cleanup — preview (no changes made).\n\n" \
        "Components in use:        #{data[:scopes]}\n" \
        "Total faces:             #{data[:faces]}\n" \
        "Total edges:             #{data[:edges]}\n" \
        "Removable coplanar edges: #{data[:removable]}\n" \
        "Estimated faces after:   ~#{data[:faces] - data[:removable]}"
      )
    end

    def summary(stats)
      removed_faces = stats[:faces_before] - stats[:faces_after]
      "Swift Cleanup complete.\n\n" \
        "Components processed: #{stats[:scopes]}\n" \
        "Edges removed:        #{stats[:edges_removed]}\n" \
        "Faces: #{stats[:faces_before]} → #{stats[:faces_after]} " \
        "(−#{removed_faces})\n" \
        "Time:                 #{stats[:seconds].round(1)}s"
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu("Extensions").add_submenu("Swift Cleanup")
      menu.add_item("Merge Coplanar Faces (whole model)") { run }
      menu.add_item("Merge Coplanar Faces (selection only)") { run_selection }
      menu.add_separator
      menu.add_item("Preview — count removable edges") { report }
      file_loaded(__FILE__)
    end
  end
end
