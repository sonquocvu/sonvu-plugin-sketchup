# frozen_string_literal: true

# Vietnamese furniture presets. All dimensions are millimetres so this file
# remains usable by the SketchUp-free regression suite.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Presets
        CUSTOM_KEY = 'tuy_chinh'
        DEFAULT_KEY = 'tu_bep_duoi'
        GRAIN_AUTOMATIC = 'Tự động theo chi tiết'
        GRAIN_VERTICAL = 'Theo chiều cao tủ'
        GRAIN_HORIZONTAL = 'Theo chiều rộng tủ'
        GRAIN_OPTIONS = [GRAIN_AUTOMATIC, GRAIN_VERTICAL, GRAIN_HORIZONTAL].freeze
        FRONT_NONE = 'khong_canh'
        FRONT_SINGLE_DOOR = 'mot_canh'
        FRONT_DOUBLE_DOOR = 'hai_canh'
        FRONT_TOP_DRAWER_DOUBLE_DOOR = 'mot_ngan_keo_hai_canh'
        FRONT_TWO_DRAWERS = 'hai_ngan_keo'
        FRONT_THREE_DRAWERS = 'ba_ngan_keo'
        FRONT_FOUR_DRAWERS = 'bon_ngan_keo'
        FRONT_FLAP = 'canh_lat'
        FRONT_LAYOUTS = {
          FRONT_NONE => 'Không cánh',
          FRONT_SINGLE_DOOR => 'Một cánh mở',
          FRONT_DOUBLE_DOOR => 'Hai cánh mở',
          FRONT_TOP_DRAWER_DOUBLE_DOOR => 'Một ngăn kéo trên + hai cánh dưới',
          FRONT_TWO_DRAWERS => 'Hai ngăn kéo',
          FRONT_THREE_DRAWERS => 'Ba ngăn kéo',
          FRONT_FOUR_DRAWERS => 'Bốn ngăn kéo',
          FRONT_FLAP => 'Cánh lật cho kệ tivi'
        }.freeze
        DRAWER_FRONT_LAYOUTS = [
          FRONT_TOP_DRAWER_DOUBLE_DOOR,
          FRONT_TWO_DRAWERS,
          FRONT_THREE_DRAWERS,
          FRONT_FOUR_DRAWERS
        ].freeze
        COVER_OVERLAY = 'Phủ ngoài'
        COVER_INSET = 'Lọt lòng'
        COVER_OPTIONS = [COVER_OVERLAY, COVER_INSET].freeze
        DEFAULT_FRONT_SETTINGS = {
          front_layout: FRONT_NONE,
          front_cover_mode: COVER_OVERLAY,
          front_thickness_mm: 18,
          front_gap_mm: 2,
          top_drawer_height_mm: 160,
          front_material_name: 'MDF 18 mm - Mặt cánh',
          front_grain_mode: GRAIN_AUTOMATIC,
          front_edge_band_all: true
        }.freeze
        DEFAULT_DRAWER_SETTINGS = {
          include_drawer_boxes: false,
          drawer_side_clearance_mm: 12.5,
          drawer_box_depth_mm: 0,
          drawer_box_height_mm: 120,
          drawer_panel_thickness_mm: 15,
          drawer_bottom_thickness_mm: 6,
          drawer_front_setback_mm: 20,
          drawer_rear_clearance_mm: 20,
          drawer_material_name: 'MDF 15 mm - Hộp ngăn kéo'
        }.freeze
        DEFAULT_HARDWARE_SETTINGS = {
          include_handles: false,
          handle_length_mm: 128,
          handle_width_mm: 12,
          handle_projection_mm: 25,
          handle_edge_offset_mm: 50,
          include_hinges: false,
          hinge_count: 0,
          hinge_cup_diameter_mm: 35,
          hinge_cup_depth_mm: 12,
          hinge_edge_offset_mm: 22,
          hinge_end_offset_mm: 100,
          include_drawer_slides: false,
          drawer_slide_length_mm: 0,
          drawer_slide_height_mm: 45,
          drawer_slide_thickness_mm: 12.5,
          hardware_material_name: 'Phụ kiện kim khí'
        }.freeze

        ITEMS = {
          CUSTOM_KEY => {
            label: 'Tùy chỉnh',
            cabinet_name: 'Tủ nội thất',
            width_mm: 800,
            height_mm: 720,
            depth_mm: 500,
            panel_thickness_mm: 18,
            back_thickness_mm: 9,
            shelf_count: 1,
            divider_count: 0,
            plinth_height_mm: 0,
            plinth_setback_mm: 50,
            include_back: true,
            edge_band_front: true,
            material_name: 'Gỗ công nghiệp',
            grain_mode: GRAIN_AUTOMATIC
          }.merge(DEFAULT_FRONT_SETTINGS).merge(DEFAULT_DRAWER_SETTINGS).merge(DEFAULT_HARDWARE_SETTINGS),
          'tu_bep_duoi' => {
            label: 'Tủ bếp dưới',
            cabinet_name: 'Tủ bếp dưới',
            width_mm: 800,
            height_mm: 720,
            depth_mm: 580,
            panel_thickness_mm: 18,
            back_thickness_mm: 9,
            shelf_count: 1,
            divider_count: 0,
            plinth_height_mm: 100,
            plinth_setback_mm: 50,
            include_back: true,
            edge_band_front: true,
            material_name: 'MDF 18 mm',
            grain_mode: GRAIN_AUTOMATIC
          }.merge(DEFAULT_FRONT_SETTINGS).merge(DEFAULT_DRAWER_SETTINGS).merge(DEFAULT_HARDWARE_SETTINGS).merge(
            front_layout: FRONT_TOP_DRAWER_DOUBLE_DOOR,
            include_drawer_boxes: true,
            include_handles: true,
            include_hinges: true,
            include_drawer_slides: true
          ),
          'tu_bep_treo' => {
            label: 'Tủ bếp treo',
            cabinet_name: 'Tủ bếp treo',
            width_mm: 800,
            height_mm: 720,
            depth_mm: 350,
            panel_thickness_mm: 18,
            back_thickness_mm: 9,
            shelf_count: 2,
            divider_count: 0,
            plinth_height_mm: 0,
            plinth_setback_mm: 0,
            include_back: true,
            edge_band_front: true,
            material_name: 'MDF 18 mm',
            grain_mode: GRAIN_AUTOMATIC
          }.merge(DEFAULT_FRONT_SETTINGS).merge(DEFAULT_DRAWER_SETTINGS).merge(DEFAULT_HARDWARE_SETTINGS).merge(
            front_layout: FRONT_DOUBLE_DOOR,
            include_handles: true,
            include_hinges: true
          ),
          'tu_ao' => {
            label: 'Tủ áo',
            cabinet_name: 'Tủ áo',
            width_mm: 1200,
            height_mm: 2400,
            depth_mm: 600,
            panel_thickness_mm: 18,
            back_thickness_mm: 9,
            shelf_count: 4,
            divider_count: 1,
            plinth_height_mm: 80,
            plinth_setback_mm: 50,
            include_back: true,
            edge_band_front: true,
            material_name: 'MDF 18 mm',
            grain_mode: GRAIN_AUTOMATIC
          }.merge(DEFAULT_FRONT_SETTINGS).merge(DEFAULT_DRAWER_SETTINGS).merge(DEFAULT_HARDWARE_SETTINGS).merge(
            front_layout: FRONT_DOUBLE_DOOR,
            include_handles: true,
            include_hinges: true
          ),
          'ke_tivi' => {
            label: 'Kệ tivi',
            cabinet_name: 'Kệ tivi',
            width_mm: 1800,
            height_mm: 450,
            depth_mm: 400,
            panel_thickness_mm: 18,
            back_thickness_mm: 9,
            shelf_count: 1,
            divider_count: 2,
            plinth_height_mm: 0,
            plinth_setback_mm: 0,
            include_back: true,
            edge_band_front: true,
            material_name: 'MDF 18 mm',
            grain_mode: GRAIN_AUTOMATIC
          }.merge(DEFAULT_FRONT_SETTINGS).merge(DEFAULT_DRAWER_SETTINGS).merge(DEFAULT_HARDWARE_SETTINGS).merge(
            front_layout: FRONT_FLAP,
            include_handles: true,
            include_hinges: true
          )
        }.freeze

        module_function

        def fetch(key)
          ITEMS.fetch(key.to_s, ITEMS.fetch(DEFAULT_KEY))
        end

        def valid_key?(key)
          ITEMS.key?(key.to_s)
        end

        def options
          ITEMS.map { |key, values| [key, values.fetch(:label)] }
        end
      end
    end
  end
end
