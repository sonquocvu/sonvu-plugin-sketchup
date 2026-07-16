# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../specification_owner'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class SpecificationOwnerTest < Minitest::Test
          class EntityStub
            attr_reader :writes, :deletes

            def initialize(values = {})
              @attributes = {}
              @writes = []
              @deletes = []
              values.each { |key, value| @attributes[[Metadata::DICTIONARY, key.to_s]] = value }
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

          def test_prefers_drawer_system_wrapper
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            wrapper = assigned('drawer_system', system_id)

            assert_same wrapper, SpecificationOwner.find(
              scope: [opening, wrapper],
              drawer_system_id: system_id
            )
          end

          def test_falls_back_to_opening
            system_id = Identity.generate_system_id
            box = assigned('drawer_box', system_id)
            opening = assigned('drawer_opening', system_id)

            assert_same opening, SpecificationOwner.find(
              scope: [box, opening],
              drawer_system_id: system_id
            )
          end

          def test_fallback_priority_is_box_then_left_then_right_slide
            system_id = Identity.generate_system_id
            right = assigned('drawer_slide_right', system_id)
            left = assigned('drawer_slide_left', system_id)
            box = assigned('drawer_box', system_id)

            assert_same box, SpecificationOwner.find(
              scope: [right, left, box],
              drawer_system_id: system_id
            )
            assert_same left, SpecificationOwner.find(
              scope: [right, left],
              drawer_system_id: system_id
            )
            assert_same right, SpecificationOwner.find(
              scope: [right],
              drawer_system_id: system_id
            )
          end

          def test_owner_is_stable_regardless_of_scope_order
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            box = assigned('drawer_box', system_id)

            first = SpecificationOwner.find(scope: [opening, box], drawer_system_id: system_id)
            second = SpecificationOwner.find(scope: [box, opening], drawer_system_id: system_id)

            assert_same opening, first
            assert_same opening, second
          end

          def test_missing_system_returns_nil_and_write_raises
            system_id = Identity.generate_system_id

            assert_nil SpecificationOwner.find(scope: [], drawer_system_id: system_id)
            error = assert_raises(SpecificationOwner::OwnerError) do
              SpecificationOwner.write(
                scope: [],
                drawer_system_id: system_id,
                specification: opening_specification(system_id)
              )
            end
            assert_equal :missing_system, error.code
          end

          def test_deleted_entity_is_ignored
            system_id = Identity.generate_system_id
            entity = assigned('drawer_opening', system_id)
            entity.define_singleton_method(:valid?) { false }

            assert_nil SpecificationOwner.find(scope: [entity], drawer_system_id: system_id)
          end

          def test_duplicate_role_is_a_structured_conflict
            system_id = Identity.generate_system_id
            first = assigned('drawer_opening', system_id)
            second = assigned('drawer_opening', system_id)

            error = assert_raises(SpecificationOwner::OwnerError) do
              SpecificationOwner.find(scope: [first, second], drawer_system_id: system_id)
            end

            assert_equal :duplicate_role, error.code
            assert_equal 'drawer_opening', error.role
          end

          def test_read_is_metadata_write_free
            system_id = Identity.generate_system_id
            owner = assigned('drawer_opening', system_id)
            Persistence.write(owner, opening_specification(system_id))
            before = owner.snapshot
            writes = owner.writes.length
            deletes = owner.deletes.length

            specification = SpecificationOwner.read(scope: [owner], drawer_system_id: system_id)

            assert_equal 600.0, specification.opening[:opening_width]
            assert_equal before, owner.snapshot
            assert_equal writes, owner.writes.length
            assert_equal deletes, owner.deletes.length
          end

          def test_read_falls_back_without_writing_when_higher_priority_owner_is_new
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id)
            Persistence.write(opening, opening_specification(system_id))
            wrapper = assigned('drawer_system', system_id)
            before = [opening.snapshot, wrapper.snapshot]
            writes = [opening.writes.length, wrapper.writes.length]

            specification = SpecificationOwner.read(
              scope: [wrapper, opening],
              drawer_system_id: system_id
            )

            assert_equal 600.0, specification.opening[:opening_width]
            assert_equal before, [opening.snapshot, wrapper.snapshot]
            assert_equal writes, [opening.writes.length, wrapper.writes.length]
          end

          def test_write_migrates_specification_to_current_owner_and_removes_stale_copy
            system_id = Identity.generate_system_id
            opening = assigned('drawer_opening', system_id, 'part_kind' => 'cabinet_part')
            Persistence.write(opening, opening_specification(system_id))
            wrapper = assigned('drawer_system', system_id, 'owner_note' => 'Hệ tủ bếp')

            SpecificationOwner.write(
              scope: [opening, wrapper],
              drawer_system_id: system_id,
              specification: opening_specification(system_id)
            )

            assert_equal 600.0, Persistence.read(wrapper).opening[:opening_width]
            assert_nil Persistence.read(opening)
            assert_equal 'cabinet_part', opening.get_attribute(Metadata::DICTIONARY, 'part_kind')
            assert_equal 'Hệ tủ bếp', wrapper.get_attribute(Metadata::DICTIONARY, 'owner_note')
          end

          def test_write_preserves_unrelated_metadata
            system_id = Identity.generate_system_id
            owner = assigned(
              'drawer_opening',
              system_id,
              'part_kind' => 'drawer_box',
              'part_role' => 'drawer_bottom',
              'drawer_index' => 4,
              'hardware_type' => 'drawer_slide_left'
            )

            SpecificationOwner.write(
              scope: [owner],
              drawer_system_id: system_id,
              specification: opening_specification(system_id)
            )

            assert_equal 'drawer_box', owner.get_attribute(Metadata::DICTIONARY, 'part_kind')
            assert_equal 'drawer_bottom', owner.get_attribute(Metadata::DICTIONARY, 'part_role')
            assert_equal 4, owner.get_attribute(Metadata::DICTIONARY, 'drawer_index')
            assert_equal 'drawer_slide_left', owner.get_attribute(Metadata::DICTIONARY, 'hardware_type')
          end

          private

          def assigned(role, system_id, values = {})
            entity = EntityStub.new(values)
            Metadata.write(entity, Identity.create(object_type: role, system_id: system_id))
            entity
          end

          def opening_specification(system_id)
            Specification.new(
              unit_system: 'millimeters',
              drawer_system_id: system_id,
              source: 'assigned',
              opening: {
                opening_width: 600,
                opening_height: 180,
                opening_depth: 500
              }
            )
          end
        end
      end
    end
  end
end
