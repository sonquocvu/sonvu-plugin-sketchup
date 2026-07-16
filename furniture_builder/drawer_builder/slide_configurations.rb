# frozen_string_literal: true

# Data-only slide definitions for the standalone drawer contract. Dimensions
# are deliberately unit-agnostic: callers may provide millimetres in pure Ruby
# tests or SketchUp internal lengths in production.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SlideConfigurations
          LEGACY_PRESET_KEY = 'legacy_side_mount_12_5'
          LEGACY_PRESET_NAME = 'Tương thích ngăn kéo SonVu hiện tại'

          TYPE_DEFINITIONS = {
            'side_mount_ball_bearing' => {
              label_vi: 'Ray bi hai bên',
              calculation_strategy: 'clearance'
            },
            'undermount' => {
              label_vi: 'Ray âm',
              calculation_strategy: nil
            },
            'box_slide' => {
              label_vi: 'Ray hộp',
              calculation_strategy: nil
            },
            'wooden_slide' => {
              label_vi: 'Ray gỗ',
              calculation_strategy: nil
            },
            'custom' => {
              label_vi: 'Ray tùy chỉnh',
              calculation_strategy: 'clearance'
            }
          }.freeze

          DIMENSION_KEYS = %i[
            left_clearance
            right_clearance
            top_clearance
            bottom_clearance
            front_setback
            rear_clearance
            slide_thickness
            slide_height
            slide_length
            minimum_drawer_depth
            maximum_drawer_depth
          ].freeze

          OPTIONAL_TEXT_KEYS = %i[manufacturer].freeze

          LEGACY_CONFIGURATION = {
            left_clearance: 12.5,
            right_clearance: 12.5,
            top_clearance: 0.0,
            bottom_clearance: 0.0,
            front_setback: 20.0,
            rear_clearance: 20.0,
            slide_thickness: 12.5,
            slide_height: 45.0,
            slide_length: nil,
            minimum_drawer_depth: nil,
            maximum_drawer_depth: nil,
            manufacturer: nil
          }.freeze

          module_function

          def resolve(type:, preset_name: nil, overrides: {})
            type_key = type.to_s
            definition = TYPE_DEFINITIONS[type_key]
            raise ArgumentError, "Unknown drawer slide type: #{type_key}" unless definition

            legacy = legacy_preset?(type_key, preset_name)
            values = empty_dimensions
            values.update(LEGACY_CONFIGURATION) if legacy
            apply_overrides(values, overrides || {})
            values.merge(
              slide_type: type_key,
              label_vi: definition[:label_vi],
              calculation_strategy: legacy ? 'legacy_clearance' : definition[:calculation_strategy],
              preset_name: legacy ? LEGACY_PRESET_NAME : normalized_preset_name(preset_name)
            ).freeze
          end

          def options
            TYPE_DEFINITIONS.map { |key, values| [key, values[:label_vi]] }
          end

          def valid_type?(type)
            TYPE_DEFINITIONS.key?(type.to_s)
          end

          def legacy_preset?(type, preset_name)
            return false unless type == 'side_mount_ball_bearing'

            [LEGACY_PRESET_KEY, LEGACY_PRESET_NAME].include?(preset_name.to_s)
          end

          def empty_dimensions
            DIMENSION_KEYS.each_with_object({}) { |key, values| values[key] = nil }
                          .merge(manufacturer: nil)
          end

          def apply_overrides(values, overrides)
            (DIMENSION_KEYS + OPTIONAL_TEXT_KEYS).each do |key|
              next unless hash_key?(overrides, key)

              values[key] = hash_value(overrides, key)
            end
          end

          def normalized_preset_name(value)
            text = value.to_s.strip
            text.empty? ? nil : text
          end

          def hash_key?(values, key)
            values.respond_to?(:key?) && (values.key?(key) || values.key?(key.to_s))
          end

          def hash_value(values, key)
            return values[key] if values.respond_to?(:key?) && values.key?(key)

            values[key.to_s]
          end
        end
      end
    end
  end
end
