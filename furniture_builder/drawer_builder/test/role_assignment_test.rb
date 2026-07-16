# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../role_assignment'
require_relative '../legacy_adapter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class RoleAssignmentTest < Minitest::Test
          class ModelStub
            attr_reader :active_entities, :operations, :commits, :aborts

            def initialize
              @active_entities = []
              @operations = []
              @commits = 0
              @aborts = 0
            end

            def start_operation(name, transparent)
              @operations << [name, transparent]
            end

            def commit_operation
              @commits += 1
            end

            def abort_operation
              @aborts += 1
            end
          end

          class EntityStub
            attr_reader :model, :writes, :deletes

            def initialize(model:, type: :group, values: {})
              @model = model
              @type = type
              @attributes = {}
              @writes = []
              @deletes = []
              values.each { |key, value| @attributes[[Metadata::DICTIONARY, key.to_s]] = value }
              model.active_entities << self if model
            end

            def drawer_assignment_entity_type
              @type
            end

            def valid?
              true
            end

            def locked?
              false
            end

            def get_attribute(dictionary, key, default = nil)
              @attributes.fetch([dictionary, key], default)
            end

            def set_attribute(dictionary, key, value)
              @writes << [dictionary, key, value]
              @attributes[[dictionary, key]] = value
            end

            def delete_attribute(dictionary, key)
              @deletes << [dictionary, key]
              @attributes.delete([dictionary, key])
            end

            def snapshot
              Marshal.load(Marshal.dump(@attributes))
            end
          end

          class UnsupportedStub
            def drawer_assignment_entity_type
              :face
            end
          end

          def setup
            @model = ModelStub.new
          end

          def test_assigns_opening_to_new_generated_system
            entity = new_entity

            result = RoleAssignment.assign(entity: entity, role: :drawer_opening)
            values = Metadata.read(entity)

            assert_success result, :assigned
            assert Identity.valid_system_id?(result[:drawer_system_id])
            assert_equal result[:drawer_system_id], values[:drawer_system_id]
            assert_equal 'drawer_opening', values[:drawer_object_type]
            assert_equal 'user_assigned', values[:drawer_source]
            assert RoleAssignment.assigned?(entity)
            assert_equal :drawer_opening, RoleAssignment.assigned_role(entity)
            assert_operation RoleAssignment::OPERATION_ASSIGN
          end

          def test_assigns_left_and_right_slides_to_existing_system
            system_id = Identity.generate_system_id
            left = new_entity
            right = new_entity(type: :component_instance)

            left_result = RoleAssignment.assign(
              entity: left,
              role: :drawer_slide_left,
              drawer_system_id: system_id
            )
            right_result = RoleAssignment.assign(
              entity: right,
              role: :drawer_slide_right,
              drawer_system_id: system_id
            )

            assert_success left_result, :assigned
            assert_success right_result, :assigned
            assert_equal system_id, Metadata.read(left)[:drawer_system_id]
            assert_equal system_id, Metadata.read(right)[:drawer_system_id]
          end

          def test_assigns_drawer_box_and_system_wrapper_roles
            system_id = Identity.generate_system_id
            box = new_entity
            wrapper = new_entity

            box_result = RoleAssignment.assign(
              entity: box,
              role: :drawer_box,
              drawer_system_id: system_id
            )
            wrapper_result = RoleAssignment.assign(
              entity: wrapper,
              role: :drawer_system,
              drawer_system_id: system_id
            )

            assert_success box_result, :assigned
            assert_success wrapper_result, :assigned
          end

          def test_same_entity_same_role_and_system_is_idempotent
            entity = new_entity
            first = RoleAssignment.assign(entity: entity, role: :drawer_opening)
            writes = entity.writes.length
            deletes = entity.deletes.length
            operation_count = @model.operations.length

            second = RoleAssignment.assign(
              entity: entity,
              role: :drawer_opening,
              drawer_system_id: first[:drawer_system_id]
            )

            assert_success second, :unchanged
            assert_equal writes, entity.writes.length
            assert_equal deletes, entity.deletes.length
            assert_equal operation_count, @model.operations.length
          end

          def test_same_role_conflict_in_one_system
            system_id = Identity.generate_system_id
            first = new_entity
            second = new_entity
            assert RoleAssignment.assign(
              entity: first,
              role: :drawer_opening,
              drawer_system_id: system_id
            )[:success]

            result = RoleAssignment.assign(
              entity: second,
              role: :drawer_opening,
              drawer_system_id: system_id
            )

            assert_failure result, :role_already_assigned
            refute RoleAssignment.assigned?(second)
          end

          def test_different_role_on_same_entity_requires_explicit_reassignment
            entity = new_entity
            assigned = RoleAssignment.assign(entity: entity, role: :drawer_opening)

            result = RoleAssignment.assign(
              entity: entity,
              role: :drawer_box,
              drawer_system_id: assigned[:drawer_system_id]
            )

            assert_failure result, :entity_assigned_to_different_role
            assert_equal :drawer_opening, RoleAssignment.assigned_role(entity)
          end

          def test_reassigns_role_explicitly_in_same_system
            entity = new_entity
            assigned = RoleAssignment.assign(entity: entity, role: :drawer_opening)

            result = RoleAssignment.reassign(
              entity: entity,
              role: :drawer_box,
              drawer_system_id: assigned[:drawer_system_id]
            )

            assert_success result, :reassigned
            assert_equal :drawer_box, RoleAssignment.assigned_role(entity)
            assert_equal assigned[:drawer_system_id], Metadata.read(entity)[:drawer_system_id]
          end

          def test_moves_entity_to_another_system_explicitly
            entity = new_entity
            original = RoleAssignment.assign(entity: entity, role: :drawer_box)
            target_system_id = Identity.generate_system_id

            conservative = RoleAssignment.assign(
              entity: entity,
              role: :drawer_box,
              drawer_system_id: target_system_id
            )
            moved = RoleAssignment.move(entity: entity, drawer_system_id: target_system_id)

            assert_failure conservative, :entity_assigned_to_different_system
            assert_success moved, :moved
            refute_equal original[:drawer_system_id], moved[:drawer_system_id]
            assert_equal target_system_id, Metadata.read(entity)[:drawer_system_id]
          end

          def test_move_rejects_an_unassigned_entity
            result = RoleAssignment.move(
              entity: new_entity,
              drawer_system_id: Identity.generate_system_id
            )

            assert_failure result, :entity_not_assigned
          end

          def test_move_and_reassign_requires_explicit_combined_method
            entity = new_entity
            original = RoleAssignment.assign(entity: entity, role: :drawer_opening)
            target_system_id = Identity.generate_system_id

            conservative = RoleAssignment.assign(
              entity: entity,
              role: :drawer_box,
              drawer_system_id: target_system_id
            )
            changed = RoleAssignment.move_and_reassign(
              entity: entity,
              role: :drawer_box,
              drawer_system_id: target_system_id
            )

            assert_failure conservative, :entity_assignment_conflict
            assert_success changed, :moved_and_reassigned
            refute_equal original[:drawer_system_id], changed[:drawer_system_id]
            assert_equal :drawer_box, RoleAssignment.assigned_role(entity)
          end

          def test_unassign_removes_only_standalone_identity
            legacy = protected_values
            entity = new_entity(values: legacy)
            RoleAssignment.assign(entity: entity, role: :drawer_box)
            Persistence.write(entity, opening: opening_values)

            result = RoleAssignment.unassign(entity: entity)

            assert_success result, :unassigned
            refute RoleAssignment.assigned?(entity)
            legacy.each do |key, value|
              assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key)
            end
            refute_nil Persistence.read(entity)
            assert_equal RoleAssignment::OPERATION_UNASSIGN, @model.operations.last.first
          end

          def test_assignment_preserves_legacy_metadata_and_legacy_detection
            legacy = protected_values
            entity = new_entity(values: legacy)
            before_detection = LegacyAdapter.detect(entity)

            result = RoleAssignment.assign(entity: entity, role: :drawer_box)
            after_detection = LegacyAdapter.detect(entity)

            assert_success result, :assigned
            assert before_detection[:recognized]
            assert after_detection[:recognized]
            legacy.each do |key, value|
              assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key)
            end
          end

          def test_partial_specification_is_validated_and_persisted_atomically
            entity = new_entity

            result = RoleAssignment.assign(
              entity: entity,
              role: :drawer_opening,
              specification: { opening: opening_values }
            )
            restored = Persistence.read(entity)

            assert_success result, :assigned
            assert_equal 600.0, restored.opening[:opening_width]
            assert_nil restored.slides
            assert_nil restored.box
            assert_equal 1, @model.commits
          end

          def test_invalid_specification_is_rejected_before_any_write
            entity = new_entity
            before = entity.snapshot

            result = RoleAssignment.assign(
              entity: entity,
              role: :drawer_opening,
              specification: { opening: opening_values.merge(opening_width: 0) }
            )

            assert_failure result, :invalid_specification
            assert_equal before, entity.snapshot
            assert_empty @model.operations
          end

          def test_unsupported_entity_is_rejected
            result = RoleAssignment.assign(entity: UnsupportedStub.new, role: :drawer_box)

            assert_failure result, :unsupported_entity
          end

          def test_caller_owned_operation_avoids_nested_model_operation
            entity = new_entity

            result = RoleAssignment.assign(
              entity: entity,
              role: :drawer_box,
              manage_operation: false
            )

            assert_success result, :assigned
            assert_empty @model.operations
            assert_equal 0, @model.commits
          end

          private

          def new_entity(type: :group, values: {})
            EntityStub.new(model: @model, type: type, values: values)
          end

          def protected_values
            {
              'part_kind' => 'drawer_box',
              'part_role' => 'drawer_bottom',
              'drawer_index' => 2,
              'hardware_type' => 'drawer_slide_left',
              'owner_part_key' => 'mat_ngan_keo_2',
              'cnc_operation' => 'pocket'
            }
          end

          def opening_values
            {
              opening_width: 600,
              opening_height: 180,
              opening_depth: 500,
              front_direction: [1, 0, 0],
              depth_direction: [0, 1, 0],
              local_transformation: [],
              source_entity_id: 12_345
            }
          end

          def assert_operation(name)
            assert_equal [[name, true]], @model.operations
            assert_equal 1, @model.commits
            assert_equal 0, @model.aborts
          end

          def assert_success(result, status)
            assert_equal true, result[:success], result.inspect
            assert_nil result[:error_code]
            assert_equal status, result[:details][:status]
          end

          def assert_failure(result, code)
            assert_equal false, result[:success], result.inspect
            assert_equal code, result[:error_code]
          end
        end
      end
    end
  end
end
