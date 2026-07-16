# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../system_registry'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SystemRegistryTest < Minitest::Test
          class EntityStub
            attr_reader :entities, :writes, :deletes

            def initialize(children = [])
              @entities = children
              @attributes = {}
              @writes = []
              @deletes = []
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

          def test_finds_entities_by_system_id_and_keeps_systems_isolated
            first_id = Identity.generate_system_id
            second_id = Identity.generate_system_id
            opening = assigned_entity('drawer_opening', first_id)
            box = assigned_entity('drawer_box', first_id)
            other = assigned_entity('drawer_opening', second_id)

            result = SystemRegistry.entities_for_system([opening, box, other], first_id)

            assert_equal [opening, box], result
            refute_includes result, other
          end

          def test_finds_entity_by_role_and_returns_nil_for_missing_role
            system_id = Identity.generate_system_id
            opening = assigned_entity('drawer_opening', system_id)

            assert_same opening, SystemRegistry.entity_for_role([opening], system_id, :drawer_opening)
            assert_nil SystemRegistry.entity_for_role([opening], system_id, :drawer_box)
          end

          def test_opening_only_state
            assert_state :opening_only, %w[drawer_opening]
          end

          def test_slides_only_state
            assert_state :slides_only, %w[drawer_slide_left drawer_slide_right]
          end

          def test_opening_and_slides_state
            assert_state :opening_and_slides,
                         %w[drawer_opening drawer_slide_left drawer_slide_right]
          end

          def test_opening_and_box_state
            assert_state :opening_and_box, %w[drawer_opening drawer_box]
          end

          def test_box_only_state
            assert_state :box_only, %w[drawer_box]
          end

          def test_complete_state_does_not_require_optional_system_wrapper
            system_id, entities = entities_for_roles(
              %w[drawer_opening drawer_slide_left drawer_slide_right drawer_box]
            )

            assert_equal :complete, SystemRegistry.system_state(entities, system_id)
            assert SystemRegistry.system_complete?(entities, system_id)
          end

          def test_roles_for_system_returns_stable_role_symbols
            system_id, entities = entities_for_roles(
              %w[drawer_box drawer_slide_right drawer_opening]
            )

            assert_equal(
              %i[drawer_opening drawer_slide_right drawer_box],
              SystemRegistry.roles_for_system(entities, system_id)
            )
          end

          def test_nested_entity_search_is_limited_to_supplied_scope
            system_id = Identity.generate_system_id
            nested = assigned_entity('drawer_box', system_id)
            container = EntityStub.new([nested])
            outside = assigned_entity('drawer_opening', system_id)

            recursive = SystemRegistry.entities_for_system([container], system_id)
            flat = SystemRegistry.entities_for_system([container], system_id, recursive: false)

            assert_equal [nested], recursive
            assert_empty flat
            refute_includes recursive, outside
          end

          def test_registry_reads_do_not_modify_attributes
            system_id = Identity.generate_system_id
            entity = assigned_entity('drawer_opening', system_id)
            before = entity.snapshot
            writes_before = entity.writes.length
            deletes_before = entity.deletes.length

            SystemRegistry.entities_for_system([entity], system_id)
            SystemRegistry.entity_for_role([entity], system_id, :drawer_opening)
            SystemRegistry.roles_for_system([entity], system_id)
            SystemRegistry.system_state([entity], system_id)

            assert_equal before, entity.snapshot
            assert_equal writes_before, entity.writes.length
            assert_equal deletes_before, entity.deletes.length
          end

          private

          def assigned_entity(role, system_id)
            entity = EntityStub.new
            Metadata.write(entity, Identity.create(object_type: role, system_id: system_id))
            entity
          end

          def entities_for_roles(roles)
            system_id = Identity.generate_system_id
            [system_id, roles.map { |role| assigned_entity(role, system_id) }]
          end

          def assert_state(expected, roles)
            system_id, entities = entities_for_roles(roles)

            assert_equal expected, SystemRegistry.system_state(entities, system_id)
            refute SystemRegistry.system_complete?(entities, system_id) unless expected == :complete
          end
        end
      end
    end
  end
end
