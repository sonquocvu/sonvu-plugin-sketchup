# frozen_string_literal: true

# Copy-on-write preview representation. It contains no SketchUp entities and
# cannot generate or modify model geometry.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PlacementData
          attr_reader :origin, :x_axis, :y_axis, :z_axis, :insertion_direction

          def self.for_male(origin, joint_axis, insertion_direction)
            z_axis = insertion_direction.normalized
            x_axis = joint_axis.normalized.canonical
            new(
              origin: origin,
              x_axis: x_axis,
              y_axis: z_axis.cross(x_axis).normalized,
              z_axis: z_axis,
              insertion_direction: insertion_direction.normalized
            )
          end

          def self.for_female(origin, joint_axis, insertion_direction)
            z_axis = -insertion_direction.normalized
            x_axis = joint_axis.normalized.canonical
            new(
              origin: origin,
              x_axis: x_axis,
              y_axis: z_axis.cross(x_axis).normalized,
              z_axis: z_axis,
              insertion_direction: insertion_direction.normalized
            )
          end

          def initialize(origin:, x_axis:, y_axis:, z_axis:, insertion_direction:)
            @origin = origin
            @x_axis = x_axis
            @y_axis = y_axis
            @z_axis = z_axis
            @insertion_direction = insertion_direction
            freeze
          end

          def to_h
            {
              origin: origin.to_h,
              x_axis: x_axis.to_h,
              y_axis: y_axis.to_h,
              z_axis: z_axis.to_h,
              insertion_direction: insertion_direction.to_h
            }
          end
        end

        class RoleAssignmentSuggestion
          attr_reader :male_part_identity, :female_part_identity, :source, :reason, :conflicts_with_geometry

          def initialize(male_part_identity:, female_part_identity:, reason:, conflicts_with_geometry:)
            @male_part_identity = male_part_identity
            @female_part_identity = female_part_identity
            @source = 'role_metadata'.freeze
            @reason = reason.to_s.freeze
            @conflicts_with_geometry = !!conflicts_with_geometry
            freeze
          end

          def to_h
            {
              male_part_id: male_part_identity.stable_id,
              female_part_id: female_part_identity.stable_id,
              source: source,
              reason: reason,
              conflicts_with_geometry: conflicts_with_geometry
            }
          end
        end

        class JointInstancePlan
          attr_reader :stable_id, :index, :center_position, :start_position, :end_position,
                      :joint_length, :detected_male_board_thickness, :tenon_thickness,
                      :mortise_opening_thickness, :fit_clearance, :tenon_height,
                      :mortise_depth, :cutter_radius, :thickness_axis,
                      :male_placement, :female_placement, :enabled

          def initialize(stable_id:, index:, center_position:, start_position:, end_position:,
                         joint_length: nil, detected_male_board_thickness: nil,
                         tenon_thickness: nil, mortise_opening_thickness: nil,
                         fit_clearance: 0.0, tenon_height: 10.0, mortise_depth: 10.0,
                         cutter_radius: 3.0, thickness_axis: nil,
                         male_placement:, female_placement:, enabled: true,
                         width: nil, thickness: nil)
            resolved_length = joint_length.nil? ? width : joint_length
            resolved_tenon = tenon_thickness.nil? ? thickness : tenon_thickness
            resolved_opening = mortise_opening_thickness
            resolved_opening = resolved_tenon.to_f + fit_clearance.to_f if resolved_opening.nil?
            resolved_detected = detected_male_board_thickness || resolved_opening
            @stable_id = stable_id.to_s.freeze
            @index = index.to_i
            @center_position = center_position
            @start_position = start_position
            @end_position = end_position
            @joint_length = resolved_length.to_f
            @detected_male_board_thickness = resolved_detected.to_f
            @tenon_thickness = resolved_tenon.to_f
            @mortise_opening_thickness = resolved_opening.to_f
            @fit_clearance = fit_clearance.to_f
            @tenon_height = tenon_height.to_f
            @mortise_depth = mortise_depth.to_f
            @cutter_radius = cutter_radius.to_f
            @thickness_axis = thickness_axis || female_placement.y_axis.normalized.canonical
            @male_placement = male_placement
            @female_placement = female_placement
            @enabled = !!enabled
            freeze
          end

          # Read compatibility for older extensions around the planning API.
          # New production code and serialization use the explicit names above.
          def width
            joint_length
          end

          def thickness
            mortise_opening_thickness
          end

          def tenon_length
            joint_length - fit_clearance
          end

          def with_enabled(value)
            JointInstancePlan.new(
              stable_id: stable_id,
              index: index,
              center_position: center_position,
              start_position: start_position,
              end_position: end_position,
              joint_length: joint_length,
              detected_male_board_thickness: detected_male_board_thickness,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening_thickness,
              fit_clearance: fit_clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis,
              male_placement: male_placement,
              female_placement: female_placement,
              enabled: value
            )
          end

          def with_placements(male:, female:)
            JointInstancePlan.new(
              stable_id: stable_id,
              index: index,
              center_position: center_position,
              start_position: start_position,
              end_position: end_position,
              joint_length: joint_length,
              detected_male_board_thickness: detected_male_board_thickness,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening_thickness,
              fit_clearance: fit_clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis,
              male_placement: male,
              female_placement: female,
              enabled: enabled
            )
          end

          def to_h
            {
              stable_id: stable_id,
              index: index,
              center_position: center_position.to_h,
              start_position: start_position.to_h,
              end_position: end_position.to_h,
              detected_male_board_thickness: detected_male_board_thickness,
              joint_length: joint_length,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening_thickness,
              fit_clearance: fit_clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis.to_h,
              male_placement: male_placement.to_h,
              female_placement: female_placement.to_h,
              enabled: enabled
            }
          end

          def with_detected_male_board_thickness(value)
            opening = value.to_f
            copy_with_dimensions(
              detected_male_board_thickness: opening,
              tenon_thickness: opening - fit_clearance,
              mortise_opening_thickness: opening
            )
          end

          private

          def copy_with_dimensions(changes)
            attributes = {
              stable_id: stable_id,
              index: index,
              center_position: center_position,
              start_position: start_position,
              end_position: end_position,
              joint_length: joint_length,
              detected_male_board_thickness: detected_male_board_thickness,
              tenon_thickness: tenon_thickness,
              mortise_opening_thickness: mortise_opening_thickness,
              fit_clearance: fit_clearance,
              tenon_height: tenon_height,
              mortise_depth: mortise_depth,
              cutter_radius: cutter_radius,
              thickness_axis: thickness_axis,
              male_placement: male_placement,
              female_placement: female_placement,
              enabled: enabled
            }
            changes.each { |name, value| attributes[name] = value }
            JointInstancePlan.new(**attributes)
          end
        end

        class ConnectionPlan
          CONNECTION_TYPES = %w[edge_to_face t_joint l_joint back_joint unknown_supported].freeze
          ASSIGNMENT_SOURCES = %w[geometry role_metadata user_override].freeze
          USER_OVERRIDE_STATES = %w[none reversed role_suggestion].freeze

          ATTRIBUTES = [
            :stable_id,
            :first_part_identity,
            :second_part_identity,
            :male_part_identity,
            :female_part_identity,
            :assignment_source,
            :reversible,
            :connection_type,
            :contact_plane,
            :contact_region_bounds,
            :contact_direction,
            :usable_joint_axis,
            :male_inward_direction,
            :female_inward_direction,
            :tenon_inward_direction,
            :mortise_inward_direction,
            :contact_length,
            :male_board_thickness,
            :female_board_thickness,
            :requested_settings,
            :calculated_settings,
            :validation,
            :joint_instances,
            :enabled,
            :user_override_state,
            :role_assignment_suggestion
          ].freeze

          attr_reader(*ATTRIBUTES)

          def initialize(attributes)
            type = attributes.fetch(:connection_type).to_s
            source = attributes.fetch(:assignment_source).to_s
            override = attributes.fetch(:user_override_state, 'none').to_s
            raise ArgumentError, 'Loại liên kết không được hỗ trợ.' unless CONNECTION_TYPES.include?(type)
            raise ArgumentError, 'Nguồn gán mộng không được hỗ trợ.' unless ASSIGNMENT_SOURCES.include?(source)
            raise ArgumentError, 'Trạng thái ghi đè không được hỗ trợ.' unless USER_OVERRIDE_STATES.include?(override)

            ATTRIBUTES.each do |name|
              value = attributes[name]
              value = type if name == :connection_type
              value = source if name == :assignment_source
              value = override if name == :user_override_state
              value = !!value if name == :reversible || name == :enabled
              value = value.freeze if value.is_a?(Array) && !value.frozen?
              instance_variable_set("@#{name}", value)
            end
            freeze
          end

          def valid?
            validation.valid?
          end

          def with_enabled(value)
            copy_with(enabled: !!value)
          end

          def with_joint_enabled(joint_id, value)
            found = false
            joints = joint_instances.map do |joint|
              if joint.stable_id == joint_id.to_s
                found = true
                joint.with_enabled(value)
              else
                joint
              end
            end
            raise ArgumentError, 'Không tìm thấy vị trí mộng trong liên kết.' unless found

            copy_with(joint_instances: joints)
          end

          def reverse_assignment
            raise ArgumentError, 'Liên kết này không cho phép đảo mộng âm/dương.' unless reversible

            swap_assignment('user_override', 'reversed')
          end

          def apply_role_assignment_suggestion
            raise ArgumentError, 'Liên kết không có đề xuất từ dữ liệu vai trò.' unless role_assignment_suggestion

            suggestion = role_assignment_suggestion
            if suggestion.male_part_identity == male_part_identity
              return copy_with(assignment_source: 'role_metadata', user_override_state: 'role_suggestion')
            end

            swap_assignment('role_metadata', 'role_suggestion')
          end

          def to_h
            {
              stable_id: stable_id,
              first_part: first_part_identity.to_h,
              second_part: second_part_identity.to_h,
              male_part: male_part_identity.to_h,
              female_part: female_part_identity.to_h,
              assignment_source: assignment_source,
              reversible: reversible,
              connection_type: connection_type,
              contact_plane: contact_plane.to_h,
              contact_region_bounds: contact_region_bounds.to_h,
              contact_direction: contact_direction.to_h,
              usable_joint_axis: usable_joint_axis.to_h,
              male_inward_direction: male_inward_direction.to_h,
              female_inward_direction: female_inward_direction.to_h,
              tenon_inward_direction: tenon_inward_direction.to_h,
              mortise_inward_direction: mortise_inward_direction.to_h,
              contact_length: contact_length,
              board_thicknesses: {
                male: male_board_thickness,
                female: female_board_thickness
              },
              requested_settings: requested_settings.to_h,
              calculated_settings: calculated_settings.to_h,
              validation: validation.to_h,
              joint_instances: joint_instances.map(&:to_h),
              enabled: enabled,
              user_override_state: user_override_state,
              role_assignment_suggestion: role_assignment_suggestion && role_assignment_suggestion.to_h
            }
          end

          private

          def swap_assignment(source, override_state)
            insertion = male_inward_direction
            joints = joint_instances.map do |joint|
              joint.with_detected_male_board_thickness(female_board_thickness).with_placements(
                male: PlacementData.for_male(joint.center_position, usable_joint_axis, insertion),
                female: PlacementData.for_female(joint.center_position, usable_joint_axis, insertion)
              )
            end
            copy_with(
              male_part_identity: female_part_identity,
              female_part_identity: male_part_identity,
              assignment_source: source,
              contact_direction: -contact_direction,
              male_inward_direction: female_inward_direction,
              female_inward_direction: male_inward_direction,
              tenon_inward_direction: insertion,
              mortise_inward_direction: insertion,
              male_board_thickness: female_board_thickness,
              female_board_thickness: male_board_thickness,
              joint_instances: joints,
              user_override_state: override_state
            )
          end

          def copy_with(changes)
            attributes = ATTRIBUTES.each_with_object({}) do |name, hash|
              hash[name] = public_send(name)
            end
            changes.each { |key, value| attributes[key] = value }
            ConnectionPlan.new(attributes)
          end
        end

        class AnalysisDiagnostic
          attr_reader :first_part_id, :second_part_id, :validation

          def initialize(first_part_id:, second_part_id:, validation:)
            @first_part_id = first_part_id.to_s.freeze
            @second_part_id = second_part_id.to_s.freeze
            @validation = validation
            freeze
          end

          def to_h
            {
              first_part_id: first_part_id,
              second_part_id: second_part_id,
              validation: validation.to_h,
              message_vi: VietnameseValidationMessages.message_for(validation)
            }
          end
        end

        class PreviewPlan
          attr_reader :connections, :diagnostics

          def initialize(connections:, diagnostics: [])
            ids = connections.map(&:stable_id)
            raise ArgumentError, 'Kế hoạch xem trước chứa mã liên kết trùng nhau.' unless ids.uniq.length == ids.length

            @connections = connections.freeze
            @diagnostics = diagnostics.freeze
            freeze
          end

          def valid?
            connections.all?(&:valid?)
          end

          def with_connection_enabled(connection_id, value)
            replace_connection(connection_id) { |connection| connection.with_enabled(value) }
          end

          def with_joint_enabled(connection_id, joint_id, value)
            replace_connection(connection_id) do |connection|
              connection.with_joint_enabled(joint_id, value)
            end
          end

          def reverse_connection(connection_id)
            replace_connection(connection_id, &:reverse_assignment)
          end

          def apply_role_suggestion(connection_id)
            replace_connection(connection_id, &:apply_role_assignment_suggestion)
          end

          def to_h
            {
              valid: valid?,
              connections: connections.map(&:to_h),
              diagnostics: diagnostics.map(&:to_h)
            }
          end

          private

          def replace_connection(connection_id)
            found = false
            updated = connections.map do |connection|
              if connection.stable_id == connection_id.to_s
                found = true
                yield(connection)
              else
                connection
              end
            end
            raise ArgumentError, 'Không tìm thấy liên kết trong kế hoạch xem trước.' unless found

            PreviewPlan.new(connections: updated, diagnostics: diagnostics)
          end
        end
      end
    end
  end
end
