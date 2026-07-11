# frozen_string_literal: true

# Shared constants for SonVu CNC Plugins. Feature modules should reference these
# names instead of duplicating display strings or plugin identifiers.

module SonVu
  module CNCPlugins
    PLUGIN_ID = 'sonvu_cnc_plugins' unless const_defined?(:PLUGIN_ID, false)
    PLUGIN_NAME = 'SonVu CNC Plugins' unless const_defined?(:PLUGIN_NAME, false)
    MENU_DOGBONE_JOINERY = 'Mộng CNC'
    MENU_DELETE_GENERATED_TEMPLATES = 'Xóa mẫu mộng đã tạo'
    TOOLBAR_DOGBONE_JOINERY = 'Mộng CNC'
    COMMAND_CREATE_DOGBONE_MORTISE = 'Tạo mộng âm'
    COMMAND_CREATE_DOGBONE_TENON = 'Tạo mộng dương'
    COMMAND_DELETE_GENERATED_TEMPLATES = 'Xóa mẫu mộng đã tạo'
    ATTRIBUTE_DICTIONARY = 'SonVu_CNC_Plugins'
    GENERATED_GROUP_ATTRIBUTE = 'generated_group'
    COMMON_CUTTER_DIAMETERS_MM = [3, 4, 6, 8].freeze
    COMMON_BOARD_THICKNESS_MM = [17, 18, 25].freeze
    DOGBONE_PRESETS = {
      'Tùy chỉnh' => {},
      'MDF 17mm / dao 6mm' => {
        mortise_depth_mm: 17,
        tenon_length_mm: 34,
        cutter_diameter_mm: 6
      },
      'MDF 18mm / dao 6mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 36,
        cutter_diameter_mm: 6
      },
      'Ván ép 18mm / dao 4mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 36,
        cutter_diameter_mm: 4
      }
    }.freeze
  end
end
