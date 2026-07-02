# frozen_string_literal: true

# SketchUp command and menu registration for the Dogbone Joinery feature. This
# file wires the feature into Extensions > SonVu CNC Plugins > Dogbone Joinery.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Commands
        module_function

        def register_menu
          return if @menu_registered

          root_menu = UI.menu('Extensions').add_submenu(CNCPlugins::PLUGIN_NAME)
          dogbone_menu = root_menu.add_submenu(CNCPlugins::MENU_DOGBONE_JOINERY)
          dogbone_menu.add_item(CNCPlugins::MENU_OPEN) { open_dialog }

          @menu_registered = true
        end

        def open_dialog
          selected_face = selected_placement_face
          return if selected_face == false

          params = DogboneJoinery::Dialog.show
          return unless params
          return unless params[:create_mortise] || params[:create_tenon]

          Sketchup.active_model.select_tool(DogboneJoinery::PlacementTool.new(params, selected_face))
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Unable to create Dogbone templates:\n#{e.message}")
        end

        def selected_placement_face
          faces = Sketchup.active_model.selection.grep(Sketchup::Face)
          return nil if faces.empty?
          return faces.first if faces.length == 1

          CNCPlugins::UIHelpers.message('Please select only one face for placement.')
          false
        end
      end
    end
  end
end
