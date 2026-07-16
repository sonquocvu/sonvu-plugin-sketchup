# frozen_string_literal: true

# Resolves every automatic joint's across-board dimensions from the male board
# descriptor. The UI, preview, and executor must not remeasure or override them.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class ResolvedJointDimensions
          FIELDS = [
            :detected_male_board_thickness,
            :joint_length,
            :tenon_thickness,
            :mortise_opening_thickness,
            :fit_clearance,
            :tenon_height,
            :mortise_depth,
            :cutter_radius,
            :thickness_axis,
            :validation
          ].freeze

          attr_reader(*FIELDS)

          def initialize(attributes)
            FIELDS.each { |field| instance_variable_set("@#{field}", attributes[field]) }
            freeze
          end

          def valid?
            validation.valid?
          end

          def to_h
            {
              detected_male_board_thickness: detected_male_board_thickness,
              joint_length: joint_length,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening_thickness,
              fit_clearance: fit_clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis && thickness_axis.to_h,
              validation: validation.to_h
            }
          end
        end

        class JointDimensionResolver
          def resolve(male_board:, female_board:, contact_bounds:, specification:)
            tolerance = positive_tolerance(specification.geometric_tolerance)
            male_thickness = numeric_value(male_board.thickness)
            female_thickness = numeric_value(female_board.thickness)
            joint_length = numeric_value(specification.joint_length)
            clearance = numeric_value(specification.fit_clearance)
            tenon_height = numeric_value(specification.tenon_height)
            mortise_depth = numeric_value(specification.mortise_depth)
            cutter_radius = numeric_value(specification.cutter_radius)
            thickness_axis = contact_bounds.cross_axis.normalized.canonical
            details = {
              male_part_id: male_board.identity.stable_id,
              female_part_id: female_board.identity.stable_id,
              detected_male_board_thickness: male_thickness,
              female_board_thickness: female_thickness,
              contact_opening_limit: contact_bounds.width,
              fit_clearance: clearance
            }

            validation = validation_for(
              male_board: male_board,
              female_board: female_board,
              male_thickness: male_thickness,
              female_thickness: female_thickness,
              joint_length: joint_length,
              clearance: clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              contact_width: contact_bounds.width,
              tolerance: tolerance,
              details: details
            )
            tenon_thickness = if male_thickness && clearance
                                male_thickness - clearance
                              end
            mortise_opening = if tenon_thickness && clearance
                                tenon_thickness + clearance
                              end

            ResolvedJointDimensions.new(
              detected_male_board_thickness: male_thickness,
              joint_length: joint_length,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening,
              fit_clearance: clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis,
              validation: validation
            )
          end

          private

          def validation_for(values)
            if values[:male_board].thickness_ambiguous || values[:male_thickness].nil?
              return invalid(ValidationResult::AMBIGUOUS_BOARD_THICKNESS, values, board_role: 'male')
            end
            unless positive?(values[:male_thickness], values[:tolerance])
              return invalid(ValidationResult::BOARD_THICKNESS_INVALID, values, board_role: 'male')
            end
            if values[:female_board].thickness_ambiguous || values[:female_thickness].nil?
              return invalid(ValidationResult::AMBIGUOUS_BOARD_THICKNESS, values, board_role: 'female')
            end
            unless positive?(values[:female_thickness], values[:tolerance])
              return invalid(ValidationResult::BOARD_THICKNESS_INVALID, values, board_role: 'female')
            end
            unless nonnegative?(values[:clearance])
              return invalid(ValidationResult::TENON_THICKNESS_INVALID, values)
            end
            unless positive?(values[:joint_length], values[:tolerance]) &&
                   values[:joint_length] - values[:clearance] > values[:tolerance]
              return invalid(ValidationResult::JOINT_LENGTH_INVALID, values)
            end

            tenon_thickness = values[:male_thickness] - values[:clearance]
            unless positive?(tenon_thickness, values[:tolerance])
              return invalid(
                ValidationResult::TENON_THICKNESS_INVALID,
                values,
                tenon_thickness: tenon_thickness
              )
            end
            mortise_opening = tenon_thickness + values[:clearance]
            unless positive?(mortise_opening, values[:tolerance]) &&
                   mortise_opening <= values[:contact_width].to_f + values[:tolerance]
              return invalid(
                ValidationResult::MORTISE_OPENING_INVALID,
                values,
                mortise_opening_thickness: mortise_opening
              )
            end
            unless positive?(values[:tenon_height], values[:tolerance])
              return invalid(ValidationResult::TENON_HEIGHT_INVALID, values)
            end
            unless positive?(values[:mortise_depth], values[:tolerance]) &&
                   values[:mortise_depth] <= values[:female_thickness] + values[:tolerance]
              return invalid(ValidationResult::MORTISE_DEPTH_INVALID, values)
            end
            unless positive?(values[:cutter_radius], values[:tolerance])
              return invalid(ValidationResult::CUTTER_RADIUS_INVALID, values)
            end

            ValidationResult.valid(
              values[:details].merge(
                joint_length: values[:joint_length],
                tenon_thickness: tenon_thickness,
                mortise_opening_thickness: mortise_opening,
                tenon_height: values[:tenon_height],
                mortise_depth: values[:mortise_depth],
                cutter_radius: values[:cutter_radius]
              )
            )
          end

          def invalid(code, values, extra = {})
            ValidationResult.new(code, values[:details].merge(extra))
          end

          def numeric_value(value)
            ValueSupport.finite_number?(value) ? value.to_f : nil
          end

          def positive_tolerance(value)
            numeric = numeric_value(value)
            numeric && numeric.positive? ? numeric : 1.0e-9
          end

          def positive?(value, tolerance)
            value && value > tolerance
          end

          def nonnegative?(value)
            value && value >= 0.0
          end
        end
      end
    end
  end
end
