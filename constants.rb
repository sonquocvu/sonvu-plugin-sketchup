# frozen_string_literal: true

# Shared constants for SonVu CNC Plugins. Feature modules should reference these
# names instead of duplicating display strings or plugin identifiers.

module SonVu
  module CNCPlugins
    PLUGIN_ID = 'sonvu_cnc_plugins' unless const_defined?(:PLUGIN_ID, false)
    PLUGIN_NAME = 'SonVu CNC Plugins' unless const_defined?(:PLUGIN_NAME, false)
    MENU_DOGBONE_JOINERY = 'Dogbone Joinery'
    MENU_OPEN = 'Open'
    COMMON_CUTTER_DIAMETERS_MM = [3, 4, 6, 8].freeze
    COMMON_BOARD_THICKNESS_MM = [17, 18, 25].freeze
    DOGBONE_PRESETS = {
      'Custom' => {},
      'MDF 17mm / cutter 6mm' => {
        mortise_depth_mm: 17,
        tenon_length_mm: 17,
        cutter_diameter_mm: 6
      },
      'MDF 18mm / cutter 6mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 18,
        cutter_diameter_mm: 6
      },
      'Plywood 18mm / cutter 4mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 18,
        cutter_diameter_mm: 4
      }
    }.freeze
  end
end
