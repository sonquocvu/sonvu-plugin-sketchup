# frozen_string_literal: true

# Main entry point for the SonVu CNC Plugins extension. It loads shared helpers,
# feature modules, and registers SketchUp menus for enabled extension features.

require 'sketchup.rb'

require_relative 'version'
require_relative 'constants'
require_relative 'shared/units'
require_relative 'shared/ui_helpers'
require_relative 'shared/materials'
require_relative 'shared/licensing/config'
require_relative 'shared/licensing/device_identity'
require_relative 'shared/licensing/license_token'
require_relative 'shared/licensing/license_client'
require_relative 'shared/licensing/manager'
require_relative 'shared/licensing/dialog'
require_relative 'shared/licensing/commands'
require_relative 'dogbone_joinery/commands'
require_relative 'dogbone_joinery/dialog_html'
require_relative 'dogbone_joinery/dialog'
require_relative 'dogbone_joinery/geometry'
require_relative 'dogbone_joinery/tool'

module SonVu
  module CNCPlugins
    def self.load_extension
      root_menu = extension_menu
      Licensing::Commands.register_menu(root_menu)
      DogboneJoinery::Commands.register_menu(root_menu)
    end

    def self.extension_menu
      @extension_menu ||= UI.menu('Extensions').add_submenu(PLUGIN_NAME)
    end
  end
end

SonVu::CNCPlugins.load_extension
