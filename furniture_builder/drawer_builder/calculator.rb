# frozen_string_literal: true

# Single unit-agnostic drawer dimension calculator. It contains no SketchUp API
# calls and returns values in exactly the same unit supplied by the caller.

require_relative 'specification'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module Calculator
          SUPPORTED_STRATEGIES = %w[clearance legacy_clearance].freeze

          class CalculationError < ArgumentError
            attr_reader :code, :field

            def initialize(code, field, message)
              @code = code
              @field = field
              super(message)
            end
          end

          module_function

          def calculate(specification = nil, opening: nil, slides: nil)
            if specification
              unless specification.is_a?(DrawerBuilder::Specification)
                specification = DrawerBuilder::Specification.from_h(specification)
              end
              specification.validate!
              opening = specification.opening
              slides = specification.slides
            end
            raise_error(:missing_opening, :opening, 'Drawer opening specification is required.') unless opening
            raise_error(:missing_slides, :slides, 'Drawer slide specification is required.') unless slides

            strategy = text_value(slides, :calculation_strategy)
            unless SUPPORTED_STRATEGIES.include?(strategy)
              raise_error(
                :unsupported_strategy,
                :calculation_strategy,
                "Drawer slide calculation strategy is not supported: #{strategy}"
              )
            end

            opening_width = required_positive(opening, :opening_width)
            opening_height = required_positive(opening, :opening_height)
            opening_depth = required_positive(opening, :opening_depth)
            left_clearance = required_nonnegative(slides, :left_clearance)
            right_clearance = required_nonnegative(slides, :right_clearance)
            top_clearance = required_nonnegative(slides, :top_clearance)
            bottom_clearance = required_nonnegative(slides, :bottom_clearance)
            front_setback = required_nonnegative(slides, :front_setback)
            rear_clearance = required_nonnegative(slides, :rear_clearance)
            slide_thickness = required_positive(slides, :slide_thickness)

            result = {
              calculation_strategy: strategy,
              opening_width: opening_width,
              opening_height: opening_height,
              opening_depth: opening_depth,
              left_clearance: left_clearance,
              right_clearance: right_clearance,
              top_clearance: top_clearance,
              bottom_clearance: bottom_clearance,
              front_setback: front_setback,
              rear_clearance: rear_clearance,
              slide_thickness: slide_thickness,
              box_width: opening_width - left_clearance - right_clearance,
              box_height: opening_height - top_clearance - bottom_clearance,
              box_depth: opening_depth - front_setback - rear_clearance
            }
            validate_result(result, :box_width)
            validate_result(result, :box_height)
            validate_result(result, :box_depth)
            result.freeze
          end

          def validate_result(result, field)
            return if result[field].positive? && result[field].finite?

            raise_error(
              "invalid_#{field}".to_sym,
              field,
              "Calculated #{field} must be greater than zero."
            )
          end

          def required_positive(values, field)
            number = numeric_value(values, field)
            unless number && number.positive?
              raise_error(:invalid_input_dimension, field, "#{field} must be greater than zero.")
            end
            number
          end

          def required_nonnegative(values, field)
            number = numeric_value(values, field)
            unless number && !number.negative?
              raise_error(:invalid_clearance, field, "#{field} must not be negative.")
            end
            number
          end

          def numeric_value(values, field)
            raw = value_for(values, field)
            return nil if raw.nil? || raw.to_s.strip.empty?

            number = Float(raw)
            number.finite? ? number : nil
          rescue ArgumentError, TypeError
            nil
          end

          def text_value(values, field)
            value_for(values, field).to_s
          end

          def value_for(values, key)
            return nil unless values.respond_to?(:[])
            return values[key] if values.respond_to?(:key?) && values.key?(key)
            return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

            nil
          end

          def raise_error(code, field, message)
            raise CalculationError.new(code, field, message)
          end
        end
      end
    end
  end
end
