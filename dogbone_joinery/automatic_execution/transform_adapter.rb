# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class JointTransformAdapter
          EPSILON = 1.0e-8

          def placement_for(connection, joint, entity_reference, role)
            parent_inverse = entity_reference.parent_world_transform.inverse
            planned = planned_placement(joint, role)
            placement = JointGeometryPlacement.new(
              role: role,
              world_center: planned.origin,
              center: parent_inverse.apply_point(planned.origin),
              x_axis: parent_inverse.apply_vector(planned.x_axis),
              y_axis: parent_inverse.apply_vector(planned.y_axis),
              z_axis: parent_inverse.apply_vector(planned.z_axis),
              execution_direction: parent_inverse.apply_vector(planned.insertion_direction),
              world_execution_direction: planned.insertion_direction
            )
            validate_placement!(placement)
            placement
          rescue ArgumentError => error
            raise JointExecutionFailure.new(
              'unsupported_transform',
              'Phép biến đổi của chi tiết không an toàn để tạo mộng.',
              error: error.message
            )
          end

          private

          def planned_placement(joint, role)
            placement = role.to_sym == :male ? joint.male_placement : joint.female_placement
            raise ArgumentError, 'Không tìm thấy hệ trục đã chốt của vị trí mộng.' unless placement

            placement
          end

          def validate_placement!(placement)
            axes = [placement.x_axis, placement.y_axis, placement.z_axis]
            unless axes.all? { |axis| axis.length > EPSILON }
              raise ArgumentError, 'Hệ trục cục bộ có véc-tơ bằng 0.'
            end
            volume = placement.x_axis.dot(placement.y_axis.cross(placement.z_axis)).abs
            raise ArgumentError, 'Hệ trục cục bộ bị suy biến.' if volume <= EPSILON

            true
          end
        end
      end
    end
  end
end
