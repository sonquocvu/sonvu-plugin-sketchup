# frozen_string_literal: true

require 'minitest/autorun'
require 'ripper'

module Sketchup
  class ModelObserver; end
  class Group; end
  class ComponentInstance; end
end

require_relative '../../constants'
require_relative '../automatic_planning/loader'

module SonVu
  module CNCPlugins
    module DogboneJoinery
      class AutomaticPreviewTest < Minitest::Test
        Planning = AutomaticPlanning

        module TestUnits
          module_function

          def millimeters_to_model_units(value)
            value.to_f
          end

          def model_units_to_millimeters(value)
            value.to_f
          end
        end

        class RawAnalyzerStub
          attr_reader :calls

          def initialize(plans)
            @plans = plans
            @calls = 0
          end

          def analyze(_boards, _specification)
            plan = @plans[[@calls, @plans.length - 1].min]
            @calls += 1
            plan
          end
        end

        class ScannerStub
          attr_reader :skipped_entities, :entity_by_part_id, :entity_paths_by_part_id,
                      :transform_snapshots_by_part_id

          def initialize(descriptors, skipped_count = 0)
            @descriptors = descriptors
            @skipped_entities = Array.new(skipped_count) { Object.new }
            @entity_by_part_id = {}
            @entity_paths_by_part_id = {}
            @transform_snapshots_by_part_id = {}
          end

          def scan(_entities, parent_transform:, parent_path:)
            raise 'Thiếu transformation cha.' unless parent_transform
            raise 'Thiếu path cha.' unless parent_path

            @descriptors
          end
        end

        def test_valid_connections_are_included_in_bulk_plan
          result = bulk_result(raw_plan(valid_connection))

          assert_equal 1, result.valid_connection_count
          assert_equal valid_connection.stable_id, result.plan.connections.first.stable_id
          assert_empty result.skipped_connections
        end

        def test_invalid_connections_are_stored_as_lightweight_skipped_records
          invalid = invalid_connection
          result = bulk_result(raw_plan(invalid))

          assert_empty result.plan.connections
          assert_equal 1, result.skipped_connections.length
          record = result.skipped_connections.first
          assert_equal invalid.validation.code, record.reason_code
          assert_equal invalid.first_part_identity.stable_id, record.first_part_id
          assert_empty invalid.joint_instances
        end

        def test_one_invalid_connection_does_not_block_valid_connections
          result = bulk_result(mixed_raw_plan)

          assert_equal 1, result.valid_connection_count
          assert_equal 1, result.skipped_connections.length
          assert_equal valid_connection.joint_instances.length, result.joint_count
        end

        def test_ambiguous_thickness_skips_only_the_affected_connection
          ambiguous = copy_connection(
            valid_connection,
            stable_id: 'connection:ambiguous-thickness',
            validation: Planning::ValidationResult.new(
              Planning::ValidationResult::AMBIGUOUS_BOARD_THICKNESS
            ),
            joint_instances: [],
            enabled: false
          )

          result = bulk_result(raw_plan(valid_connection, ambiguous))

          assert_equal 1, result.valid_connection_count
          assert_equal 1, result.skipped_connections.length
          assert_equal Planning::ValidationResult::AMBIGUOUS_BOARD_THICKNESS,
                       result.skipped_connections.first.reason_code
        end

        def test_infeasible_vertical_tbone_skips_only_the_affected_connection
          result = bulk_result(raw_plan(valid_connection, narrow_tbone_connection))

          assert_equal 1, result.valid_connection_count
          assert_equal valid_connection.stable_id, result.plan.connections.first.stable_id
          assert_equal 1, result.skipped_connections.length
          assert_equal Planning::BulkPreviewAnalyzer::INFEASIBLE_VERTICAL_TBONE,
                       result.skipped_connections.first.reason_code
          assert_in_delta narrow_tbone_connection.joint_instances.first.mortise_opening_thickness,
                          result.skipped_connections.first.details[:mortise_opening_thickness],
                          0.0001
        end

        def test_insufficient_length_skips_only_that_connection
          result = bulk_result(mixed_raw_plan)

          assert_equal Planning::ValidationResult::CONTACT_REGION_TOO_SHORT,
                       result.skipped_connections.first.reason_code
          assert_equal valid_connection.stable_id, result.plan.connections.first.stable_id
        end

        def test_requested_count_is_not_silently_reduced
          invalid = invalid_connection
          result = bulk_result(raw_plan(invalid))
          record = result.skipped_connections.first

          assert_equal invalid.requested_settings.requested_count, record.details[:requested_count]
          assert_operator record.details[:requested_count], :>, record.details[:maximum_feasible_count]
          assert_empty result.plan.connections
          assert_empty invalid.joint_instances
        end

        def test_skipped_reason_codes_are_grouped_correctly
          diagnostic = Planning::AnalysisDiagnostic.new(
            first_part_id: 'a',
            second_part_id: 'b',
            validation: Planning::ValidationResult.new(Planning::ValidationResult::LINE_ONLY_CONTACT)
          )
          plan = Planning::PreviewPlan.new(
            connections: [invalid_connection, copy_connection(invalid_connection,
                                                               stable_id: 'invalid:second')],
            diagnostics: [diagnostic]
          )
          counts = bulk_result(plan).skipped_reason_counts

          assert_equal 2, counts[Planning::ValidationResult::CONTACT_REGION_TOO_SHORT]
          assert_equal 1, counts[Planning::ValidationResult::LINE_ONLY_CONTACT]
        end

        def test_summary_reports_valid_connection_count
          payload = serializer.serialize(calculated_state(mixed_raw_plan))

          assert_equal 1, payload[:summary][:valid_connection_count]
        end

        def test_summary_reports_total_preview_joint_count
          state = calculated_state(raw_plan(valid_connection))
          payload = serializer.serialize(state)

          assert_equal valid_connection.joint_instances.length,
                       payload[:summary][:preview_joint_count]
        end

        def test_summary_reports_skipped_positions_including_ignored_entities
          state = calculated_state(mixed_raw_plan, ignored_entity_count: 2)
          payload = serializer.serialize(state)

          assert_equal 3, payload[:summary][:skipped_position_count]
          assert_equal 2,
                       payload[:skipped_groups].find { |group| group[:reason_code] == 'invalid_entity' }[:count]
          assert_includes payload[:skipped_note], 'mộng đơn lẻ'
        end

        def test_readiness_is_true_with_at_least_one_valid_connection
          state = calculated_state(raw_plan(valid_connection))

          assert state.ready?
          assert_equal 'ready', state.readiness_code
        end

        def test_readiness_remains_true_when_some_connections_are_skipped
          state = calculated_state(mixed_raw_plan)

          assert state.ready?
          assert_equal 1, state.skipped_position_count
        end

        def test_readiness_is_false_when_all_connections_are_skipped
          state = calculated_state(raw_plan(invalid_connection))

          refute state.ready?
          assert_equal 'no_valid_joints', state.readiness_code
        end

        def test_readiness_is_false_when_input_is_invalid
          state = calculated_state(raw_plan(valid_connection))
          state.mark_input_invalid

          refute state.ready?
          assert_equal 'invalid_input', state.readiness_code
          refute state.preview_calculated
        end

        def test_readiness_is_false_when_preview_is_stale
          state = calculated_state(raw_plan(valid_connection))
          state.mark_stale

          refute state.ready?
          assert_equal 'stale_model', state.readiness_code
          assert_includes serializer.serialize(state)[:stale_message], 'bấm Xem trước'
        end

        def test_parameter_recalculation_refreshes_valid_and_skipped_results
          raw = RawAnalyzerStub.new([raw_plan(valid_connection), raw_plan(invalid_connection)])
          state = new_state(raw_analyzer: raw)
          state.calculate_preview(settings)
          assert_equal 1, state.valid_connection_count

          state.recalculate(settings(length: 40.0, count: 8))

          assert_equal 2, raw.calls
          assert_equal 0, state.valid_connection_count
          assert_equal 1, state.skipped_position_count
        end

        def test_no_per_connection_table_state_is_required
          state = calculated_state(mixed_raw_plan)
          payload = serializer.serialize(state)

          refute state.respond_to?(:selected_connection_id)
          refute state.respond_to?(:toggle_connection)
          refute state.respond_to?(:toggle_joint)
          refute state.respond_to?(:reverse_assignment)
          refute payload.key?(:connections)
          refute payload.key?(:selected_connection_id)
        end

        def test_preview_contains_all_valid_joints_simultaneously
          first = valid_connection
          second = copy_connection(first, stable_id: "#{first.stable_id}:second")
          plan = Planning::PreviewPlan.new(connections: [first, second])

          primitives = primitive_builder.build(plan)
          tenons = primitives.select { |primitive| primitive[:kind] == 'tenon_prism' }
          mortises = primitives.select do |primitive|
            primitive[:kind] == 'vertical_tbone_mortise_cavity'
          end
          reliefs = primitives.select do |primitive|
            primitive[:kind] == 'vertical_tbone_relief_markers'
          end

          assert_equal first.joint_instances.length * 2, tenons.length
          assert_equal first.joint_instances.length * 2, mortises.length
          assert_equal first.joint_instances.length * 2, reliefs.length
          assert_equal 2, tenons.map { |primitive| primitive[:connection_id] }.uniq.length
        end

        def test_vertical_tbone_mortise_and_tenon_styles_are_visually_distinct
          primitives = primitive_builder.build(raw_plan(valid_connection))
          tenon = primitives.find { |primitive| primitive[:kind] == 'tenon_prism' }
          mortise = primitives.find do |primitive|
            primitive[:kind] == 'vertical_tbone_mortise_cavity'
          end
          relief = primitives.find do |primitive|
            primitive[:kind] == 'vertical_tbone_relief_markers'
          end

          assert_equal :tenon, tenon[:style]
          assert_equal :mortise, mortise[:style]
          assert_equal 'vertical_tbone', mortise[:mortise_geometry]
          assert_equal 'female_local_y', relief[:relief_orientation]
          assert_equal 3.0, relief[:cutter_radius]
          assert_in_delta 17.8, tenon[:tenon_thickness], 0.0001
          assert_in_delta 18.0, mortise[:mortise_opening_thickness], 0.0001
          assert_in_delta 18.0, mortise[:detected_male_board_thickness], 0.0001
          assert_in_delta 0.2, mortise[:fit_clearance], 0.0001
          assert_equal '', Planning::PreviewDisplayStyles.fetch(:tenon)[:line_stipple]
          assert_equal '-', Planning::PreviewDisplayStyles.fetch(:mortise)[:line_stipple]
          refute_equal Planning::PreviewDisplayStyles.fetch(:tenon)[:color],
                       Planning::PreviewDisplayStyles.fetch(:mortise)[:color]
        end

        def test_preview_geometry_uses_finalized_tenon_and_mortise_thicknesses
          primitives = primitive_builder.build(raw_plan(valid_connection))
          tenon = primitives.find { |primitive| primitive[:kind] == 'tenon_prism' }
          mortise = primitives.find do |primitive|
            primitive[:kind] == 'vertical_tbone_mortise_cavity'
          end
          joint = valid_connection.joint_instances.first
          axis = joint.thickness_axis

          assert_in_delta joint.tenon_thickness, projected_extent(tenon[:points], axis), 0.0001
          assert_in_delta joint.mortise_opening_thickness,
                          projected_extent(mortise[:points], axis), 0.0001
          assert_in_delta joint.tenon_height, tenon[:display_depth], 0.0001
          assert_in_delta joint.mortise_depth, mortise[:display_depth], 0.0001
        end

        def test_global_display_toggles_hide_only_requested_primitive_roles
          display = Planning::PreviewDisplaySettings.new(
            show_tenons: false,
            show_mortises: true,
            show_contact_region: false,
            show_legend: true
          )
          primitives = primitive_builder.build(
            raw_plan(valid_connection),
            display_settings: display
          )

          refute primitives.any? { |primitive| primitive[:kind] == 'tenon_prism' }
          assert(primitives.any? do |primitive|
            primitive[:kind] == 'vertical_tbone_mortise_cavity'
          end)
          assert(primitives.any? do |primitive|
            primitive[:kind] == 'vertical_tbone_relief_markers'
          end)
          refute primitives.any? { |primitive| primitive[:kind] == 'contact_boundary' }
        end

        def test_skipped_connections_are_never_rendered
          plan = Planning::PreviewPlan.new(connections: [invalid_connection])

          primitives = primitive_builder.build(plan)

          refute(primitives.any? do |primitive|
            %w[tenon_prism vertical_tbone_mortise_cavity vertical_tbone_relief_markers]
              .include?(primitive[:kind])
          end)
        end

        def test_automatic_preview_never_builds_a_normal_mortise_primitive
          primitives = primitive_builder.build(raw_plan(valid_connection))

          assert primitives.any? { |primitive| primitive[:mortise_geometry] == 'vertical_tbone' }
          refute primitives.any? { |primitive| primitive[:kind] == 'mortise_cavity' }
          refute primitives.any? { |primitive| primitive[:mortise_geometry] == 'normal' }
        end

        def test_vertical_tbone_relief_uses_stored_female_local_axes
          joint = valid_connection.joint_instances.first
          rotated_female = Planning::PlacementData.new(
            origin: joint.center_position,
            x_axis: Planning::Vector3.new(0, 1, 0),
            y_axis: Planning::Vector3.new(0, 0, 1),
            z_axis: Planning::Vector3.new(1, 0, 0),
            insertion_direction: Planning::Vector3.new(-1, 0, 0)
          )
          rotated_joint = Planning::JointInstancePlan.new(
            stable_id: joint.stable_id,
            index: joint.index,
            center_position: joint.center_position,
            start_position: joint.start_position,
            end_position: joint.end_position,
            joint_length: joint.joint_length,
            detected_male_board_thickness: joint.detected_male_board_thickness,
            tenon_thickness: joint.tenon_thickness,
            mortise_opening_thickness: joint.mortise_opening_thickness,
            fit_clearance: joint.fit_clearance,
            tenon_height: joint.tenon_height,
            mortise_depth: joint.mortise_depth,
            cutter_radius: joint.cutter_radius,
            thickness_axis: rotated_female.y_axis.normalized.canonical,
            male_placement: joint.male_placement,
            female_placement: rotated_female,
            enabled: true
          )
          connection = copy_connection(valid_connection, joint_instances: [rotated_joint])
          marker = primitive_builder.build(raw_plan(connection)).find do |primitive|
            primitive[:kind] == 'vertical_tbone_relief_markers'
          end

          refute_nil marker
          assert(marker[:points].all? do |point|
            (point.x - joint.center_position.x).abs < 1.0e-8
          end)
          assert_operator marker[:points].map(&:z).uniq.length, :>, 2
        end

        def test_clearing_preview_removes_all_plans_and_readiness
          state = calculated_state(raw_plan(valid_connection))
          state.clear_preview

          assert_empty state.plan.connections
          assert_empty state.skipped_connections
          refute state.preview_calculated
          refute state.ready?
        end

        def test_shared_edge_offset_is_validated_in_ruby_and_applied_to_both_ends
          parsed = settings_parser.parse(valid_payload)

          assert_equal 20.0, parsed.specification.start_offset
          assert_equal 20.0, parsed.specification.end_offset
          error = assert_raises(Planning::PreviewSettingsError) do
            settings_parser.parse(valid_payload.merge('edge_offset_mm' => '-1'))
          end
          assert_equal 'edge_offset_mm', error.field
        end

        def test_compact_dialog_has_only_bulk_controls_and_summary
          ui_root = File.expand_path('../automatic_planning/ui', __dir__)
          html = File.read(File.join(ui_root, 'automatic_preview.html'), encoding: 'UTF-8')
          javascript = File.read(File.join(ui_root, 'automatic_preview.js'), encoding: 'UTF-8')

          assert_includes html, 'Tạo mộng âm dương tự động'
          assert_includes html, 'Chi tiết đã quét'
          assert_includes html, 'Liên kết hợp lệ'
          assert_includes html, 'Vị trí bị bỏ qua'
          assert_includes html, 'Xem lý do bỏ qua'
          assert_includes html, '>Xem trước<'
          assert_includes html, '>Tính lại<'
          assert_includes html, '>Tạo mộng<'
          assert_includes html, 'Mộng âm tự động sử dụng kiểu dọc T-bone.'
          assert_includes html, 'Chiều dài mộng'
          assert_includes html, 'Chiều cao mộng dương'
          assert_includes html, 'Bề dày mộng được tự động tính theo độ dày của từng tấm.'
          assert_includes html, 'id="joint_length_mm"'
          refute_includes html, 'id="joint_thickness_mm"'
          refute_includes html, 'Chiều dày mộng'
          refute_includes html, 'Bề dày mộng</span>'
          refute_includes javascript, 'joint_thickness_mm'
          refute_includes html, '<select'
          refute_includes html, 'Kiểu mộng âm'
          refute_includes html, 'Kiểu khoét góc mộng âm'
          refute_includes html, 'tenon_relief_enabled'
          refute_includes javascript, 'dogbone_style'
          refute_includes javascript, 'tenon_style'
          refute_includes javascript, 'tenon_relief_enabled'
          refute_includes html, '<table'
          refute_includes html, 'Đảo mộng'
          refute_includes javascript, 'select_connection'
          refute_includes javascript, 'toggle_joint'
          refute_includes javascript, 'reverse_assignment'
          %w[preview_selection recalculate_preview ready_for_generation close_preview].each do |callback|
            assert_includes javascript, "send('#{callback}'"
          end
        end

        def test_joint_length_remains_configurable_without_a_global_thickness
          parsed = settings_parser.parse(valid_payload.merge('joint_length_mm' => '25.5'))

          assert_in_delta 25.5, parsed.specification.joint_length, 0.0001
          refute parsed.to_h.key?(:joint_thickness_mm)
          refute parsed.specification.to_h.key?(:joint_thickness)
        end

        def test_historical_joint_width_mm_migrates_only_as_the_along_edge_length
          payload = valid_payload.dup
          payload.delete('joint_length_mm')
          payload['joint_width_mm'] = '22'
          payload['joint_width'] = '999'

          parsed = settings_parser.parse(payload)

          assert_in_delta 22.0, parsed.specification.joint_length, 0.0001
          assert_in_delta 22.0, parsed.to_h[:joint_length_mm], 0.0001
          refute parsed.to_h.key?(:joint_width_mm)
          refute parsed.to_h.key?(:joint_width)
        end

        def test_obsolete_automatic_thickness_fields_cannot_override_board_geometry
          legacy = valid_payload.merge(
            'edge_offset_mm' => '5',
            'joint_thickness_mm' => '2',
            'joint_thickness' => '3',
            'tenon_thickness' => '4',
            'mortise_width' => '5'
          )
          parsed = settings_parser.parse(legacy)
          connection = Planning::Analyzer.new.analyze(
            t_joint_boards,
            parsed.specification
          ).connections.first
          joint = connection.joint_instances.first

          assert_in_delta 18.0, joint.detected_male_board_thickness, 0.0001
          assert_in_delta 17.8, joint.tenon_thickness, 0.0001
          assert_in_delta 18.0, joint.mortise_opening_thickness, 0.0001
          %i[joint_thickness_mm joint_thickness tenon_thickness mortise_width].each do |field|
            refute parsed.to_h.key?(field)
          end
        end

        def test_selection_still_accepts_complete_group_and_component_sets
          resolver = Planning::PreviewSelectionResolver.new(scanner: ScannerStub.new(t_joint_boards, 1))
          resolution = resolver.resolve([Sketchup::Group.new, Sketchup::ComponentInstance.new])

          assert resolution.valid?
          assert_equal 1, resolution.ignored_entity_count
          assert_equal 2, resolution.board_descriptors.length
        end

        def test_legacy_joint_style_payloads_are_accepted_but_not_persisted
          legacy_values = [
            { 'mortise_style' => 'standard' },
            { 'mortise_type' => 't_bone_vertical' },
            { 'dogbone_style' => 'Ngang (T-bone)' },
            { 'joint_style' => 'standard', 'tenon_style' => 'obsolete' },
            { 'male_joint_type' => 'legacy', 'tenon_relief_enabled' => false }
          ]

          legacy_values.each do |legacy|
            parsed = settings_parser.parse(valid_payload.merge(legacy))
            keys = parsed.to_h.keys.map(&:to_s)
            refute_includes keys, 'mortise_style'
            refute_includes keys, 'mortise_type'
            refute_includes keys, 'dogbone_style'
            refute_includes keys, 'joint_style'
            refute_includes keys, 'tenon_style'
            refute_includes keys, 'male_joint_type'
            refute_includes keys, 'tenon_relief_enabled'
          end
        end

        def test_new_automatic_settings_and_serialized_state_have_no_style_fields
          parsed = settings_parser.parse(valid_payload)
          state = calculated_state(raw_plan(valid_connection))
          keys = parsed.to_h.keys.map(&:to_s)
          serialized_keys = serializer.serialize(state)[:settings].keys.map(&:to_s)
          assert_includes keys, 'joint_length_mm'
          assert_includes keys, 'tenon_height_mm'
          assert_includes serialized_keys, 'joint_length_mm'
          assert_includes serialized_keys, 'tenon_height_mm'
          obsolete = %w[
            mortise_style mortise_type dogbone_style joint_style tenon_style
            male_joint_type tenon_relief_enabled joint_thickness_mm
            joint_thickness tenon_thickness mortise_width
          ]

          obsolete.each do |field|
            refute_includes Planning::PreviewSettings::KEYS.map(&:to_s), field
            refute_includes keys, field
            refute_includes serialized_keys, field
          end
        end

        def test_command_uses_simplified_bulk_label_and_manual_commands_remain
          commands = File.read(File.expand_path('../commands.rb', __dir__), encoding: 'UTF-8')

          assert_equal 'Tạo mộng tự động', CNCPlugins::COMMAND_AUTOMATIC_JOINT_PREVIEW
          assert_includes commands, 'COMMAND_CREATE_DOGBONE_MORTISE'
          assert_includes commands, 'COMMAND_CREATE_DOGBONE_TENON'
          assert_includes commands, 'COMMAND_AUTOMATIC_JOINT_PREVIEW'
        end

        def test_closing_session_explicitly_clears_preview
          source = File.read(File.expand_path('../automatic_planning/preview_session.rb', __dir__), encoding: 'UTF-8')

          assert_match(/def close\(dialog_closed: false\).*?state\.clear_preview/m, source)
          assert_includes source, 'model.active_view.invalidate'
        end

        def test_committed_geometry_change_invalidates_execution_readiness
          state = calculated_state(raw_plan(valid_connection))
          session = Struct.new(:preview_state) do
            def mark_stale_from_model
              preview_state.mark_stale
            end
          end.new(state)
          observer = Planning::PreviewModelObserver.new(session)

          assert state.ready?
          observer.onTransactionCommit(Object.new)

          assert state.stale
          refute state.ready?
          assert_equal 'stale_model', state.readiness_code
        end

        def test_production_code_remains_non_mutating_and_ruby_27_compatible
          root = File.expand_path('../automatic_planning', __dir__)
          files = Dir.children(root).select { |name| File.extname(name) == '.rb' }.map do |name|
            File.join(root, name)
          end
          files << File.expand_path('../vertical_tbone_geometry.rb', __dir__)
          source = files.map { |path| File.read(path, encoding: 'UTF-8') }.join("\n")

          refute_match(/\.start_operation\b|\.commit_operation\b|\.abort_operation\b/, source)
          refute_match(/\.set_attribute\b|\.add_face\b|\.add_group\b|\.union\b|\.subtract\b/, source)
          files.each do |path|
            file_source = File.read(path, encoding: 'UTF-8')
            refute_nil Ripper.sexp(file_source), "Không phân tích được cú pháp: #{path}"
            refute_match(
              /^\s*def\s+[a-zA-Z_]\w*[!?=]?\s*(?:\([^)]*\))?\s*=\s*[^\n]+$/,
              file_source,
              "Không dùng endless method của Ruby 3: #{path}"
            )
          end
        end

        private

        def settings_parser
          Planning::PreviewSettingsParser.new(unit_converter: TestUnits)
        end

        def serializer
          Planning::PreviewStateSerializer.new(unit_converter: TestUnits)
        end

        def primitive_builder
          Planning::PreviewPrimitiveBuilder.new
        end

        def valid_payload
          {
            'joint_length_mm' => '10',
            'requested_count' => '3',
            'edge_offset_mm' => '20',
            'minimum_gap_mm' => '2'
          }
        end

        def settings(length: 10.0, count: 3, edge_offset: 5.0,
                     minimum_gap: 2.0, cutter_radius: 3.0)
          values = {
            joint_length_mm: length,
            mortise_depth_mm: 10.0,
            tenon_height_mm: 10.0,
            cutter_radius_mm: cutter_radius,
            clearance_mm: 0.2,
            requested_count: count,
            start_offset_mm: edge_offset,
            end_offset_mm: edge_offset,
            minimum_gap_mm: minimum_gap,
            geometric_tolerance_mm: 0.01
          }
          specification = Planning::JointLayoutSpecification.new(
            joint_length: length,
            fit_clearance: 0.2,
            tenon_height: 10.0,
            mortise_depth: 10.0,
            cutter_radius: cutter_radius,
            requested_count: count,
            start_offset: edge_offset,
            end_offset: edge_offset,
            minimum_gap: minimum_gap,
            geometric_tolerance: 0.01
          )
          Planning::PreviewSettings.new(
            values_mm: values,
            specification: specification,
            cutter_radius: cutter_radius
          )
        end

        def raw_plan(*connections)
          Planning::PreviewPlan.new(connections: connections.flatten)
        end

        def mixed_raw_plan
          raw_plan(valid_connection, invalid_connection)
        end

        def bulk_result(plan)
          Planning::BulkPreviewAnalyzer.new(analyzer: RawAnalyzerStub.new([plan])).analyze(
            t_joint_boards,
            settings.specification
          )
        end

        def new_state(raw_analyzer:, ignored_entity_count: 0)
          Planning::PreviewState.new(
            board_descriptors: t_joint_boards,
            settings: settings,
            ignored_entity_count: ignored_entity_count,
            bulk_analyzer: Planning::BulkPreviewAnalyzer.new(analyzer: raw_analyzer)
          )
        end

        def calculated_state(plan, ignored_entity_count: 0)
          state = new_state(
            raw_analyzer: RawAnalyzerStub.new([plan]),
            ignored_entity_count: ignored_entity_count
          )
          state.calculate_preview
        end

        def valid_connection
          @valid_connection ||= Planning::Analyzer.new.analyze(
            t_joint_boards,
            settings.specification
          ).connections.first
        end

        def invalid_connection
          @invalid_connection ||= begin
            plan = Planning::Analyzer.new.analyze(
              t_joint_boards,
              settings(length: 20.0, count: 8, edge_offset: 5.0, minimum_gap: 5.0).specification
            )
            copy_connection(plan.connections.first, stable_id: 'connection:invalid-short')
          end
        end

        def narrow_tbone_connection
          @narrow_tbone_connection ||= begin
            joints = valid_connection.joint_instances.map do |joint|
              Planning::JointInstancePlan.new(
                stable_id: "#{joint.stable_id}:narrow",
                index: joint.index,
                center_position: joint.center_position,
                start_position: joint.start_position,
                end_position: joint.end_position,
                joint_length: 2.0,
                detected_male_board_thickness: joint.detected_male_board_thickness,
                tenon_thickness: joint.tenon_thickness,
                mortise_opening_thickness: joint.mortise_opening_thickness,
                fit_clearance: joint.fit_clearance,
                tenon_height: joint.tenon_height,
                mortise_depth: joint.mortise_depth,
                cutter_radius: joint.cutter_radius,
                thickness_axis: joint.thickness_axis,
                male_placement: joint.male_placement,
                female_placement: joint.female_placement,
                enabled: true
              )
            end
            copy_connection(
              valid_connection,
              stable_id: "#{valid_connection.stable_id}:narrow",
              joint_instances: joints
            )
          end
        end

        def copy_connection(connection, changes = {})
          attributes = Planning::ConnectionPlan::ATTRIBUTES.each_with_object({}) do |name, result|
            result[name] = connection.public_send(name)
          end
          changes.each { |name, value| attributes[name] = value }
          Planning::ConnectionPlan.new(attributes)
        end

        def identity(id)
          Planning::PartIdentity.new(
            stable_id: id,
            persistent_id: id,
            definition_id: "definition-#{id}",
            instance_path: [id],
            display_name: "Tấm #{id}"
          )
        end

        def t_joint_boards
          male_identity = identity('male')
          female_identity = identity('female')
          male_face = Planning::FaceDescriptor.new(
            stable_id: 'male:contact',
            board_identity: male_identity,
            vertices: rectangle(20, 40, 80, 58),
            kind: 'edge_face'
          )
          female_face = Planning::FaceDescriptor.new(
            stable_id: 'female:contact',
            board_identity: female_identity,
            vertices: rectangle(0, 0, 100, 100),
            kind: 'broad_face'
          )
          [
            Planning::BoardDescriptor.new(
              identity: male_identity,
              faces: [male_face],
              thickness: 18.0,
              center: Planning::Point3.new(50, 50, 20)
            ),
            Planning::BoardDescriptor.new(
              identity: female_identity,
              faces: [female_face],
              thickness: 18.0,
              center: Planning::Point3.new(50, 50, -9)
            )
          ]
        end

        def rectangle(min_x, min_y, max_x, max_y)
          [
            Planning::Point3.new(min_x, min_y, 0),
            Planning::Point3.new(max_x, min_y, 0),
            Planning::Point3.new(max_x, max_y, 0),
            Planning::Point3.new(min_x, max_y, 0)
          ]
        end

        def projected_extent(points, axis)
          unit_axis = axis.normalized
          values = points.map do |point|
            Planning::Vector3.new(point.x, point.y, point.z).dot(unit_axis)
          end
          values.max - values.min
        end
      end
    end
  end
end
