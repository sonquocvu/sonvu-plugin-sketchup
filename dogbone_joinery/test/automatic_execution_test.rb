# frozen_string_literal: true

require 'minitest/autorun'
require 'ripper'
require 'stringio'
require 'tmpdir'

module Sketchup
  class ModelObserver; end unless const_defined?(:ModelObserver)
  class Group; end unless const_defined?(:Group)
  class ComponentInstance; end unless const_defined?(:ComponentInstance)
end

module Geom
  Point3d = Struct.new(:x, :y, :z) unless const_defined?(:Point3d)
end

require_relative '../../constants'
require_relative '../../shared/units'
require_relative '../automatic_planning/loader'
require_relative '../geometry'
require_relative '../automatic_execution/loader'

module SonVu
  module CNCPlugins
    module UIHelpers
      class << self
        attr_accessor :last_test_message

        def message(value)
          self.last_test_message = value
        end
      end
    end unless const_defined?(:UIHelpers)

    module DogboneJoinery
      class AutomaticExecutionTest < Minitest::Test
        Planning = AutomaticPlanning
        Execution = AutomaticExecution

        module TestUnits
          module_function

          def millimeters_to_model_units(value)
            value.to_f
          end

          def model_units_to_millimeters(value)
            value.to_f
          end
        end

        class FakeEntities
          def initialize(children = [])
            @children = children
          end

          def to_a
            @children.dup
          end

          def replace_children(children)
            @children = children
          end

          def add_group
            Object.new
          end
        end

        class FakeDefinition
          attr_reader :persistent_id, :instances, :entities

          def initialize(persistent_id, instances: [], entities: FakeEntities.new)
            @persistent_id = persistent_id
            @instances = instances
            @entities = entities
          end
        end

        class FakeEntity
          attr_accessor :transformation, :parent, :definition, :valid_state
          attr_reader :persistent_id, :make_unique_count

          def initialize(persistent_id, definition_id:, parent: FakeEntities.new,
                         transformation: Planning::Transform3.identity)
            @persistent_id = persistent_id
            @parent = parent
            @transformation = transformation
            @definition = FakeDefinition.new(definition_id, instances: [self])
            @valid_state = true
            @make_unique_count = 0
          end

          def valid?
            valid_state
          end

          def manifold?
            true
          end

          def union(_other)
            self
          end

          def subtract(_other)
            self
          end

          def make_unique
            @make_unique_count += 1
            previous = definition
            previous.instances.delete(self)
            @definition = FakeDefinition.new(
              "#{previous.persistent_id}-unique-#{make_unique_count}",
              instances: [self],
              entities: previous.entities
            )
            self
          end
        end

        class FakeModel
          attr_reader :started_operations, :commit_count, :abort_count, :active_view

          def initialize
            @started_operations = []
            @commit_count = 0
            @abort_count = 0
            @active_view = FakeView.new
          end

          def start_operation(name, transparent)
            @started_operations << [name, transparent]
            true
          end

          def commit_operation
            @commit_count += 1
          end

          def abort_operation
            @abort_count += 1
          end

          def remove_observer(_observer); end

          def select_tool(_tool); end
        end

        class FakeView
          attr_reader :invalidate_count

          def initialize
            @invalidate_count = 0
          end

          def invalidate
            @invalidate_count += 1
          end
        end

        class RecordingGeometryAdapter
          attr_reader :calls

          def initialize(fail_on_call: nil, invalid_on_call: nil)
            @calls = []
            @fail_on_call = fail_on_call
            @invalid_on_call = invalid_on_call
          end

          def generate_tenon(target:, params:, placement:, parent_entities:)
            generate(:tenon, target, params, placement, parent_entities)
          end

          def generate_mortise(target:, params:, placement:, parent_entities:)
            generate(:mortise, target, params, placement, parent_entities)
          end

          private

          def generate(kind, target, params, placement, parent_entities)
            @calls << {
              kind: kind,
              target: target,
              params: params,
              placement: placement,
              parent_entities: parent_entities
            }
            raise 'Lỗi boolean thử nghiệm.' if @fail_on_call == calls.length
            return Object.new if @invalid_on_call == calls.length

            FakeEntity.new(
              "result-#{calls.length}",
              definition_id: "result-definition-#{calls.length}",
              parent: parent_entities
            )
          end
        end

        class RecordingDiagnosticLogger
          attr_reader :errors

          def initialize
            @errors = []
          end

          def record(error)
            errors << error
            detail = if error.respond_to?(:details)
                       error.details[:error_message] || error.message
                     else
                       error.message
                     end
            Execution::AutomaticJointDiagnosticLogger::Entry.new(
              'SVJ-TEST-001',
              'C:\\SonVu\\automatic_joint_diagnostics.log',
              detail
            )
          end
        end

        class RecordingParameterAdapter
          def tenon_parameters(connection, joint, _settings)
            { connection_id: connection.stable_id, joint_id: joint.stable_id, kind: :tenon }
          end

          def mortise_parameters(connection, joint, _settings)
            { connection_id: connection.stable_id, joint_id: joint.stable_id, kind: :mortise }
          end
        end

        class FakeDialog
          attr_reader :scripts, :closed

          def initialize
            @scripts = []
            @closed = false
          end

          def execute_script(script)
            @scripts << script
          end

          def close
            @closed = true
          end
        end

        class FakeAttributeDictionary
          attr_reader :name

          def initialize(name, values)
            @name = name
            @values = values
          end

          def each_pair(&block)
            @values.each_pair(&block)
          end
        end

        class FakePropertyEntity
          attr_accessor :name, :material, :layer, :definition
          attr_reader :written_attributes

          def initialize(name:, material:, layer:, dictionaries: [], definition: nil)
            @name = name
            @material = material
            @layer = layer
            @dictionaries = dictionaries
            @definition = definition
            @written_attributes = {}
          end

          def attribute_dictionaries
            @dictionaries
          end

          def set_attribute(dictionary, key, value)
            @written_attributes[[dictionary, key]] = value
          end
        end

        class ResultExecutor
          attr_reader :calls

          def initialize(result)
            @result = result
            @calls = []
          end

          def execute(**arguments)
            @calls << arguments
            @result
          end
        end

        def setup
          @settings = build_settings
          @connection = Planning::Analyzer.new.analyze(
            t_joint_boards,
            @settings.specification
          ).connections.first
          refute_nil @connection
        end

        def test_executor_accepts_only_finalized_non_stale_plans
          unfinished = execute(finalized: false)
          stale = execute(stale: true)

          refute unfinished.success?
          assert_equal 'plan_not_finalized', unfinished.failure_code
          refute stale.success?
          assert_equal 'preview_stale', stale.failure_code
          assert_empty @last_model.started_operations
        end

        def test_skipped_and_invalid_connections_are_never_executed
          invalid = copy_connection(@connection, stable_id: 'connection:disabled', enabled: false)
          result = execute(plan: Planning::PreviewPlan.new(connections: [invalid]))

          refute result.success?
          assert_equal 'no_executable_joints', result.failure_code
          assert_empty @last_geometry.calls
          assert_empty @last_model.started_operations
        end

        def test_valid_connections_continue_despite_planning_skips
          result = execute(skipped_count: 4)

          assert result.success?
          assert_equal @connection.joint_instances.length * 2, @last_geometry.calls.length
          assert_equal 4, result.skipped_planning_count
        end

        def test_execution_order_is_connection_then_joint_stable_id
          first_joint = copy_joint(
            @connection.joint_instances.first,
            stable_id: 'joint:z',
            center: @connection.joint_instances.first.center_position
          )
          second_center = @connection.joint_instances.last.center_position + Planning::Vector3.new(0, 1, 0)
          second_joint = copy_joint(
            @connection.joint_instances.last,
            stable_id: 'joint:a',
            center: second_center
          )
          plan = Planning::PreviewPlan.new(
            connections: [copy_connection(@connection, joint_instances: [first_joint, second_joint])]
          )

          result = execute(plan: plan)

          assert result.success?
          generated_ids = @last_geometry.calls.select { |call| call[:kind] == :tenon }
                                       .map { |call| call[:params][:joint_id] }
          assert_equal %w[joint:a joint:z], generated_ids
        end

        def test_duplicate_joint_ids_are_rejected_before_operation
          source = @connection.joint_instances.first
          other = @connection.joint_instances.last
          duplicate = copy_joint(other, stable_id: source.stable_id, center: other.center_position)
          plan = Planning::PreviewPlan.new(
            connections: [copy_connection(@connection, joint_instances: [source, duplicate])]
          )

          result = execute(plan: plan)

          refute result.success?
          assert_equal 'duplicate_joint_id', result.failure_code
          assert_empty @last_model.started_operations
        end

        def test_reverse_duplicate_geometry_is_rejected
          joint = @connection.joint_instances.first
          reversed = copy_connection(
            @connection,
            stable_id: 'connection:reverse',
            male_part_identity: @connection.female_part_identity,
            female_part_identity: @connection.male_part_identity,
            joint_instances: [copy_joint(joint, stable_id: 'joint:reverse', center: joint.center_position)]
          )
          original = copy_connection(@connection, joint_instances: [joint])

          result = execute(plan: Planning::PreviewPlan.new(connections: [original, reversed]))

          refute result.success?
          assert_equal 'duplicate_part_pair', result.failure_code
          assert_empty @last_model.started_operations
        end

        def test_stale_entity_identity_is_rejected_before_operation
          entities = entities_for(@connection)
          entities.fetch(@connection.male_part_identity.stable_id).instance_variable_set(
            :@persistent_id,
            'changed-id'
          )

          result = execute(entities: entities)

          refute result.success?
          assert_equal 'persistent_identity_changed', result.failure_code
          assert_empty @last_model.started_operations
        end

        def test_changed_transform_is_rejected_before_operation
          entities = entities_for(@connection)
          male = entities.fetch(@connection.male_part_identity.stable_id)
          resolution = resolution_for(entities)
          male.transformation = Planning::Transform3.translation(5, 0, 0)

          result = execute(entities: entities, resolution: resolution)

          refute result.success?
          assert_equal 'transform_changed', result.failure_code
          assert_empty @last_model.started_operations
        end

        def test_geometry_settings_must_match_finalized_snapshot
          assert execute.success?

          changed = build_settings(length: 12.0)
          result = execute(current_settings: changed)

          refute result.success?
          assert_equal 'settings_changed', result.failure_code
          assert_empty @last_model.started_operations
        end

        def test_male_and_female_inputs_use_same_shared_center_and_planned_axes
          result = execute
          pair = @last_geometry.calls.first(2)
          joint = @connection.joint_instances.sort_by(&:stable_id).first

          assert result.success?
          assert_equal [:tenon, :mortise], pair.map { |call| call[:kind] }
          assert_equal joint.center_position, pair[0][:placement].world_center
          assert_equal joint.center_position, pair[1][:placement].world_center
          assert_equal joint.male_placement.z_axis, pair[0][:placement].z_axis
          assert_equal joint.female_placement.z_axis, pair[1][:placement].z_axis
          assert_equal joint.male_placement.insertion_direction,
                       pair[0][:placement].execution_direction
          assert_equal joint.female_placement.insertion_direction,
                       pair[1][:placement].execution_direction
          assert_equal joint.male_placement.insertion_direction,
                       pair[0][:placement].world_execution_direction
          assert_equal joint.thickness_axis,
                       joint.male_placement.y_axis.normalized.canonical
          assert_equal joint.thickness_axis,
                       joint.female_placement.y_axis.normalized.canonical
        end

        def test_nested_rotated_and_mirrored_transform_is_inverted_by_adapter
          parent = Planning::Transform3.new([
            0, 2, 0, 0,
            -1, 0, 0, 0,
            0, 0, -1, 0,
            10, 20, 30, 1
          ])
          reference = Struct.new(:parent_world_transform).new(parent)
          joint = @connection.joint_instances.first

          placement = Execution::JointTransformAdapter.new.placement_for(
            @connection,
            joint,
            reference,
            :male
          )

          assert_point_close joint.center_position, parent.apply_point(placement.center)
          assert_vector_close joint.male_placement.x_axis, parent.apply_vector(placement.x_axis)
          assert_vector_close joint.male_placement.y_axis, parent.apply_vector(placement.y_axis)
          assert_vector_close joint.male_placement.z_axis, parent.apply_vector(placement.z_axis)
          assert_vector_close joint.male_placement.insertion_direction,
                              parent.apply_vector(placement.execution_direction)
          assert_equal joint.male_placement.insertion_direction,
                       placement.world_execution_direction
        end

        def test_non_invertible_transform_is_rejected
          singular = Planning::Transform3.new([
            1, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
          ])
          reference = Struct.new(:parent_world_transform).new(singular)

          error = assert_raises(Execution::JointExecutionFailure) do
            Execution::JointTransformAdapter.new.placement_for(
              @connection,
              @connection.joint_instances.first,
              reference,
              :male
            )
          end

          assert_equal 'unsupported_transform', error.code
        end

        def test_shared_component_instance_is_made_unique_without_modifying_sibling
          selected = FakeEntity.new('male', definition_id: 'definition-male')
          sibling = FakeEntity.new('sibling', definition_id: 'definition-male')
          shared = FakeDefinition.new('definition-male', instances: [selected, sibling])
          selected.definition = shared
          sibling.definition = shared
          resolution = resolution_for({ 'male' => selected })
          identity = identity('male')
          registry = Execution::ExecutionEntityRegistry.new(resolution)

          registry.validate_for!(identity, :male)
          registry.ensure_unique_all!

          assert_equal 1, selected.make_unique_count
          assert_equal 0, sibling.make_unique_count
          assert_includes shared.instances, sibling
          refute_includes shared.instances, selected
        end

        def test_unshared_instance_is_not_made_unique
          selected = FakeEntity.new('male', definition_id: 'definition-male')
          registry = Execution::ExecutionEntityRegistry.new(resolution_for({ 'male' => selected }))

          registry.validate_for!(identity('male'), :male)
          registry.ensure_unique_all!

          assert_equal 0, selected.make_unique_count
        end

        def test_shared_active_context_is_made_unique_before_nested_part_changes
          selected = FakeEntity.new('male', definition_id: 'definition-male')
          active = FakeEntity.new('active', definition_id: 'definition-active')
          active.definition.entities.replace_children([selected])
          active_sibling = FakeEntity.new('active-sibling', definition_id: 'definition-active')
          shared = FakeDefinition.new(
            'definition-active',
            instances: [active, active_sibling],
            entities: active.definition.entities
          )
          active.definition = shared
          active_sibling.definition = shared
          resolution = Planning::PreviewSelectionResolution.new(
            board_descriptors: t_joint_boards,
            ignored_entity_count: 0,
            warnings: [],
            entity_by_part_id: { 'male' => selected },
            entity_paths_by_part_id: { 'male' => [selected] },
            transform_snapshots_by_part_id: {
              'male' => [Planning::Transform3.identity.values]
            },
            active_path_entities: [active],
            active_path_snapshot: [Planning::Transform3.identity.values]
          )
          registry = Execution::ExecutionEntityRegistry.new(resolution)

          registry.validate_for!(identity('male'), :male)
          registry.ensure_unique_all!

          assert_equal 1, active.make_unique_count
          assert_equal 0, active_sibling.make_unique_count
          assert_equal 0, selected.make_unique_count
        end

        def test_success_starts_and_commits_exactly_one_operation
          result = execute

          assert result.success?
          assert_equal [['Tạo mộng âm dương tự động', true]], @last_model.started_operations
          assert_equal 1, @last_model.commit_count
          assert_equal 0, @last_model.abort_count
        end

        def test_geometry_failure_aborts_complete_batch_with_diagnostics
          geometry = RecordingGeometryAdapter.new(fail_on_call: 3)

          result = execute(geometry: geometry)

          refute result.success?
          assert_equal 'tenon_geometry_failed', result.failure_code
          assert_equal 1, @last_model.started_operations.length
          assert_equal 0, @last_model.commit_count
          assert_equal 1, @last_model.abort_count
          assert_operator geometry.calls.length, :>, 2
          assert_equal 'SVJ-TEST-001', result.failure_details[:diagnostic_id]
          assert_equal 'Lỗi boolean thử nghiệm.', result.failure_details[:diagnostic_detail]
          assert_equal 'tenon', result.failure_details[:context][:execution_role]
          assert_includes result.failure_details[:diagnostic_log_path], 'automatic_joint_diagnostics.log'
        end

        def test_diagnostic_logger_writes_root_error_context_and_backtrace
          path = File.join(Dir.tmpdir, "sonvu-joint-diagnostic-#{object_id}.log")
          console = StringIO.new
          console_controller = Struct.new(:show_count) do
            def show
              self.show_count += 1
            end
          end.new(0)
          clock = lambda { Time.new(2026, 7, 16, 18, 30, 0, '+07:00') }
          logger = Execution::AutomaticJointDiagnosticLogger.new(
            path: path,
            clock: clock,
            console: console,
            console_controller: console_controller
          )
          error = Execution::JointExecutionFailure.new(
            'mortise_geometry_failed',
            'Không thể cắt mộng âm.',
            execution_role: 'mortise',
            connection_id: 'connection-1',
            joint_id: 'joint-1',
            error_message: 'SketchUp subtract trả về nil.'
          )
          error.set_backtrace(['geometry.rb:88', 'executor.rb:66'])

          entry = logger.record(error)
          content = File.read(path, encoding: 'UTF-8')

          assert_match(/\ASVJ-20260716-183000-[0-9A-F]{4}-001\z/, entry.id)
          assert_equal path, entry.path
          assert_equal 'SketchUp subtract trả về nil.', entry.detail
          assert_includes content, 'code=mortise_geometry_failed'
          assert_includes content, 'execution_role: "mortise"'
          assert_includes content, 'connection_id: "connection-1"'
          assert_includes content, 'geometry.rb:88'
          assert_includes console.string, entry.id
          assert_operator console_controller.show_count, :>=, 1
        ensure
          File.delete(path) if path && File.exist?(path)
        end

        def test_invalid_generated_solid_aborts_batch
          result = execute(geometry: RecordingGeometryAdapter.new(invalid_on_call: 1))

          refute result.success?
          assert_equal 'tenon_generation_failed', result.failure_code
          assert_equal 0, @last_model.commit_count
          assert_equal 1, @last_model.abort_count
        end

        def test_result_counts_and_skipped_success_message_are_correct
          result = execute(skipped_count: 3)

          assert_equal 1, result.executed_connection_count
          assert_equal @connection.joint_instances.length, result.executed_joint_pair_count
          assert_equal result.executed_joint_pair_count, result.generated_mortise_count
          assert_equal result.executed_joint_pair_count, result.generated_tenon_count
          assert_equal 3, result.skipped_planning_count
          assert_includes result.user_message, 'Bỏ qua 3 vị trí không hợp lệ'
        end

        def test_manual_geometry_adapter_delegates_without_nested_operations
          geometry = FakeManualGeometry.new
          adapter = Execution::ManualGeometryExecutionAdapter.new(geometry: geometry)
          placement = Struct.new(:to_sketchup_transformation).new(:transform)
          target = FakeEntity.new('target', definition_id: 'target-definition')
          params = { tenon_width: 10.0, tenon_height: 8.0 }

          adapter.generate_tenon(
            target: target,
            params: params,
            placement: placement,
            parent_entities: target.parent
          )
          adapter.generate_mortise(
            target: target,
            params: params,
            placement: placement,
            parent_entities: target.parent
          )

          tenon_keywords = geometry.tenon_call.last
          mortise_keywords = geometry.mortise_call.last
          assert_equal false, tenon_keywords[:manage_operation]
          assert_equal false, mortise_keywords[:manage_operation]
          assert_equal false, tenon_keywords[:create_backup]
          assert_equal false, mortise_keywords[:create_backup]
          assert_equal false, tenon_keywords[:ensure_unique]
          assert_equal false, tenon_keywords[:apply_template_material]
          assert_equal true, tenon_keywords[:normalize_target_scale]
          assert_equal true, tenon_keywords[:preserve_target_properties]
          assert_equal true, mortise_keywords[:preserve_target_properties]
          assert_equal true, mortise_keywords[:normalize_target_scale]
        end

        def test_manual_geometry_adapter_reports_the_failing_boolean_stage_safely
          geometry = FakeManualGeometry.new
          geometry.fail_tenon = true
          adapter = Execution::ManualGeometryExecutionAdapter.new(geometry: geometry)
          placement = Struct.new(:to_sketchup_transformation).new(:transform)
          target = FakeEntity.new('target', definition_id: 'target-definition')

          error = assert_raises(Execution::JointExecutionFailure) do
            adapter.generate_tenon(
              target: target,
              params: { tenon_width: 10.0, tenon_height: 8.0 },
              placement: placement,
              parent_entities: target.parent
            )
          end

          assert_equal 'tenon_geometry_failed', error.code
          assert_includes error.message, 'mộng dương'
          refute_includes error.message, 'Lỗi boolean nội bộ'
          assert_equal 'Lỗi boolean nội bộ', error.details[:error_message]
        end

        def test_manual_public_geometry_entry_points_keep_managed_operation_default
          assert Geometry.respond_to?(:cut_mortise_into_solid)
          assert Geometry.respond_to?(:union_tenons_into_solid)
          source = File.read(File.expand_path('../geometry.rb', __dir__), encoding: 'UTF-8')
          assert_match(/def cut_mortise_into_solid.*?manage_operation: true/m, source)
          assert_match(/def union_tenons_into_solid.*?manage_operation: true/m, source)

          model = FakeModel.new
          value = Geometry.execute_model_operation(model, 'Thử thao tác thủ công', true) { :ok }
          assert_equal :ok, value
          assert_equal 1, model.started_operations.length
          assert_equal 1, model.commit_count
          assert_equal 0, model.abort_count

          failed_model = FakeModel.new
          assert_raises(RuntimeError) do
            Geometry.execute_model_operation(failed_model, 'Thử lỗi thủ công', true) do
              raise 'Lỗi thử nghiệm.'
            end
          end
          assert_equal 0, failed_model.commit_count
          assert_equal 1, failed_model.abort_count
        end

        def test_geometry_parameter_adapter_uses_finalized_resolved_dimensions
          adapter = Execution::GeometryParameterAdapter.new(unit_converter: TestUnits)
          joint = @connection.joint_instances.first

          tenon = adapter.tenon_parameters(@connection, joint, @settings)
          mortise = adapter.mortise_parameters(@connection, joint, @settings)

          assert_equal joint.joint_length, tenon[:tenon_width]
          assert_equal joint.mortise_opening_thickness, tenon[:tenon_height]
          assert_equal 8.0, tenon[:tenon_projection]
          assert_equal 2.0, tenon[:tenon_cutter_radius]
          assert_equal 0.2, tenon[:clearance]
          assert_in_delta joint.tenon_thickness,
                          Geometry.effective_tenon_height(tenon), 0.0001
          assert_in_delta joint.tenon_length,
                          Geometry.effective_tenon_width(tenon), 0.0001
          assert_equal joint.joint_length, mortise[:mortise_width]
          assert_equal joint.mortise_opening_thickness, mortise[:mortise_height]
          assert_equal 5.0, mortise[:mortise_depth]
          assert_equal Geometry::DOGBONE_STYLE_VERTICAL_TBONE, mortise[:dogbone_style]
          assert_equal true, tenon[:tenon_relief_enabled]
          refute tenon.key?(:dogbone_style)
        end

        def test_geometry_parameter_adapter_ignores_legacy_style_values
          adapter = Execution::GeometryParameterAdapter.new(unit_converter: TestUnits)
          legacy_values = @settings.to_h.merge(
            dogbone_style: Geometry::DOGBONE_STYLE_HORIZONTAL_TBONE,
            mortise_style: 'standard',
            tenon_style: 'obsolete',
            tenon_relief_enabled: false,
            joint_thickness_mm: 1.0,
            tenon_thickness: 2.0,
            mortise_width: 3.0
          )
          legacy_settings = Struct.new(:values) do
            def to_h
              values
            end
          end.new(legacy_values)
          joint = @connection.joint_instances.first

          tenon = adapter.tenon_parameters(@connection, joint, legacy_settings)
          mortise = adapter.mortise_parameters(@connection, joint, legacy_settings)

          assert_equal Geometry::DOGBONE_STYLE_VERTICAL_TBONE, mortise[:dogbone_style]
          assert_equal true, tenon[:tenon_relief_enabled]
          assert_in_delta joint.tenon_thickness,
                          Geometry.effective_tenon_height(tenon), 0.0001
          assert_in_delta joint.mortise_opening_thickness, mortise[:mortise_height], 0.0001
          refute tenon.key?(:mortise_style)
          refute mortise.key?(:tenon_style)
        end

        def test_geometry_adapter_consumes_finalized_joint_snapshot_without_remeasuring_settings
          adapter = Execution::GeometryParameterAdapter.new(unit_converter: TestUnits)
          forbidden_settings = Object.new
          def forbidden_settings.to_h
            raise 'Không được đọc lại kích thước UI khi đã chốt plan.'
          end
          joint = @connection.joint_instances.first

          tenon = adapter.tenon_parameters(@connection, joint, forbidden_settings)
          mortise = adapter.mortise_parameters(@connection, joint, forbidden_settings)

          assert_in_delta joint.tenon_thickness,
                          Geometry.effective_tenon_height(tenon), 0.0001
          assert_in_delta joint.mortise_opening_thickness, mortise[:mortise_height], 0.0001
          assert_in_delta joint.tenon_height, tenon[:tenon_projection], 0.0001
          assert_in_delta joint.mortise_depth, mortise[:mortise_depth], 0.0001
        end

        def test_automatic_boolean_property_copy_preserves_existing_metadata
          source_definition = FakePropertyEntity.new(
            name: 'Định nghĩa',
            material: nil,
            layer: nil,
            dictionaries: [FakeAttributeDictionary.new('SonVu CNC Plugins', 'part_role' => 'side')]
          )
          source = FakePropertyEntity.new(
            name: 'Hông trái',
            material: :wood,
            layer: :panel_tag,
            dictionaries: [FakeAttributeDictionary.new('Khách hàng', 'ma' => 'A-01')],
            definition: source_definition
          )
          result_definition = FakePropertyEntity.new(
            name: '', material: nil, layer: nil
          )
          result = FakePropertyEntity.new(
            name: '', material: nil, layer: nil, definition: result_definition
          )

          properties = Geometry.capture_target_properties(source)
          Geometry.apply_target_properties(result, properties, fallback_name: 'Kết quả')

          assert_equal 'Hông trái', result.name
          assert_equal :wood, result.material
          assert_equal :panel_tag, result.layer
          assert_equal 'A-01', result.written_attributes[['Khách hàng', 'ma']]
          assert_equal 'side',
                       result_definition.written_attributes[['SonVu CNC Plugins', 'part_role']]
        end

        def test_preview_state_is_cleared_and_dialog_closes_after_success
          state = calculated_state
          model = FakeModel.new
          dialog = FakeDialog.new
          result = Execution::JointExecutionResult.success(
            connection_count: 1,
            joint_pair_count: @connection.joint_instances.length,
            skipped_count: 0
          )
          executor = ResultExecutor.new(result)
          session = Planning::PreviewSession.new(
            model: model,
            resolution: empty_resolution,
            state: state,
            executor: executor
          )
          session.instance_variable_set(:@dialog, dialog)

          returned = session.handle_ready_for_generation

          assert returned.success?
          refute state.preview_calculated
          assert_empty state.plan.connections
          assert dialog.closed
          assert_equal 1, executor.calls.length
          assert dialog.scripts.any? { |script| script.include?('setGenerating(true)') }
          assert_includes CNCPlugins::UIHelpers.last_test_message, 'Đã tạo'
        end

        def test_failure_marks_preview_stale_and_restores_dialog_controls
          state = calculated_state
          model = FakeModel.new
          dialog = FakeDialog.new
          failure = Execution::JointExecutionResult.failure(
            code: 'test_failure',
            user_message: 'Không thể hoàn tất việc tạo mộng.',
            details: {
              diagnostic_id: 'SVJ-TEST-001',
              diagnostic_detail: 'SketchUp subtract trả về nil.',
              diagnostic_log_path: 'C:\\SonVu\\automatic_joint_diagnostics.log'
            }
          )
          session = Planning::PreviewSession.new(
            model: model,
            resolution: empty_resolution,
            state: state,
            executor: ResultExecutor.new(failure)
          )
          session.instance_variable_set(:@dialog, dialog)

          returned = session.handle_ready_for_generation

          refute returned.success?
          assert state.stale
          refute dialog.closed
          assert dialog.scripts.any? { |script| script.include?('setGenerating(false)') }
          assert dialog.scripts.any? { |script| script.include?('showError') }
          assert dialog.scripts.any? { |script| script.include?('SVJ-TEST-001') }
          assert dialog.scripts.any? { |script| script.include?('subtract trả về nil') }
        end

        def test_unexpected_preview_execution_failure_is_logged_with_backtrace_and_shown
          state = calculated_state
          model = FakeModel.new
          dialog = FakeDialog.new
          logger = RecordingDiagnosticLogger.new
          executor = Class.new do
            def execute(**_arguments)
              raise 'Lỗi ngoài executor cần chẩn đoán.'
            end
          end.new
          session = Planning::PreviewSession.new(
            model: model,
            resolution: empty_resolution,
            state: state,
            executor: executor,
            diagnostic_logger: logger
          )
          session.instance_variable_set(:@dialog, dialog)

          returned = session.handle_ready_for_generation

          assert_nil returned
          assert state.stale
          assert_equal 1, logger.errors.length
          assert_equal 'Lỗi ngoài executor cần chẩn đoán.', logger.errors.first.message
          refute_empty logger.errors.first.backtrace
          assert dialog.scripts.any? { |script| script.include?('setGenerating(false)') }
          assert dialog.scripts.any? { |script| script.include?('unexpected_execution_failure') }
          assert dialog.scripts.any? { |script| script.include?('SVJ-TEST-001') }
          assert dialog.scripts.any? { |script| script.include?('Lỗi ngoài executor cần chẩn đoán') }
        end

        def test_automatic_execution_production_code_is_ruby_27_compatible
          root = File.expand_path('../automatic_execution', __dir__)
          files = Dir.glob(File.join(root, '*.rb'))

          files.each do |path|
            source = File.read(path, encoding: 'UTF-8')
            refute_nil Ripper.sexp(source), "Không phân tích được cú pháp: #{path}"
            refute_match(
              /^\s*def\s+[a-zA-Z_]\w*[!?=]?\s*(?:\([^)]*\))?\s*=\s*[^\n]+$/,
              source,
              "Không dùng endless method của Ruby 3: #{path}"
            )
          end
        end

        class FakeManualGeometry
          attr_reader :tenon_call, :mortise_call
          attr_accessor :fail_tenon, :fail_mortise

          def effective_tenon_width(_params)
            9.8
          end

          def effective_tenon_height(_params)
            7.8
          end

          def tenon_vertical_inset(_params)
            0.1
          end

          def union_tenons_into_solid(*arguments, **keywords)
            raise 'Lỗi boolean nội bộ' if fail_tenon

            @tenon_call = [arguments, keywords]
            arguments.first
          end

          def cut_mortise_into_solid(*arguments, **keywords)
            raise 'Lỗi boolean nội bộ' if fail_mortise

            @mortise_call = [arguments, keywords]
            arguments.first
          end
        end

        private

        def execute(plan: Planning::PreviewPlan.new(connections: [@connection]),
                    settings: @settings, current_settings: settings,
                    entities: nil, resolution: nil, geometry: nil,
                    stale: false, finalized: true, skipped_count: 0)
          @last_model = FakeModel.new
          @last_geometry = geometry || RecordingGeometryAdapter.new
          entities ||= entities_for_plan(plan)
          resolution ||= resolution_for(entities)
          request = Execution::AutomaticJointExecutionRequest.new(
            model: @last_model,
            plan: plan,
            settings: settings,
            resolution: resolution,
            skipped_planning_count: skipped_count,
            stale: stale,
            finalized: finalized
          )
          executor = Execution::AutomaticJointGeometryExecutor.new(
            geometry_adapter: @last_geometry,
            parameter_adapter: RecordingParameterAdapter.new,
            transform_adapter: Execution::JointTransformAdapter.new,
            diagnostic_logger: (@last_diagnostic_logger = RecordingDiagnosticLogger.new),
            active_model_provider: lambda { @last_model }
          )
          executor.execute(
            model: @last_model,
            request: request,
            current_settings: current_settings
          )
        end

        def build_settings(length: 10.0)
          values = {
            joint_length_mm: length,
            mortise_depth_mm: 5.0,
            tenon_height_mm: 8.0,
            cutter_radius_mm: 2.0,
            clearance_mm: 0.2,
            requested_count: 2,
            start_offset_mm: 5.0,
            end_offset_mm: 5.0,
            minimum_gap_mm: 2.0,
            geometric_tolerance_mm: 0.01
          }
          specification = Planning::JointLayoutSpecification.new(
            joint_length: length,
            fit_clearance: 0.2,
            tenon_height: 8.0,
            mortise_depth: 5.0,
            cutter_radius: 2.0,
            requested_count: 2,
            start_offset: 5.0,
            end_offset: 5.0,
            minimum_gap: 2.0,
            geometric_tolerance: 0.01
          )
          Planning::PreviewSettings.new(
            values_mm: values,
            specification: specification,
            cutter_radius: 2.0
          )
        end

        def calculated_state
          raw = Planning::PreviewPlan.new(connections: [@connection])
          analyzer = Struct.new(:plan) do
            def analyze(_boards, _settings)
              Planning::BulkPreviewAnalysis.new(
                plan: plan,
                skipped_connections: [],
                raw_connection_count: plan.connections.length
              )
            end
          end.new(raw)
          state = Planning::PreviewState.new(
            board_descriptors: t_joint_boards,
            settings: @settings,
            bulk_analyzer: analyzer
          )
          state.calculate_preview
        end

        def entities_for(connection)
          [connection.male_part_identity, connection.female_part_identity].each_with_object({}) do |part, result|
            result[part.stable_id] = FakeEntity.new(
              part.persistent_id,
              definition_id: part.definition_id
            )
          end
        end

        def entities_for_plan(plan)
          identities = plan.connections.flat_map do |connection|
            [connection.male_part_identity, connection.female_part_identity]
          end.compact
          identities.each_with_object({}) do |part, result|
            result[part.stable_id] ||= FakeEntity.new(
              part.persistent_id,
              definition_id: part.definition_id
            )
          end
        end

        def resolution_for(entities)
          snapshots = {}
          paths = {}
          entities.each do |part_id, entity|
            paths[part_id] = [entity]
            snapshots[part_id] = [Planning::Transform3.from_sketchup(entity.transformation).values]
          end
          Planning::PreviewSelectionResolution.new(
            board_descriptors: t_joint_boards,
            ignored_entity_count: 0,
            warnings: [],
            entity_by_part_id: entities,
            entity_paths_by_part_id: paths,
            transform_snapshots_by_part_id: snapshots,
            active_path_entities: [],
            active_path_snapshot: []
          )
        end

        def empty_resolution
          Planning::PreviewSelectionResolution.new(
            board_descriptors: t_joint_boards,
            ignored_entity_count: 0,
            warnings: [],
            entity_by_part_id: {},
            entity_paths_by_part_id: {},
            transform_snapshots_by_part_id: {},
            active_path_entities: [],
            active_path_snapshot: []
          )
        end

        def copy_connection(connection, changes = {})
          attributes = Planning::ConnectionPlan::ATTRIBUTES.each_with_object({}) do |name, result|
            result[name] = connection.public_send(name)
          end
          changes.each { |name, value| attributes[name] = value }
          Planning::ConnectionPlan.new(attributes)
        end

        def copy_joint(joint, stable_id:, center:)
          axis = @connection.usable_joint_axis.normalized
          half = axis * (joint.joint_length / 2.0)
          Planning::JointInstancePlan.new(
            stable_id: stable_id,
            index: joint.index,
            center_position: center,
            start_position: center - half,
            end_position: center + half,
            joint_length: joint.joint_length,
            detected_male_board_thickness: joint.detected_male_board_thickness,
            tenon_thickness: joint.tenon_thickness,
            mortise_opening_thickness: joint.mortise_opening_thickness,
            fit_clearance: joint.fit_clearance,
            tenon_height: joint.tenon_height,
            mortise_depth: joint.mortise_depth,
            cutter_radius: joint.cutter_radius,
            thickness_axis: joint.thickness_axis,
            male_placement: Planning::PlacementData.for_male(
              center,
              @connection.usable_joint_axis,
              @connection.tenon_inward_direction
            ),
            female_placement: Planning::PlacementData.for_female(
              center,
              @connection.usable_joint_axis,
              @connection.mortise_inward_direction
            ),
            enabled: true
          )
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

        def assert_point_close(expected, actual)
          assert_in_delta expected.x, actual.x, 1.0e-8
          assert_in_delta expected.y, actual.y, 1.0e-8
          assert_in_delta expected.z, actual.z, 1.0e-8
        end

        alias assert_vector_close assert_point_close
      end
    end
  end
end
