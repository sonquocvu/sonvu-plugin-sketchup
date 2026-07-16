# frozen_string_literal: true

# Simple full-model drawing primitives for every valid bulk-preview joint.
# Skipped connections never reach this renderer.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PreviewPrimitiveBuilder
          RELIEF_MARKER_SEGMENTS = 12

          def build(plan, display_settings: PreviewDisplaySettings.defaults)
            primitives = plan.connections.flat_map do |connection|
              next [] unless connection.valid?

              connection_primitives(connection, display_settings)
            end
            primitives << legend_primitive if display_settings.show_legend
            primitives.freeze
          end

          private

          def connection_primitives(connection, display)
            primitives = []
            if display.show_contact_region
              primitives << primitive(
                'contact_boundary', loop_segments(boundary_points(connection.contact_region_bounds)),
                :contact, connection_id: connection.stable_id
              )
            end
            connection.joint_instances.each do |joint|
              primitives.concat(joint_primitives(connection, joint, display))
            end
            primitives.freeze
          end

          def joint_primitives(connection, joint, display)
            thickness_axis = joint.thickness_axis.normalized
            tenon_cross = thickness_axis * (joint.tenon_thickness / 2.0)
            mortise_cross = thickness_axis * (joint.mortise_opening_thickness / 2.0)
            tenon_start, tenon_end = centered_axis_limits(joint, joint.tenon_length)
            tenon_opening = rectangle_from_axis(tenon_start, tenon_end, tenon_cross)
            mortise_opening = rectangle_from_axis(
              joint.start_position,
              joint.end_position,
              mortise_cross
            )
            tenon_direction = connection.tenon_inward_direction.normalized
            mortise_direction = connection.mortise_inward_direction.normalized
            common = {
              connection_id: connection.stable_id,
              joint_id: joint.stable_id,
              direction: tenon_direction,
              original_center: joint.center_position,
              detected_male_board_thickness: joint.detected_male_board_thickness,
              joint_length: joint.joint_length,
              tenon_thickness: joint.tenon_thickness,
              mortise_opening_thickness: joint.mortise_opening_thickness,
              fit_clearance: joint.fit_clearance,
              thickness_axis: joint.thickness_axis,
              display_only: true
            }
            primitives = []
            if display.show_tenons
              tenon_tip = translate_points(tenon_opening, tenon_direction * joint.tenon_height)
              primitives << primitive(
                'tenon_prism', prism_segments(tenon_opening, tenon_tip), :tenon,
                common.merge(
                  role: 'male',
                  part_id: connection.male_part_identity.stable_id,
                  direction: tenon_direction,
                  display_depth: joint.tenon_height
                )
              )
            end
            if display.show_mortises
              mortise_inner = translate_points(
                mortise_opening,
                mortise_direction * joint.mortise_depth
              )
              primitives << primitive(
                'vertical_tbone_mortise_cavity',
                prism_segments(mortise_opening, mortise_inner),
                :mortise,
                common.merge(
                  role: 'female',
                  part_id: connection.female_part_identity.stable_id,
                  direction: mortise_direction,
                  mortise_geometry: 'vertical_tbone',
                  relief_orientation: 'female_local_y',
                  cutter_radius: joint.cutter_radius,
                  display_depth: joint.mortise_depth
                )
              )
              relief_points = vertical_tbone_relief_segments(joint)
              unless relief_points.empty?
                primitives << primitive(
                  'vertical_tbone_relief_markers', relief_points, :mortise,
                  common.merge(
                    role: 'female',
                    part_id: connection.female_part_identity.stable_id,
                    direction: mortise_direction,
                    mortise_geometry: 'vertical_tbone',
                    relief_orientation: 'female_local_y',
                    cutter_radius: joint.cutter_radius,
                    display_depth: joint.mortise_depth
                  )
                )
              end
            end
            primitives.freeze
          end

          def legend_primitive
            primitive(
              'viewport_legend', [], :label,
              legend_entries: [
                { style: :tenon, label: 'Mộng dương — nét liền xanh' },
                { style: :mortise, label: 'Mộng âm dọc (T-bone) – – nét đứt cam' }
              ],
              legend_note: 'Vị trí bị bỏ qua không hiển thị · Xem trước không thay đổi mô hình.'
            )
          end

          def boundary_points(bounds)
            [
              point_at(bounds, bounds.axis_min, bounds.cross_min),
              point_at(bounds, bounds.axis_max, bounds.cross_min),
              point_at(bounds, bounds.axis_max, bounds.cross_max),
              point_at(bounds, bounds.axis_min, bounds.cross_max)
            ]
          end

          def point_at(bounds, axis_value, cross_value)
            bounds.origin + (bounds.axis * axis_value) + (bounds.cross_axis * cross_value)
          end

          def rectangle_from_axis(start_point, end_point, cross)
            [start_point - cross, end_point - cross, end_point + cross, start_point + cross]
          end

          def centered_axis_limits(joint, length)
            axis = (joint.end_position - joint.start_position).normalized
            half = axis * (length / 2.0)
            [joint.center_position - half, joint.center_position + half]
          end

          def translate_points(points, vector)
            points.map { |point| point + vector }
          end

          def loop_segments(points)
            points.each_with_index.flat_map do |point, index|
              [point, points[(index + 1) % points.length]]
            end
          end

          def prism_segments(first, second)
            loop_segments(first) + loop_segments(second) +
              first.zip(second).flat_map { |start_point, end_point| [start_point, end_point] }
          end

          def vertical_tbone_relief_segments(joint)
            cutter_radius = joint.cutter_radius
            return [] unless VerticalTBoneGeometry.feasible?(
              width: joint.joint_length,
              height: joint.mortise_opening_thickness,
              radius: cutter_radius
            )

            centers = VerticalTBoneGeometry.relief_centers(
              width: joint.joint_length,
              height: joint.mortise_opening_thickness,
              radius: cutter_radius,
              origin_x: -(joint.joint_length / 2.0),
              origin_y: -(joint.mortise_opening_thickness / 2.0)
            )
            x_axis = joint.female_placement.x_axis.normalized
            y_axis = joint.thickness_axis.normalized
            centers.values.flat_map do |local_center|
              center = joint.center_position +
                (x_axis * local_center[0]) +
                (y_axis * local_center[1])
              circle_segments(center, x_axis, y_axis, cutter_radius)
            end
          end

          def circle_segments(center, x_axis, y_axis, radius)
            points = RELIEF_MARKER_SEGMENTS.times.map do |index|
              angle = (Math::PI * 2.0 * index) / RELIEF_MARKER_SEGMENTS
              center +
                (x_axis * (Math.cos(angle) * radius)) +
                (y_axis * (Math.sin(angle) * radius))
            end
            loop_segments(points)
          end

          def primitive(kind, points, style, extra = {})
            ValueSupport.freeze_hash(
              {
                kind: kind,
                points: points,
                state: 'enabled',
                style: style,
                connection_id: extra[:connection_id],
                joint_id: extra[:joint_id],
                role: extra[:role],
                part_id: extra[:part_id],
                direction: extra[:direction],
                original_center: extra[:original_center],
                display_depth: extra[:display_depth],
                display_only: extra.key?(:display_only) ? extra[:display_only] : true,
                legend_entries: extra[:legend_entries],
                legend_note: extra[:legend_note],
                mortise_geometry: extra[:mortise_geometry],
                relief_orientation: extra[:relief_orientation],
                cutter_radius: extra[:cutter_radius],
                detected_male_board_thickness: extra[:detected_male_board_thickness],
                joint_length: extra[:joint_length],
                tenon_thickness: extra[:tenon_thickness],
                mortise_opening_thickness: extra[:mortise_opening_thickness],
                fit_clearance: extra[:fit_clearance],
                thickness_axis: extra[:thickness_axis]
              }
            )
          end
        end
      end
    end
  end
end
