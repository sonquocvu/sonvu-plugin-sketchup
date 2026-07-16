# frozen_string_literal: true

# Shared constants for SonVu CNC Plugins. Feature modules should reference these
# names instead of duplicating display strings or plugin identifiers.

module SonVu
  module CNCPlugins
    PLUGIN_ID = 'sonvu_cnc_plugins' unless const_defined?(:PLUGIN_ID, false)
    PLUGIN_NAME = 'SonVu CNC Plugins' unless const_defined?(:PLUGIN_NAME, false)
    MENU_DOGBONE_JOINERY = 'Mộng CNC'
    MENU_FURNITURE_BUILDER = 'Thiết kế nội thất'
    MENU_DELETE_GENERATED_TEMPLATES = 'Xóa mẫu mộng đã tạo'
    TOOLBAR_DOGBONE_JOINERY = 'Mộng CNC'
    TOOLBAR_FURNITURE_BUILDER = 'SonVu Nội thất'
    COMMAND_CREATE_DOGBONE_MORTISE = 'Tạo mộng âm'
    COMMAND_CREATE_DOGBONE_TENON = 'Tạo mộng dương'
    COMMAND_DELETE_GENERATED_TEMPLATES = 'Xóa mẫu mộng đã tạo'
    COMMAND_LICENSE_MANAGER = 'Quản lý giấy phép'
    COMMAND_CREATE_FURNITURE = 'Tạo tủ nội thất'
    COMMAND_FURNITURE_DASHBOARD = 'Trung tâm nội thất'
    COMMAND_EDIT_FURNITURE = 'Chỉnh sửa tủ đã chọn'
    COMMAND_SHOW_FURNITURE_CUT_LIST = 'Danh sách chi tiết'
    COMMAND_SHOW_FURNITURE_COST_ESTIMATE = 'Dự toán chi phí'
    COMMAND_OPTIMIZE_FURNITURE_SHEETS = 'Tối ưu cắt ván'
    COMMAND_PREVIEW_FURNITURE_MACHINING = 'Xem trước gia công CNC'
    ATTRIBUTE_DICTIONARY = 'SonVu_CNC_Plugins'
    GENERATED_GROUP_ATTRIBUTE = 'generated_group'
    COMMAND_AUTOMATIC_JOINT_PREVIEW = 'Tạo mộng tự động'
    COMMON_CUTTER_RADII_MM = [1.5, 2, 3, 4].freeze
    COMMON_BOARD_THICKNESS_MM = [17, 18, 25].freeze
    DOGBONE_PRESETS = {
      'Tùy chỉnh' => {},
      'MDF 17mm / bán kính dao 3mm' => {
        mortise_depth_mm: 17,
        tenon_length_mm: 34,
        cutter_radius_mm: 3
      },
      'MDF 18mm / bán kính dao 3mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 36,
        cutter_radius_mm: 3
      },
      'Ván ép 18mm / bán kính dao 2mm' => {
        mortise_depth_mm: 18,
        tenon_length_mm: 36,
        cutter_radius_mm: 2
      }
    }.freeze
  end
end
