# frozen_string_literal: true

# Pure Phase 5B machining-rule presets. Values remain in millimetres and are
# independent from SketchUp and any CNC controller.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module MachiningRules
        DEFAULT_KEY = 'tieu_chuan_18'
        CUSTOM_KEY = 'tuy_chinh'
        BOOLEAN_KEYS = %i[
          include_connectors include_cam_pockets include_shelf_pins include_back_grooves
        ].freeze
        NUMERIC_KEYS = %i[
          dowel_diameter_mm dowel_depth_mm connector_front_offset_mm
          connector_rear_offset_mm cam_diameter_mm cam_depth_mm cam_edge_offset_mm
          shelf_pin_diameter_mm shelf_pin_depth_mm shelf_pin_pitch_mm
          shelf_pin_bottom_margin_mm shelf_pin_top_margin_mm
          shelf_pin_front_offset_mm shelf_pin_rear_offset_mm
          back_groove_width_mm back_groove_depth_mm back_groove_rear_offset_mm
        ].freeze

        BASE = {
          include_connectors: true,
          include_cam_pockets: true,
          dowel_diameter_mm: 8.0,
          dowel_depth_mm: 8.0,
          connector_front_offset_mm: 37.0,
          connector_rear_offset_mm: 37.0,
          cam_diameter_mm: 15.0,
          cam_depth_mm: 12.0,
          cam_edge_offset_mm: 34.0,
          include_shelf_pins: true,
          shelf_pin_diameter_mm: 5.0,
          shelf_pin_depth_mm: 10.0,
          shelf_pin_pitch_mm: 32.0,
          shelf_pin_bottom_margin_mm: 64.0,
          shelf_pin_top_margin_mm: 64.0,
          shelf_pin_front_offset_mm: 37.0,
          shelf_pin_rear_offset_mm: 37.0,
          include_back_grooves: true,
          back_groove_width_mm: 10.0,
          back_groove_depth_mm: 6.0,
          back_groove_rear_offset_mm: 10.0
        }.freeze

        PRESETS = {
          DEFAULT_KEY => BASE.merge(label: 'Tiêu chuẩn ván 18 mm'),
          'chi_chot_go' => BASE.merge(
            label: 'Chỉ chốt gỗ và hàng lỗ',
            include_cam_pockets: false
          ),
          'chi_ban_le' => BASE.merge(
            label: 'Chỉ bản lề hiện có',
            include_connectors: false,
            include_cam_pockets: false,
            include_shelf_pins: false,
            include_back_grooves: false
          ),
          CUSTOM_KEY => BASE.merge(label: 'Tùy chỉnh')
        }.freeze

        module_function

        def defaults(key = DEFAULT_KEY)
          preset = PRESETS.fetch(key.to_s, PRESETS.fetch(DEFAULT_KEY))
          preset.reject { |name, _value| name == :label }.merge(preset_key: key.to_s)
        end

        def normalize(values = {})
          values ||= {}
          key = value_for(values, :preset_key).to_s
          key = DEFAULT_KEY unless PRESETS.key?(key)
          base = defaults(key)
          normalized = base.merge(preset_key: key)
          BOOLEAN_KEYS.each do |name|
            value = value_for(values, name)
            normalized[name] = boolean(value, base[name])
          end
          normalized[:include_cam_pockets] = false unless normalized[:include_connectors]
          NUMERIC_KEYS.each do |name|
            value = value_for(values, name)
            normalized[name] = number(value, base[name])
          end
          error = validate(normalized)
          raise ArgumentError, error if error

          normalized
        end

        def validate(settings)
          return 'Đường kính và chiều sâu khoan chốt gỗ phải lớn hơn 0.' unless positive_pair?(settings, :dowel_diameter_mm, :dowel_depth_mm)
          return 'Khoảng cách lỗ liên kết đến mép không được âm.' if negative_any?(settings, :connector_front_offset_mm, :connector_rear_offset_mm)
          return 'Đường kính và chiều sâu cam phải lớn hơn 0.' unless positive_pair?(settings, :cam_diameter_mm, :cam_depth_mm)
          return 'Khoảng cách tâm cam đến mép phải lớn hơn 0.' unless settings[:cam_edge_offset_mm].to_f.positive?
          return 'Đường kính, chiều sâu và bước hàng lỗ phải lớn hơn 0.' unless positive_all?(settings, :shelf_pin_diameter_mm, :shelf_pin_depth_mm, :shelf_pin_pitch_mm)
          if negative_any?(
            settings, :shelf_pin_bottom_margin_mm, :shelf_pin_top_margin_mm,
            :shelf_pin_front_offset_mm, :shelf_pin_rear_offset_mm
          )
            return 'Khoảng cách hàng lỗ đến mép không được âm.'
          end
          return 'Kích thước và chiều sâu rãnh hậu phải lớn hơn 0.' unless positive_pair?(settings, :back_groove_width_mm, :back_groove_depth_mm)
          return 'Khoảng cách rãnh hậu đến mép không được âm.' if settings[:back_groove_rear_offset_mm].to_f.negative?

          nil
        end

        def options
          PRESETS.map { |key, values| [key, values[:label]] }
        end

        def presets_for_json
          PRESETS.transform_values do |values|
            values.reject { |name, _value| name == :label }.merge(label: values[:label])
          end
        end

        def value_for(values, key)
          return values[key] if values.respond_to?(:key?) && values.key?(key)
          return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

          nil
        end

        def boolean(value, fallback)
          return fallback if value.nil?
          return value if value == true || value == false

          %w[true 1 yes có].include?(value.to_s.downcase)
        end

        def number(value, fallback)
          return fallback.to_f if value.nil? || value.to_s.strip.empty?

          Float(value)
        rescue ArgumentError, TypeError
          raise ArgumentError, 'Thông số gia công phải là số hợp lệ.'
        end

        def positive_pair?(settings, first, second)
          positive_all?(settings, first, second)
        end

        def positive_all?(settings, *keys)
          keys.all? { |key| settings[key].to_f.positive? }
        end

        def negative_any?(settings, *keys)
          keys.any? { |key| settings[key].to_f.negative? }
        end
      end
    end
  end
end
