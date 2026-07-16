# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../slide_configurations'
require_relative '../specification'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SpecificationTest < Minitest::Test
          def test_constructs_valid_independent_sections
            specification = Specification.new(valid_values)

            assert specification.valid?, specification.errors.inspect
            assert_equal 600.0, specification.opening[:opening_width]
            assert_equal 10.0, specification.slides[:left_clearance]
            assert_equal 15.0, specification.slides[:right_clearance]
            assert_equal 15.0, specification.box[:board_thickness]
            assert specification.frozen?
            assert specification.opening.frozen?
          end

          def test_converts_to_plain_hash_and_reconstructs_from_string_key_hash
            original = Specification.new(valid_values)
            plain = original.to_h
            string_values = stringify_keys(plain)
            reconstructed = Specification.from_h(string_values)

            assert_instance_of Hash, plain
            assert_equal plain, reconstructed.to_h
            refute_same plain[:opening], reconstructed.opening
            assert reconstructed.valid?, reconstructed.errors.inspect
          end

          def test_missing_required_opening_dimension_is_reported
            values = valid_values
            values[:opening].delete(:opening_width)
            specification = Specification.new(values)

            refute specification.valid?
            assert_error specification, :missing_field, :opening_width
            assert_raises(Specification::ValidationError) { specification.validate! }
          end

          def test_zero_opening_dimension_is_rejected
            values = valid_values
            values[:opening][:opening_height] = 0
            specification = Specification.new(values)

            refute specification.valid?
            assert_error specification, :nonpositive_dimension, :opening_height
          end

          def test_negative_opening_dimension_is_rejected
            values = valid_values
            values[:opening][:opening_depth] = -1
            specification = Specification.new(values)

            refute specification.valid?
            assert_error specification, :negative_dimension, :opening_depth
          end

          def test_left_and_right_clearances_remain_independent
            specification = Specification.new(valid_values)

            assert_equal 10.0, specification.slides[:left_clearance]
            assert_equal 15.0, specification.slides[:right_clearance]
            refute_equal specification.slides[:left_clearance], specification.slides[:right_clearance]
          end

          def test_optional_placement_metadata_is_opaque_and_preserved
            values = valid_values
            values[:opening][:front_direction] = [1, 0, 0]
            values[:opening][:depth_direction] = [0, 1, 0]
            values[:opening][:local_transformation] = (1..16).to_a
            values[:opening][:source_entity_id] = 42_001
            specification = Specification.new(values)

            assert specification.valid?, specification.errors.inspect
            assert_equal [1, 0, 0], specification.opening[:front_direction]
            assert_equal [0, 1, 0], specification.opening[:depth_direction]
            assert_equal (1..16).to_a, specification.opening[:local_transformation]
            assert_equal 42_001, specification.opening[:source_entity_id]
          end

          def test_custom_slide_configuration_accepts_explicit_values
            configuration = custom_configuration

            assert_equal 'custom', configuration[:slide_type]
            assert_equal 'Ray tùy chỉnh', configuration[:label_vi]
            assert_equal 'clearance', configuration[:calculation_strategy]
            assert_equal 10, configuration[:left_clearance]
            assert_equal 15, configuration[:right_clearance]
            assert_equal 'Xưởng SonVu', configuration[:manufacturer]
          end

          def test_unknown_slide_type_is_rejected
            error = assert_raises(ArgumentError) do
              SlideConfigurations.resolve(type: 'unknown_slide')
            end

            assert_includes error.message, 'Unknown drawer slide type'
          end

          def test_all_initial_slide_types_have_vietnamese_names
            assert_equal(
              {
                'side_mount_ball_bearing' => 'Ray bi hai bên',
                'undermount' => 'Ray âm',
                'box_slide' => 'Ray hộp',
                'wooden_slide' => 'Ray gỗ',
                'custom' => 'Ray tùy chỉnh'
              },
              SlideConfigurations.options.to_h
            )
          end

          def test_slide_and_box_dimensions_apply_positive_validation
            values = valid_values
            values[:slides] = values[:slides].merge(left_clearance: -1, slide_thickness: 0)
            values[:box][:bottom_thickness] = 0
            specification = Specification.new(values)

            refute specification.valid?
            assert_error specification, :negative_dimension, :left_clearance
            assert_error specification, :nonpositive_dimension, :slide_thickness
            assert_error specification, :nonpositive_dimension, :bottom_thickness
          end

          def test_opening_slides_and_box_can_exist_independently
            opening_only = Specification.new(opening: valid_values[:opening])
            slides_only = Specification.new(slides: custom_configuration)
            box_only = Specification.new(box: valid_values[:box])

            assert opening_only.valid?, opening_only.errors.inspect
            assert slides_only.valid?, slides_only.errors.inspect
            assert box_only.valid?, box_only.errors.inspect
          end

          def test_contract_uses_plain_ruby_data_and_no_sketchup_classes
            specification = Specification.new(stringify_keys(valid_values))

            assert specification.valid?, specification.errors.inspect
            assert_instance_of Hash, specification.to_h
            assert_instance_of Array, specification.opening[:local_transformation]
            refute specification.to_h.values.any? { |value| value.class.name.start_with?('Sketchup') }
          end

          private

          def valid_values
            {
              schema_version: 1,
              unit_system: 'millimeters',
              drawer_system_id: 'drawer-system-1',
              source: 'generated',
              opening: {
                object_id: 'opening-1',
                opening_width: 600,
                opening_height: 180,
                opening_depth: 500,
                local_transformation: []
              },
              slides: custom_configuration,
              box: {
                object_id: 'box-1',
                dimension_mode: 'calculated',
                box_width: nil,
                box_height: nil,
                box_depth: nil,
                board_thickness: 15,
                bottom_thickness: 6,
                front_thickness: 15,
                back_thickness: 15,
                material_name: 'MDF 15 mm'
              }
            }
          end

          def custom_configuration
            SlideConfigurations.resolve(
              type: 'custom',
              preset_name: 'Tùy chỉnh xưởng',
              overrides: {
                left_clearance: 10,
                right_clearance: 15,
                top_clearance: 5,
                bottom_clearance: 4,
                front_setback: 20,
                rear_clearance: 10,
                slide_thickness: 10,
                slide_height: 35,
                slide_length: 450,
                minimum_drawer_depth: 300,
                maximum_drawer_depth: 550,
                manufacturer: 'Xưởng SonVu'
              }
            )
          end

          def assert_error(specification, code, field)
            assert specification.errors.any? { |error| error[:code] == code && error[:field] == field },
                   "Expected #{code} for #{field}, got #{specification.errors.inspect}"
          end

          def stringify_keys(value)
            case value
            when Hash
              value.each_with_object({}) do |(key, item), result|
                result[key.to_s] = stringify_keys(item)
              end
            when Array
              value.map { |item| stringify_keys(item) }
            else
              value
            end
          end
        end
      end
    end
  end
end
