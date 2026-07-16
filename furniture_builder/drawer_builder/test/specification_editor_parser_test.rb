# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../identity'
require_relative '../specification_editor_parser'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SpecificationEditorParserTest < Minitest::Test
          def setup
            Units.define_singleton_method(:millimeters_to_model_units) { |value| value.to_f * 2.0 }
            Units.define_singleton_method(:model_units_to_millimeters) { |value| value.to_f / 2.0 }
          end

          def test_integer_dot_and_comma_millimeter_input
            assert_equal 12.0, SpecificationEditorParser.parse_number('12', :left_clearance)
            assert_equal 12.5, SpecificationEditorParser.parse_number('12.5', :left_clearance)
            assert_equal 12.5, SpecificationEditorParser.parse_number('12,5', :left_clearance)
          end

          def test_blank_optional_field_returns_nil
            assert_nil SpecificationEditorParser.optional_number({}, :slide_length)
            assert_nil SpecificationEditorParser.optional_number({ slide_length: '  ' }, :slide_length)
          end

          def test_blank_required_field_is_rejected
            error = assert_raises(SpecificationEditorParser::ParserError) do
              SpecificationEditorParser.required_number({}, :opening_width)
            end

            assert_equal :missing_field, error.code
            assert_equal 'Chiều rộng khoang phải lớn hơn 0.', error.message
          end

          def test_zero_and_negative_positive_dimensions_are_rejected
            zero = assert_raises(SpecificationEditorParser::ParserError) do
              SpecificationEditorParser.positive_number({ box_width: '0' }, :box_width)
            end
            negative = assert_raises(SpecificationEditorParser::ParserError) do
              SpecificationEditorParser.positive_number({ box_width: '-1' }, :box_width)
            end

            assert_equal :nonpositive_dimension, zero.code
            assert_equal :nonpositive_dimension, negative.code
          end

          def test_invalid_nan_and_infinity_are_rejected
            %w[abc NaN Infinity -Infinity].each do |value|
              assert_raises(SpecificationEditorParser::ParserError) do
                SpecificationEditorParser.parse_number(value, :opening_width)
              end
            end
          end

          def test_millimeters_are_converted_with_shared_unit_helper
            specification = parse(opening_only_payload)

            assert_equal 1200.0, specification.opening[:opening_width]
            assert_equal 360.0, specification.opening[:opening_height]
            assert_equal 1000.0, specification.opening[:opening_depth]
            assert_equal 'sketchup_internal', specification.unit_system
          end

          def test_custom_asymmetric_clearances_and_utf8_text_are_preserved
            payload = slide_only_payload
            payload[:slides].merge!(
              left_clearance: '10,5',
              right_clearance: '15.25',
              manufacturer: 'Xưởng ray Sơn Vũ',
              preset_name: 'Mẫu bếp Việt'
            )

            specification = parse(payload)

            assert_equal 21.0, specification.slides[:left_clearance]
            assert_equal 30.5, specification.slides[:right_clearance]
            assert_equal 'Xưởng ray Sơn Vũ', specification.slides[:manufacturer]
            assert_equal 'Mẫu bếp Việt', specification.slides[:preset_name]
          end

          def test_legacy_preset_supplies_exact_12_5_millimeter_values
            payload = slide_only_payload
            payload[:slides] = {
              enabled: true,
              slide_type: 'side_mount_ball_bearing',
              preset_name: SlideConfigurations::LEGACY_PRESET_KEY,
              manufacturer: '',
              left_clearance: '', right_clearance: '', top_clearance: '', bottom_clearance: '',
              front_setback: '', rear_clearance: '', slide_thickness: '', slide_height: '',
              slide_length: '', minimum_drawer_depth: '', maximum_drawer_depth: ''
            }

            specification = parse(payload)

            assert_equal 25.0, specification.slides[:left_clearance]
            assert_equal 25.0, specification.slides[:right_clearance]
            assert_equal 25.0, specification.slides[:slide_thickness]
            assert_equal 'legacy_clearance', specification.slides[:calculation_strategy]
          end

          def test_automatic_box_uses_authoritative_calculator
            payload = complete_payload
            result = SpecificationEditorParser.parse(
              payload,
              drawer_system_id: Identity.generate_system_id
            )

            assert_equal 1150.0, result.specification.box[:box_width]
            assert_equal 350.0, result.specification.box[:box_height]
            assert_equal 940.0, result.specification.box[:box_depth]
          end

          def test_manual_box_can_exceed_opening_with_nonblocking_warning
            payload = opening_only_payload
            payload[:box] = manual_box_payload.merge(box_width: '650')

            result = SpecificationEditorParser.parse(
              payload,
              drawer_system_id: Identity.generate_system_id
            )

            assert_equal 'manual', result.specification.box[:dimension_mode]
            assert_equal ['Kích thước thùng ngăn kéo đang lớn hơn khoang lắp đặt.'], result.warnings
          end

          def test_preview_returns_millimeters_and_does_not_build_persistence
            preview = SpecificationEditorParser.calculate_preview(complete_payload)

            assert_equal 575.0, preview[:box_width]
            assert_equal 175.0, preview[:box_height]
            assert_equal 470.0, preview[:box_depth]
          end

          def test_unsupported_automatic_strategy_has_vietnamese_error
            payload = complete_payload
            payload[:slides][:slide_type] = 'undermount'

            error = assert_raises(SpecificationEditorParser::ParserError) do
              SpecificationEditorParser.calculate_preview(payload)
            end

            assert_equal :unsupported_strategy, error.code
            assert_equal 'Loại ray đã chọn chưa hỗ trợ tính tự động.', error.message
          end

          private

          def parse(payload)
            SpecificationEditorParser.parse(
              payload,
              drawer_system_id: Identity.generate_system_id
            ).specification
          end

          def opening_only_payload
            {
              opening: {
                enabled: true,
                opening_width: '600',
                opening_height: '180',
                opening_depth: '500'
              },
              slides: { enabled: false },
              box: { enabled: false }
            }
          end

          def slide_only_payload
            {
              opening: { enabled: false },
              slides: {
                enabled: true,
                slide_type: 'custom',
                preset_name: '',
                manufacturer: '',
                left_clearance: '12.5',
                right_clearance: '12.5',
                top_clearance: '3',
                bottom_clearance: '2',
                front_setback: '20',
                rear_clearance: '10',
                slide_thickness: '12.5',
                slide_height: '',
                slide_length: '',
                minimum_drawer_depth: '',
                maximum_drawer_depth: ''
              },
              box: { enabled: false }
            }
          end

          def complete_payload
            payload = opening_only_payload
            payload[:slides] = slide_only_payload[:slides]
            payload[:box] = {
              enabled: true,
              dimension_mode: 'calculated',
              box_width: '', box_height: '', box_depth: '',
              board_thickness: '15',
              bottom_thickness: '6',
              front_thickness: '15',
              back_thickness: '15'
            }
            payload
          end

          def manual_box_payload
            {
              enabled: true,
              dimension_mode: 'manual',
              box_width: '575',
              box_height: '170',
              box_depth: '470',
              board_thickness: '15',
              bottom_thickness: '6',
              front_thickness: '15',
              back_thickness: '15'
            }
          end
        end
      end
    end
  end
end
