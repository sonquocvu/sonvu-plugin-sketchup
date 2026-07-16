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
require_relative 'dogbone_joinery/automatic_planning/loader'
require_relative 'dogbone_joinery/automatic_execution/loader'
require_relative 'furniture_builder/drawer_builder/slide_configurations'
require_relative 'furniture_builder/drawer_builder/specification'
require_relative 'furniture_builder/drawer_builder/calculator'
require_relative 'furniture_builder/drawer_builder/identity'
require_relative 'furniture_builder/drawer_builder/metadata'
require_relative 'furniture_builder/drawer_builder/persistence'
require_relative 'furniture_builder/drawer_builder/legacy_adapter'
require_relative 'furniture_builder/drawer_builder/selection_validator'
require_relative 'furniture_builder/drawer_builder/system_registry'
require_relative 'furniture_builder/drawer_builder/role_assignment'
require_relative 'furniture_builder/drawer_builder/specification_owner'
require_relative 'furniture_builder/drawer_builder/specification_editor_presenter'
require_relative 'furniture_builder/drawer_builder/specification_editor_parser'
require_relative 'furniture_builder/drawer_builder/specification_editor'
require_relative 'furniture_builder/drawer_builder/command_messages'
require_relative 'furniture_builder/drawer_builder/system_picker'
require_relative 'furniture_builder/drawer_builder/toolbar'
require_relative 'furniture_builder/drawer_builder/commands'
require_relative 'furniture_builder/presets'
require_relative 'furniture_builder/specification'
require_relative 'furniture_builder/dialog_html'
require_relative 'furniture_builder/dialog'
require_relative 'furniture_builder/geometry'
require_relative 'furniture_builder/cut_list'
require_relative 'furniture_builder/cut_list_csv_exporter'
require_relative 'furniture_builder/sheet_optimizer'
require_relative 'furniture_builder/sheet_layout_svg'
require_relative 'furniture_builder/sheet_layout_exporter'
require_relative 'furniture_builder/sheet_optimization_dialog_html'
require_relative 'furniture_builder/sheet_optimization_dialog'
require_relative 'furniture_builder/cost_estimator'
require_relative 'furniture_builder/cost_estimate_csv_exporter'
require_relative 'furniture_builder/cost_estimate_dialog_html'
require_relative 'furniture_builder/cost_estimate_dialog'
require_relative 'furniture_builder/cut_list_dialog_html'
require_relative 'furniture_builder/cut_list_dialog'
require_relative 'furniture_builder/machining_rules'
require_relative 'furniture_builder/machining_planner'
require_relative 'furniture_builder/machining_exporter'
require_relative 'furniture_builder/machining_preview_html'
require_relative 'furniture_builder/machining_preview_dialog'
require_relative 'furniture_builder/dashboard_state'
require_relative 'furniture_builder/dashboard_html'
require_relative 'furniture_builder/dashboard'
require_relative 'furniture_builder/tool'
require_relative 'furniture_builder/commands'

module SonVu
  module CNCPlugins
    def self.load_extension
      Licensing::Manager.start_trial
      root_menu = extension_menu
      Licensing::Commands.register_menu(root_menu)
      FurnitureBuilder::Commands.register_menu(root_menu)
      DogboneJoinery::Commands.register_menu(root_menu)
      FurnitureBuilder::DrawerBuilder::Commands.register_menu(root_menu)
    end

    def self.extension_menu
      @extension_menu ||= UI.menu('Extensions').add_submenu(PLUGIN_NAME)
    end
  end
end

SonVu::CNCPlugins.load_extension
