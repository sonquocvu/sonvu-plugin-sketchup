# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../slide_configurations'
require_relative '../specification'
require_relative '../calculator'
require_relative '../../presets'
require_relative '../../specification'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class CalculatorTest < Minitest::Test
          def test_symmetric_side_clearance
            result = calculate(opening_width: 600, left_clearance: 12.5, right_clearance: 12.5)

            assert_equal 575.0, result[:box_width]
          end

          def test_asymmetric_side_clearance
            result = calculate(opening_width: 600, left_clearance: 10, right_clearance: 15)

            assert_equal 575.0, result[:box_width]
            assert_equal 10.0, result[:left_clearance]
            assert_equal 15.0, result[:right_clearance]
          end

          def test_height_calculation
            result = calculate(opening_height: 200, top_clearance: 12, bottom_clearance: 8)

            assert_equal 180.0, result[:box_height]
          end

          def test_depth_calculation
            result = calculate(opening_depth: 550, front_setback: 20, rear_clearance: 30)

            assert_equal 500.0, result[:box_depth]
          end

          def test_invalid_width_result_has_structured_error
            error = assert_raises(Calculator::CalculationError) do
              calculate(opening_width: 20, left_clearance: 10, right_clearance: 10)
            end

            assert_equal :invalid_box_width, error.code
            assert_equal :box_width, error.field
          end

          def test_invalid_height_result_has_structured_error
            error = assert_raises(Calculator::CalculationError) do
              calculate(opening_height: 10, top_clearance: 5, bottom_clearance: 5)
            end

            assert_equal :invalid_box_height, error.code
            assert_equal :box_height, error.field
          end

          def test_invalid_depth_result_has_structured_error
            error = assert_raises(Calculator::CalculationError) do
              calculate(opening_depth: 30, front_setback: 20, rear_clearance: 10)
            end

            assert_equal :invalid_box_depth, error.code
            assert_equal :box_depth, error.field
          end

          def test_invalid_slide_thickness_is_rejected
            slides = SlideConfigurations.resolve(
              type: 'custom',
              overrides: slide_values.merge(slide_thickness: 0)
            )
            error = assert_raises(Calculator::CalculationError) do
              Calculator.calculate(opening: opening_values, slides: slides)
            end

            assert_equal :invalid_input_dimension, error.code
            assert_equal :slide_thickness, error.field
          end

          def test_custom_slide_configuration_uses_explicit_values
            slides = SlideConfigurations.resolve(
              type: 'custom',
              overrides: slide_values.merge(left_clearance: 9, right_clearance: 16)
            )
            result = Calculator.calculate(opening: opening_values, slides: slides)

            assert_equal 575.0, result[:box_width]
            assert_equal 9.0, result[:left_clearance]
            assert_equal 16.0, result[:right_clearance]
          end

          def test_unresolved_specialized_slide_type_is_not_forced_into_clearance_formula
            slides = SlideConfigurations.resolve(type: 'undermount')
            error = assert_raises(Calculator::CalculationError) do
              Calculator.calculate(opening: opening_values, slides: slides)
            end

            assert_equal :unsupported_strategy, error.code
          end

          def test_calculator_accepts_complete_specification_value_object
            specification = DrawerBuilder::Specification.new(
              opening: opening_values,
              slides: SlideConfigurations.resolve(type: 'custom', overrides: slide_values)
            )
            result = Calculator.calculate(specification)

            assert_equal 575.0, result[:box_width]
            assert_equal 171.0, result[:box_height]
            assert_equal 470.0, result[:box_depth]
          end

          def test_legacy_base_cabinet_uses_real_rules_and_preserves_exact_outputs
            settings = FurnitureBuilder::Specification.defaults('tu_bep_duoi')
            result = FurnitureBuilder::Specification.drawer_dimensions(settings)
            parts = FurnitureBuilder::Specification.parts(settings)
            left = parts.find { |part| part.role == 'drawer_side_left' }
            right = parts.find { |part| part.role == 'drawer_side_right' }
            internal_left = settings[:panel_thickness_mm]
            internal_right = settings[:width_mm] - settings[:panel_thickness_mm]

            assert_equal 'legacy_clearance', result[:calculation_strategy]
            assert_in_delta 531.0, result[:box_depth], 0.001
            assert_in_delta 12.5, result[:left_clearance], 0.001
            assert_in_delta 12.5, result[:right_clearance], 0.001
            assert_in_delta 531.0, left.size_y, 0.001
            assert_in_delta 12.5, left.x - internal_left, 0.001
            assert_in_delta 12.5, internal_right - (right.x + right.size_x), 0.001
          end

          def test_legacy_manual_depth_still_overrides_automatic_depth
            settings = FurnitureBuilder::Specification.defaults('tu_bep_duoi').merge(
              drawer_box_depth_mm: 450
            )

            assert_in_delta 450.0,
                            FurnitureBuilder::Specification.drawer_dimensions(settings)[:box_depth],
                            0.001
          end

          private

          def calculate(overrides = {})
            opening_keys = %i[opening_width opening_height opening_depth]
            slide_keys = %i[
              left_clearance right_clearance top_clearance bottom_clearance
              front_setback rear_clearance
            ]
            opening_overrides = overrides.select { |key, _value| opening_keys.include?(key) }
            slide_overrides = overrides.select { |key, _value| slide_keys.include?(key) }
            slides = SlideConfigurations.resolve(
              type: 'custom',
              overrides: slide_values.merge(slide_overrides)
            )
            Calculator.calculate(opening: opening_values.merge(opening_overrides), slides: slides)
          end

          def opening_values
            {
              opening_width: 600,
              opening_height: 180,
              opening_depth: 500
            }
          end

          def slide_values
            {
              left_clearance: 12.5,
              right_clearance: 12.5,
              top_clearance: 5,
              bottom_clearance: 4,
              front_setback: 20,
              rear_clearance: 10,
              slide_thickness: 12.5
            }
          end
        end
      end
    end
  end
end
