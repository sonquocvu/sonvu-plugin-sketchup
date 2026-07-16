# frozen_string_literal: true

# Main entry point for the SonVu CNC Plugins extension. It loads shared helpers,
# feature modules, and registers SketchUp menus for enabled extension features.

require 'sketchup.rb'

Sketchup.require 'sonvu_cnc_plugins/version'
Sketchup.require 'sonvu_cnc_plugins/constants'
Sketchup.require 'sonvu_cnc_plugins/shared/units'
Sketchup.require 'sonvu_cnc_plugins/shared/ui_helpers'
Sketchup.require 'sonvu_cnc_plugins/shared/materials'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/config'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/device_identity'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/license_token'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/license_client'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/manager'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/dialog'
Sketchup.require 'sonvu_cnc_plugins/shared/licensing/commands'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/commands'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/dialog_html'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/dialog'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/geometry'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/tool'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/loader'
Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/loader'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/slide_configurations'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/specification'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/calculator'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/identity'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/metadata'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/persistence'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/legacy_adapter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/selection_validator'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/system_registry'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/role_assignment'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/specification_owner'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/specification_editor_presenter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/specification_editor_parser'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/specification_editor'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/command_messages'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/system_picker'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/toolbar'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/commands'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/presets'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/specification'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/dialog_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/dialog'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/geometry'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cut_list'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cut_list_csv_exporter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_optimizer'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_layout_svg'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_layout_exporter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_optimization_dialog_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_optimization_dialog'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cost_estimator'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cost_estimate_csv_exporter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cost_estimate_dialog_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cost_estimate_dialog'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cut_list_dialog_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/cut_list_dialog'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_rules'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_planner'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_exporter'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_preview_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_preview_dialog'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/dashboard_state'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/dashboard_html'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/dashboard'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/tool'
Sketchup.require 'sonvu_cnc_plugins/furniture_builder/commands'

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
