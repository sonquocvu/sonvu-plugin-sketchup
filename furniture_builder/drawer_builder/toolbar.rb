# frozen_string_literal: true

# Reload-safe SketchUp toolbar registration for the existing drawer commands.
# Command construction, validation, licensing, and execution remain in Commands;
# this module only arranges those same UI::Command instances on one toolbar.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module Toolbar
          TOOLBAR_NAME = 'Ngăn kéo'
          ASSIGNMENT_ROLES = %i[
            drawer_opening drawer_slide_left drawer_slide_right drawer_box
          ].freeze

          module_function

          def register
            return @toolbar if @registered

            toolbar = UI::Toolbar.new(TOOLBAR_NAME)
            ASSIGNMENT_ROLES.each { |role| toolbar.add_item(Commands.role_command(role)) }
            toolbar.add_separator
            toolbar.add_item(Commands.edit_specification_command)
            toolbar.add_item(Commands.unassign_command)
            toolbar.restore

            @toolbar = toolbar
            @registered = true
            toolbar
          end

          def registered?
            @registered == true
          end

          def toolbar
            @toolbar
          end
        end
      end
    end
  end
end
