# frozen_string_literal: true

require 'minitest/autorun'
require 'ripper'

require_relative '../../constants'
require_relative '../automatic_planning/loader'

module Sketchup
  class AutomaticPlanningVertex
    attr_reader :position

    def initialize(position)
      @position = position
    end
  end

  class AutomaticPlanningLoop
    attr_reader :vertices

    def initialize(vertices)
      @vertices = vertices
    end
  end

  class Face
    attr_reader :persistent_id, :outer_loop

    def initialize(persistent_id, points)
      @persistent_id = persistent_id
      vertices = points.map { |point| AutomaticPlanningVertex.new(point) }
      @outer_loop = AutomaticPlanningLoop.new(vertices)
    end
  end

  class AutomaticPlanningDefinition
    attr_reader :persistent_id, :entities, :name

    def initialize(persistent_id, entities, name = 'Shared board')
      @persistent_id = persistent_id
      @entities = entities
      @name = name
      @attributes = {}
    end

    def get_attribute(dictionary, key, default = nil)
      @attributes.fetch([dictionary, key], default)
    end

    def set_test_attribute(dictionary, key, value)
      @attributes[[dictionary, key]] = value
    end
  end

  class ComponentInstance
    attr_reader :persistent_id, :definition, :transformation, :name

    def initialize(persistent_id, definition, transformation, name = '')
      @persistent_id = persistent_id
      @definition = definition
      @transformation = transformation
      @name = name
      @attributes = {}
    end

    def valid?
      true
    end

    def hidden?
      false
    end

    def get_attribute(dictionary, key, default = nil)
      @attributes.fetch([dictionary, key], default)
    end

    def set_test_attribute(dictionary, key, value)
      @attributes[[dictionary, key]] = value
    end
  end

  class Group < ComponentInstance
    def entities
      definition.entities
    end
  end
