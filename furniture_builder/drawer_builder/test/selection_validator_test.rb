# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../selection_validator'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SelectionValidatorTest < Minitest::Test
          class EntityStub
            attr_accessor :locked

            def initialize(type:, valid: true, locked: false)
              @type = type
              @valid = valid
              @locked = locked
              @attributes = {}
            end

            def drawer_assignment_entity_type
              @type
            end

            def valid?
              @valid
            end

            def locked?
              @locked
            end

            def get_attribute(dictionary, key, default = nil)
              @attributes.fetch([dictionary, key], default)
            end

            def set_attribute(dictionary, key, value)
              @attributes[[dictionary, key]] = value
            end

            def delete_attribute(dictionary, key)
              @attributes.delete([dictionary, key])
            end
          end

          class UnsupportedStub
            def initialize(type)
              @type = type
            end

            def drawer_assignment_entity_type
              @type
            end
          end

          def test_empty_selection
            result = SelectionValidator.validate_single_assignable_entity([])

            assert_failure result, :empty_selection
            assert_equal 0, result[:details][:count]
          end

          def test_one_valid_group
            entity = valid_group
            result = SelectionValidator.validate_single_assignable_entity([entity])

            assert_success result
            assert_same entity, result[:entity]
            assert_equal :instance, result[:details][:identity_scope]
          end

          def test_one_valid_component_instance
            entity = EntityStub.new(type: :component_instance)
            result = SelectionValidator.validate_single_assignable_entity([entity])

            assert_success result
            assert_same entity, result[:entity]
          end

          def test_multiple_selected_entities
            result = SelectionValidator.validate_single_assignable_entity([valid_group, valid_group])

            assert_failure result, :multiple_selection
            assert_equal 2, result[:details][:count]
          end

          def test_selected_face_is_rejected
            result = SelectionValidator.validate_single_assignable_entity([UnsupportedStub.new(:face)])

            assert_failure result, :unsupported_entity
          end

          def test_selected_edge_is_rejected
            result = SelectionValidator.validate_single_assignable_entity([UnsupportedStub.new(:edge)])

            assert_failure result, :unsupported_entity
          end

          def test_deleted_entity_is_rejected
            entity = EntityStub.new(type: :group, valid: false)

            assert_failure SelectionValidator.validate_single_assignable_entity([entity]), :deleted_entity
          end

          def test_locked_entity_is_rejected
            entity = EntityStub.new(type: :group, locked: true)

            assert_failure SelectionValidator.validate_single_assignable_entity([entity]), :locked_entity
          end

          def test_invalid_role_is_rejected
            result = SelectionValidator.validate_role_assignment(valid_group, :drawer_front)

            assert_failure result, :invalid_role
          end

          def test_invalid_system_id_is_rejected
            result = SelectionValidator.validate_role_assignment(
              valid_group,
              :drawer_opening,
              drawer_system_id: 'entity-42'
            )

            assert_failure result, :invalid_system_id
          end

          def test_shared_component_definition_is_rejected_explicitly
            result = SelectionValidator.validate_single_assignable_entity(
              [UnsupportedStub.new(:component_definition)]
            )

            assert_failure result, :shared_component_definition_risk
          end

          def test_existing_assignment_states_are_detected
            entity = valid_group
            system_id = Identity.generate_system_id
            Metadata.write(
              entity,
              Identity.create(object_type: 'drawer_box', system_id: system_id)
            )

            same = SelectionValidator.validate_role_assignment(
              entity,
              :drawer_box,
              drawer_system_id: system_id
            )
            different_role = SelectionValidator.validate_role_assignment(
              entity,
              :drawer_opening,
              drawer_system_id: system_id
            )
            different_system = SelectionValidator.validate_system_membership(
              entity,
              Identity.generate_system_id
            )

            assert_success same
            assert_equal :same_role_same_system, same[:details][:assignment_state]
            assert_failure different_role, :entity_assigned_to_different_role
            assert_failure different_system, :entity_assigned_to_different_system
          end

          def test_result_shape_is_consistent
            success = SelectionValidator.validate_single_assignable_entity([valid_group])
            failure = SelectionValidator.validate_single_assignable_entity([])

            assert_equal success.keys, failure.keys
            assert_equal %i[success entity role drawer_system_id error_code details], success.keys
          end

          private

          def valid_group
            EntityStub.new(type: :group)
          end

          def assert_success(result)
            assert_equal true, result[:success], result.inspect
            assert_nil result[:error_code]
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
