# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class GeometryParameterAdapter
          def initialize(unit_converter: CNCPlugins::Units)
            @unit_converter = unit_converter
          end

          def mortise_parameters(connection, joint, _preview_settings = nil)
            depth = joint.mortise_depth
            if connection.female_board_thickness &&
               depth > connection.female_board_thickness + connection.requested_settings.geometric_tolerance
              raise JointExecutionFailure.new(
                'mortise_depth_exceeds_board',
                'Chiều sâu mộng âm vượt quá chiều dày chi tiết nhận mộng.',
                connection_id: connection.stable_id,
                joint_id: joint.stable_id
              )
            end
            {
              mortise_width: joint.joint_length,
              mortise_height: joint.mortise_opening_thickness,
              mortise_depth: depth,
              mortise_face_width: connection.contact_region_bounds.length,
              mortise_face_height: connection.contact_region_bounds.width,
              mortise_model_depth: connection.female_board_thickness,
              cutter_radius: joint.cutter_radius,
              clearance: joint.fit_clearance,
              dogbone_style: Geometry::DOGBONE_STYLE_VERTICAL_TBONE,
              create_mortise: true,
              create_tenon: false,
              add_labels: false
            }.freeze
          end

          def tenon_parameters(_connection, joint, _preview_settings = nil)
            # The legacy manual generator subtracts `clearance` once from both
            # nominal profile dimensions. Passing the resolved opening size here
            # therefore produces exactly the finalized tenon_length and
            # tenon_thickness without changing manual-tool behavior.
            {
              tenon_width: joint.joint_length,
              tenon_height: joint.mortise_opening_thickness,
              tenon_projection: joint.tenon_height,
              tenon_cutter_radius: joint.cutter_radius,
              clearance: joint.fit_clearance,
              tenon_count: 1,
              tenon_edge_offset: 0.0,
              tenon_face_width: nil,
              tenon_relief_enabled: true,
              create_mortise: false,
              create_tenon: true,
              add_labels: false
            }.freeze
          end

        end

        class ManualGeometryExecutionAdapter
          def initialize(geometry: DogboneJoinery::Geometry)
            @geometry = geometry
          end

          def generate_tenon(target:, params:, placement:, parent_entities:)
            effective_width = @geometry.effective_tenon_width(params)
            effective_height = @geometry.effective_tenon_height(params)
            vertical_inset = @geometry.tenon_vertical_inset(params)
            origin = Geom::Point3d.new(
              -(effective_width / 2.0),
              -((effective_height / 2.0) + vertical_inset),
              0
            )
            @geometry.union_tenons_into_solid(
              target,
              params,
              origin: origin,
              transformation: placement.to_sketchup_transformation,
              manage_operation: false,
              create_backup: false,
              ensure_unique: false,
              update_selection: false,
              parent_entities: parent_entities,
              preserve_target_properties: true,
              apply_template_material: false
            )
          rescue JointExecutionFailure
            raise
          rescue StandardError => error
            raise JointExecutionFailure.new(
              'tenon_geometry_failed',
              'Không thể tạo mộng dương tại vị trí đã xem trước. Toàn bộ thay đổi đã được hoàn tác.',
              error_class: error.class.name,
              error_message: error.message
            )
          end

          def generate_mortise(target:, params:, placement:, parent_entities:)
            @geometry.cut_mortise_into_solid(
              target,
              params,
              origin: Geom::Point3d.new(0, 0, 0),
              transformation: placement.to_sketchup_transformation,
              manage_operation: false,
              create_backup: false,
              parent_entities: parent_entities,
              preserve_target_properties: true
            )
          rescue JointExecutionFailure
            raise
          rescue StandardError => error
            raise JointExecutionFailure.new(
              'mortise_geometry_failed',
              'Không thể cắt mộng âm tại vị trí đã xem trước. Toàn bộ thay đổi đã được hoàn tác.',
              error_class: error.class.name,
              error_message: error.message
            )
          end
        end
      end
    end
  end
end