end

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class AutomaticPlanningTest < Minitest::Test
        Planning = AutomaticPlanning

        class ReversePairFinder
          def find(boards, _tolerance)
            [[boards[0], boards[1]], [boards[1], boards[0]]]
          end
        end

        def setup
          @specification = Planning::JointLayoutSpecification.new(
            joint_length: 10.0,
            fit_clearance: 0.2,
            tenon_height: 10.0,
            mortise_depth: 10.0,
            cutter_radius: 3.0,
            requested_count: 3,
            start_offset: 5.0,
            end_offset: 5.0,
            minimum_gap: 2.0,
            geometric_tolerance: 0.001
          )
        end

        def test_edge_face_to_broad_face_assigns_edge_board_as_male
          male, female = t_joint_boards
          plan = Planning::Analyzer.new.analyze([male, female], @specification)
          connection = plan.connections.first

          assert_equal 'male', connection.male_part_identity.stable_id
          assert_equal 'female', connection.female_part_identity.stable_id
          assert_equal 'geometry', connection.assignment_source
          assert connection.valid?
          assert_in_delta 60.0, connection.contact_length, 0.0001
        end

        def test_edge_to_edge_contact_is_rejected
          first_identity = identity('edge-a')
          second_identity = identity('edge-b')
          first_face = face(first_identity, 'a', 'edge_face', rectangle(0, 0, 40, 20))
          second_face = face(second_identity, 'b', 'edge_face', rectangle(0, 0, 40, 20))
          first = board(first_identity, first_face, center_z: 10)
          second = board(second_identity, second_face, center_z: -10)

          detection = Planning::ContactDetector.new(0.001).detect_all(first, second).first

          refute detection.valid?
          assert_equal Planning::ValidationResult::UNSUPPORTED_CONTACT_TYPE, detection.validation.code
        end

        def test_line_only_contact_is_rejected
          broad_identity = identity('broad')
          edge_identity = identity('edge')
          broad = board(broad_identity, face(broad_identity, 'b', 'broad_face', rectangle(0, 0, 100, 100)), center_z: -10)
          edge = board(edge_identity, face(edge_identity, 'e', 'edge_face', rectangle(100, 20, 120, 40)), center_z: 10)

          detection = Planning::ContactDetector.new(0.001).detect_all(broad, edge).first

          assert_equal Planning::ValidationResult::LINE_ONLY_CONTACT, detection.validation.code
        end

        def test_point_only_contact_is_rejected
          broad_identity = identity('broad')
          edge_identity = identity('edge')
          broad = board(broad_identity, face(broad_identity, 'b', 'broad_face', rectangle(0, 0, 100, 100)), center_z: -10)
          edge = board(edge_identity, face(edge_identity, 'e', 'edge_face', rectangle(100, 100, 120, 120)), center_z: 10)

          detection = Planning::ContactDetector.new(0.001).detect_all(broad, edge).first

          assert_equal Planning::ValidationResult::POINT_ONLY_CONTACT, detection.validation.code
        end

        def test_contact_area_below_geometric_tolerance_is_rejected
          broad_identity = identity('small-broad')
          edge_identity = identity('small-edge')
          broad = board(broad_identity, face(broad_identity, 'b', 'broad_face', rectangle(0, 0, 10, 10)), center_z: -10)
          edge = board(edge_identity, face(edge_identity, 'e', 'edge_face', rectangle(9.95, 9.95, 12, 12)), center_z: 10)

          detection = Planning::ContactDetector.new(0.1).detect_all(broad, edge).first

          assert_equal Planning::ValidationResult::CONTACT_AREA_TOO_SMALL, detection.validation.code
        end

        def test_t_joint_is_classified_correctly
          connection = Planning::Analyzer.new.analyze(t_joint_boards, @specification).connections.first

          assert_equal 't_joint', connection.connection_type
        end

        def test_l_joint_is_classified_as_reversible
          connection = Planning::Analyzer.new.analyze(l_joint_boards, @specification).connections.first

          assert_equal 'l_joint', connection.connection_type
          assert connection.reversible
        end

        def test_reverse_pair_detection_collapses_to_one_connection
          analyzer = Planning::Analyzer.new(pair_finder: ReversePairFinder.new)

          plan = analyzer.analyze(t_joint_boards, @specification)

          assert_equal 1, plan.connections.length
          assert_equal 1, plan.diagnostics.count { |item| item.validation.code == Planning::ValidationResult::DUPLICATE_CONNECTION }
        end

        def test_three_joints_fit_and_distribute_symmetrically
          result = calculator.calculate(
            contact_length: 200.0,
            axis_min: 0.0,
            specification: layout_spec(width: 40, count: 3, start_offset: 20, end_offset: 20),
            female_board_thickness: 18.0
          )

          assert result.valid?
          assert_in_delta 20.0, result.calculated_gap, 0.0001
          assert_equal [40.0, 100.0, 160.0], result.axis_centers
          assert_in_delta 20.0, result.axis_starts.first, 0.0001
          assert_in_delta 180.0, result.axis_ends.last, 0.0001
        end

        def test_male_and_female_plans_share_identical_center_objects
          connection = Planning::Analyzer.new.analyze(t_joint_boards, @specification).connections.first

          connection.joint_instances.each do |joint|
            assert_same joint.center_position, joint.male_placement.origin
            assert_same joint.center_position, joint.female_placement.origin
            assert joint.male_placement.y_axis.normalized.canonical.almost_equal?(
              joint.thickness_axis,
              0.0001
            )
            assert joint.female_placement.y_axis.normalized.canonical.almost_equal?(
              joint.thickness_axis,
              0.0001
            )
          end
        end

        def test_tenon_and_mortise_thickness_are_resolved_from_each_male_board
          joint_17 = Planning::Analyzer.new.analyze(
            t_joint_boards(male_thickness: 17.0),
            @specification
          ).connections.first.joint_instances.first
          joint_18 = Planning::Analyzer.new.analyze(
            t_joint_boards(male_thickness: 18.0),
            @specification
          ).connections.first.joint_instances.first

          assert_in_delta 17.0, joint_17.detected_male_board_thickness, 0.0001
          assert_in_delta 16.8, joint_17.tenon_thickness, 0.0001
          assert_in_delta 17.0, joint_17.mortise_opening_thickness, 0.0001
          assert_in_delta 18.0, joint_18.detected_male_board_thickness, 0.0001
          assert_in_delta 17.8, joint_18.tenon_thickness, 0.0001
          assert_in_delta 18.0, joint_18.mortise_opening_thickness, 0.0001
          refute_equal joint_17.tenon_thickness, joint_18.tenon_thickness
        end

        def test_clearance_is_one_total_opening_allowance_without_hidden_adjustment
          joint = Planning::Analyzer.new.analyze(
            t_joint_boards(male_thickness: 17.0),
            @specification
          ).connections.first.joint_instances.first

          assert_in_delta 0.2, joint.fit_clearance, 0.0001
          assert_in_delta(
            joint.tenon_thickness + joint.fit_clearance,
            joint.mortise_opening_thickness,
            0.0001
          )
          assert_in_delta joint.detected_male_board_thickness,
                          joint.mortise_opening_thickness, 0.0001
        end

        def test_zero_configured_clearance_adds_no_hidden_allowance
          exact_specification = Planning::JointLayoutSpecification.new(
            joint_length: 10.0,
            fit_clearance: 0.0,
            tenon_height: 10.0,
            mortise_depth: 10.0,
            cutter_radius: 3.0,
            requested_count: 3,
            start_offset: 5.0,
            end_offset: 5.0,
            minimum_gap: 2.0,
            geometric_tolerance: 0.001
          )

          joint = Planning::Analyzer.new.analyze(
            t_joint_boards(male_thickness: 17.0),
            exact_specification
          ).connections.first.joint_instances.first

          assert_in_delta 17.0, joint.tenon_thickness, 0.0001
          assert_in_delta 17.0, joint.mortise_opening_thickness, 0.0001
          assert_in_delta 0.0, joint.fit_clearance, 0.0001
        end

        def test_mixed_board_thicknesses_are_resolved_per_connection
          boards = t_joint_boards(male_thickness: 17.0, id_suffix: '-17') +
            t_joint_boards(male_thickness: 18.0, id_suffix: '-18', offset_x: 200.0)

          plan = Planning::Analyzer.new.analyze(boards, @specification)
          joints = plan.connections.select(&:valid?).map do |connection|
            connection.joint_instances.first
          end
          resolved = joints.map(&:detected_male_board_thickness).sort

          assert_equal 2, plan.connections.count(&:valid?)
          assert_equal [17.0, 18.0], resolved
          assert_equal [10.0], joints.map(&:joint_length).uniq
          assert_equal [16.8, 17.8], joints.map(&:tenon_thickness).sort
        end

        def test_asymmetric_offsets_are_respected
          result = calculator.calculate(
            contact_length: 150.0,
            axis_min: 10.0,
            specification: layout_spec(width: 30, count: 3, start_offset: 10, end_offset: 20),
            female_board_thickness: 18.0
          )

          assert result.valid?
          assert_in_delta 20.0, result.axis_starts.first, 0.0001
          assert_in_delta 140.0, result.axis_ends.last, 0.0001
        end

        def test_insufficient_length_is_invalid_without_reducing_requested_count
          specification = layout_spec(width: 30, count: 4, start_offset: 5, end_offset: 5)
          result = calculator.calculate(
            contact_length: 100.0,
            axis_min: 0.0,
            specification: specification,
            female_board_thickness: 18.0
          )

          refute result.valid?
          assert_equal Planning::ValidationResult::CONTACT_REGION_TOO_SHORT, result.validation.code
          assert_equal 4, specification.requested_count
          assert_empty result.axis_centers
        end

        def test_maximum_feasible_count_is_reported
          result = calculator.calculate(
            contact_length: 100.0,
            axis_min: 0.0,
            specification: layout_spec(width: 30, count: 4, start_offset: 5, end_offset: 5, minimum_gap: 10),
            female_board_thickness: 18.0
          )

          assert_equal 2, result.maximum_feasible_count
          assert_equal 4, result.validation.details[:requested_count]
        end

        def test_minimum_gap_is_validated
          result = calculator.calculate(
            contact_length: 150.0,
            axis_min: 0.0,
            specification: layout_spec(width: 40, count: 3, start_offset: 10, end_offset: 10, minimum_gap: 10),
            female_board_thickness: 18.0
          )

          assert_equal Planning::ValidationResult::MINIMUM_GAP_CANNOT_BE_MAINTAINED, result.validation.code
          assert_in_delta 5.0, result.calculated_gap, 0.0001
        end

        def test_invalid_joint_length_and_count_have_stable_codes
          width = calculation_for(layout_spec(width: 0, count: 2))
          count = calculation_for(layout_spec(width: 20, count: 0))

          assert_equal Planning::ValidationResult::JOINT_LENGTH_INVALID, width.validation.code
          assert_equal Planning::ValidationResult::COUNT_INVALID, count.validation.code
          assert_equal 'Chiều dài mộng phải là số hữu hạn lớn hơn 0.', Planning::VietnameseValidationMessages.message_for(width.validation)
        end

        def test_ambiguous_board_thickness_is_reported
          male, female = t_joint_boards
          ambiguous_male = Planning::BoardDescriptor.new(
            identity: male.identity,
            faces: male.faces,
            thickness: nil,
            thickness_ambiguous: true,
            center: male.center
          )

          connection = Planning::Analyzer.new.analyze([ambiguous_male, female], @specification).connections.first

          assert_equal Planning::ValidationResult::AMBIGUOUS_BOARD_THICKNESS, connection.validation.code
          refute connection.enabled
          assert_empty connection.joint_instances
        end

        def test_zero_male_board_thickness_is_rejected_without_guessing
          male, female = t_joint_boards(male_thickness: 0.0)

          connection = Planning::Analyzer.new.analyze([male, female], @specification).connections.first

          assert_equal Planning::ValidationResult::BOARD_THICKNESS_INVALID, connection.validation.code
          refute connection.enabled
          assert_empty connection.joint_instances
        end

        def test_offsets_that_consume_length_have_stable_code
          result = calculation_for(layout_spec(width: 20, count: 1, start_offset: 60, end_offset: 60))

          assert_equal Planning::ValidationResult::OFFSETS_CONSUME_AVAILABLE_LENGTH, result.validation.code
        end

        def test_transformed_rotated_descriptors_resolve_consistently
          original = t_joint_boards
          transform = Planning::Transform3.translation(300, -20, 75) *
            Planning::Transform3.rotation(Planning::Vector3.new(1, 1, 0), Math::PI / 3.0)
          transformed = original.map { |item| transform_board(item, transform) }

          original_connection = Planning::Analyzer.new.analyze(original, @specification).connections.first
          transformed_connection = Planning::Analyzer.new.analyze(transformed, @specification).connections.first

          assert_equal original_connection.male_part_identity.stable_id, transformed_connection.male_part_identity.stable_id
          assert_equal original_connection.connection_type, transformed_connection.connection_type
          assert_in_delta original_connection.contact_length, transformed_connection.contact_length, 0.0001
          assert_equal original_connection.joint_instances.length, transformed_connection.joint_instances.length
          original_joint = original_connection.joint_instances.first
          transformed_joint = transformed_connection.joint_instances.first
          assert_in_delta original_joint.detected_male_board_thickness,
                          transformed_joint.detected_male_board_thickness, 0.0001
          assert_in_delta original_joint.tenon_thickness, transformed_joint.tenon_thickness, 0.0001
          assert_in_delta original_joint.mortise_opening_thickness,
                          transformed_joint.mortise_opening_thickness, 0.0001
        end

        def test_finalized_joint_hash_uses_unambiguous_dimension_names
          joint_hash = Planning::Analyzer.new.analyze(
            t_joint_boards,
            @specification
          ).connections.first.joint_instances.first.to_h

          %i[
            detected_male_board_thickness joint_length tenon_thickness
            mortise_opening_thickness fit_clearance tenon_height mortise_depth
            cutter_radius thickness_axis
          ].each { |field| assert joint_hash.key?(field), "Thiếu #{field}" }
          refute joint_hash.key?(:width)
          refute joint_hash.key?(:thickness)
        end

        def test_shared_component_definition_instances_keep_separate_identity
          definition = shared_box_definition
          first = Sketchup::ComponentInstance.new(101, definition, Planning::Transform3.identity, 'First')
          second = Sketchup::ComponentInstance.new(102, definition, Planning::Transform3.translation(500, 0, 0), 'Second')

          descriptors = Planning::SketchupBoardScanner.new.scan([first, second])

          assert_equal 2, descriptors.length
          refute_equal descriptors[0].identity.stable_id, descriptors[1].identity.stable_id
          assert_equal descriptors[0].identity.definition_id, descriptors[1].identity.definition_id
          assert_equal 9001, descriptors[0].identity.definition_id
        end

        def test_nested_rotated_component_preserves_physical_board_thickness
          board_definition = box_definition(17.0, 9101)
          child = Sketchup::ComponentInstance.new(
            201,
            board_definition,
            Planning::Transform3.rotation(Planning::Vector3.new(1, 1, 0), Math::PI / 4.0),
            'Nested board'
          )
          container_definition = Sketchup::AutomaticPlanningDefinition.new(9201, [child], 'Container')
          container = Sketchup::Group.new(
            202,
            container_definition,
            Planning::Transform3.translation(40, -30, 70) *
              Planning::Transform3.rotation(Planning::Vector3.new(0, 0, 1), Math::PI / 3.0),
            'Rotated container'
          )

          descriptor = Planning::SketchupBoardScanner.new.scan([container]).first

          refute_nil descriptor
          refute descriptor.thickness_ambiguous
          assert_in_delta 17.0, descriptor.thickness, 0.0001
        end

        def test_role_metadata_records_suggestion_without_silent_override
          male, female = t_joint_boards(male_role: 'back', female_role: 'side_left')

          connection = Planning::Analyzer.new.analyze([male, female], @specification).connections.first

          assert_equal 'male', connection.male_part_identity.stable_id
          assert_equal 'geometry', connection.assignment_source
          assert connection.role_assignment_suggestion.conflicts_with_geometry
          assert_equal 'female', connection.role_assignment_suggestion.male_part_identity.stable_id
          assert_equal 'male', connection.role_assignment_suggestion.female_part_identity.stable_id
        end

        def test_user_reversal_swaps_assignment_and_preserves_shared_positions
          connection = Planning::Analyzer.new.analyze(t_joint_boards, @specification).connections.first
          centers = connection.joint_instances.map(&:center_position)

          reversed = connection.reverse_assignment

          assert_equal connection.female_part_identity, reversed.male_part_identity
          assert_equal connection.male_part_identity, reversed.female_part_identity
          assert_equal 'user_override', reversed.assignment_source
          assert_equal 'reversed', reversed.user_override_state
          assert_equal centers, reversed.joint_instances.map(&:center_position)
        end

        def test_disabled_connections_and_joints_remain_in_preview
          plan = Planning::Analyzer.new.analyze(t_joint_boards, @specification)
          connection = plan.connections.first
          joint = connection.joint_instances.first

          disabled_connection_plan = plan.with_connection_enabled(connection.stable_id, false)
          disabled_joint_plan = plan.with_joint_enabled(connection.stable_id, joint.stable_id, false)

          assert_equal 1, disabled_connection_plan.connections.length
          refute disabled_connection_plan.connections.first.enabled
          assert_equal 3, disabled_joint_plan.connections.first.joint_instances.length
          refute disabled_joint_plan.connections.first.joint_instances.first.enabled
        end

        def test_invalid_connection_remains_in_preview_with_no_partial_joints
          invalid_spec = layout_spec(width: 40, count: 4, start_offset: 5, end_offset: 5)

          connection = Planning::Analyzer.new.analyze(t_joint_boards, invalid_spec).connections.first

          refute connection.valid?
          refute connection.enabled
          assert_equal 4, connection.requested_settings.requested_count
          assert_empty connection.joint_instances
        end

        def test_all_automatic_planning_production_files_parse_and_avoid_post_27_syntax
          root = File.expand_path('../automatic_planning', __dir__)
          files = Dir.children(root).select { |name| File.extname(name) == '.rb' }.map do |name|
            File.join(root, name)
          end

          refute_empty files
          files.each do |path|
            source = File.read(path, encoding: 'UTF-8')
            refute_nil Ripper.sexp(source), "Không phân tích được cú pháp: #{path}"
            refute_match(
              /^\s*def\s+[a-zA-Z_]\w*[!?=]?\s*(?:\([^)]*\))?\s*=\s*[^\n]+$/,
              source,
              "Không dùng endless method của Ruby 3: #{path}"
            )
            refute_match(/\bData\.define\b/, source, "Không dùng Data của Ruby 3.2: #{path}")
          end
        end

        private

        def identity(id, role = nil)
          Planning::PartIdentity.new(
            stable_id: id,
            persistent_id: id,
            definition_id: "definition-#{id}",
            instance_path: [id],
            display_name: id,
            role_metadata: role
          )
        end

        def face(part_identity, id, kind, points)
          Planning::FaceDescriptor.new(
            stable_id: "#{part_identity.stable_id}:#{id}",
            board_identity: part_identity,
            vertices: points,
            kind: kind
          )
        end

        def board(part_identity, contact_face, center_z:, thickness: 18.0, ambiguous: false)
          Planning::BoardDescriptor.new(
            identity: part_identity,
            faces: [contact_face],
            thickness: thickness,
            thickness_ambiguous: ambiguous,
            center: Planning::Point3.new(50, 50, center_z)
          )
        end

        def rectangle(min_x, min_y, max_x, max_y, z = 0.0)
          [
            Planning::Point3.new(min_x, min_y, z),
            Planning::Point3.new(max_x, min_y, z),
            Planning::Point3.new(max_x, max_y, z),
            Planning::Point3.new(min_x, max_y, z)
          ]
        end

        def t_joint_boards(male_role: nil, female_role: nil, male_thickness: 18.0,
                           female_thickness: 18.0, id_suffix: '', offset_x: 0.0)
          male_identity = identity("male#{id_suffix}", male_role)
          female_identity = identity("female#{id_suffix}", female_role)
          male_face = face(
            male_identity,
            'contact',
            'edge_face',
            rectangle(20 + offset_x, 40, 80 + offset_x, 58)
          )
          female_face = face(
            female_identity,
            'contact',
            'broad_face',
            rectangle(offset_x, 0, 100 + offset_x, 100)
          )
          [
            Planning::BoardDescriptor.new(
              identity: male_identity,
              faces: [male_face],
              thickness: male_thickness,
              center: Planning::Point3.new(50 + offset_x, 50, 20)
            ),
            Planning::BoardDescriptor.new(
              identity: female_identity,
              faces: [female_face],
              thickness: female_thickness,
              center: Planning::Point3.new(50 + offset_x, 50, -9)
            )
          ]
        end

        def l_joint_boards
          male_identity = identity('male-l')
          female_identity = identity('female-l')
          male_face = face(male_identity, 'contact', 'edge_face', rectangle(0, 0, 60, 18))
          female_face = face(female_identity, 'contact', 'broad_face', rectangle(0, 0, 100, 100))
          [
            board(male_identity, male_face, center_z: 20),
            board(female_identity, female_face, center_z: -9)
          ]
        end

        def calculator
          Planning::JointLayoutCalculator.new
        end

        def layout_spec(width:, count:, start_offset: 0, end_offset: 0, minimum_gap: 0)
          Planning::JointLayoutSpecification.new(
            joint_length: width,
            fit_clearance: 0.2,
            tenon_height: 10.0,
            mortise_depth: 10.0,
            cutter_radius: 3.0,
            requested_count: count,
            start_offset: start_offset,
            end_offset: end_offset,
            minimum_gap: minimum_gap,
            geometric_tolerance: 0.001
          )
        end

        def calculation_for(specification)
          calculator.calculate(
            contact_length: 100.0,
            axis_min: 0.0,
            specification: specification,
            female_board_thickness: 18.0
          )
        end

        def transform_board(source, transform)
          transformed_faces = source.faces.map do |source_face|
            Planning::FaceDescriptor.new(
              stable_id: source_face.stable_id,
              board_identity: source.identity,
              vertices: source_face.vertices.map { |point| transform.apply_point(point) },
              kind: source_face.kind
            )
          end
          Planning::BoardDescriptor.new(
            identity: source.identity,
            faces: transformed_faces,
            thickness: source.thickness,
            thickness_ambiguous: source.thickness_ambiguous,
            center: transform.apply_point(source.center)
          )
        end

        def shared_box_definition
          box_definition(18.0, 9001)
        end

        def box_definition(thickness, definition_id)
          points = [
            [0, 0, 0], [100, 0, 0], [100, 50, 0], [0, 50, 0],
            [0, 0, thickness], [100, 0, thickness],
            [100, 50, thickness], [0, 50, thickness]
          ].map { |values| Struct.new(:x, :y, :z).new(*values) }
          face_indices = [
            [0, 3, 2, 1], [4, 5, 6, 7],
            [0, 1, 5, 4], [1, 2, 6, 5],
            [2, 3, 7, 6], [3, 0, 4, 7]
          ]
          faces = face_indices.each_with_index.map do |indices, index|
            Sketchup::Face.new(index + 1, indices.map { |point_index| points[point_index] })
          end
          Sketchup::AutomaticPlanningDefinition.new(definition_id, faces)
        end
      end
    end
  end
end
