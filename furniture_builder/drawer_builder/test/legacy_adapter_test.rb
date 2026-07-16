# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../legacy_adapter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class LegacyAdapterTest < Minitest::Test
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

          def test_recognizes_existing_drawer_side_panel
            detection = LegacyAdapter.detect(drawer_box_entity('drawer_side_left'))

            assert detection[:recognized]
            assert_equal 'drawer_box', detection[:inferred_object_type]
            assert_equal 'high', detection[:confidence]
          end

          def test_recognizes_existing_drawer_front
            entity = EntityStub.new(
              'part_kind' => 'front',
              'part_role' => 'drawer_front',
              'drawer_index' => 2
            )

            detection = LegacyAdapter.detect(entity)

            assert detection[:recognized]
            assert_equal 'drawer_system', detection[:inferred_object_type]
            assert_equal 'medium', detection[:confidence]
          end

          def test_recognizes_existing_drawer_bottom
            detection = LegacyAdapter.detect(drawer_box_entity('drawer_bottom'))

            assert detection[:recognized]
            assert_equal 'drawer_box', detection[:inferred_object_type]
          end

          def test_recognizes_existing_left_and_right_slide_hardware
            left = LegacyAdapter.detect(slide_entity('drawer_slide_left'))
            right = LegacyAdapter.detect(slide_entity('drawer_slide_right'))

            assert left[:recognized]
            assert_equal 'drawer_slide_left', left[:inferred_object_type]
            assert right[:recognized]
            assert_equal 'drawer_slide_right', right[:inferred_object_type]
          end

          def test_hardware_type_is_used_when_legacy_role_is_not_specific
            entity = EntityStub.new(
              'part_kind' => 'hardware',
              'part_role' => 'drawer_slide',
              'hardware_type' => 'drawer_slide_right',
              'drawer_index' => 1
            )

            assert_equal 'drawer_slide_right', LegacyAdapter.detect(entity)[:inferred_object_type]
          end

          def test_read_only_detection_does_not_modify_entity
            entity = drawer_box_entity('drawer_side_right')
            before = entity.snapshot

            LegacyAdapter.detect(entity)
            LegacyAdapter.to_drawer_identity(entity)

            assert_equal before, entity.snapshot
            assert_empty entity.writes
            assert_empty entity.deletes
          end

          def test_explicit_adaptation_adds_identity_and_preserves_all_old_keys
            values = {
              'part_kind' => 'hardware',
              'part_role' => 'drawer_slide_left',
              'drawer_index' => 5,
              'hardware_type' => 'drawer_slide_left',
              'owner_part_key' => 'mat_ngan_keo_5',
              'part_name_vi' => 'Ray trái ngăn kéo'
            }
            entity = EntityStub.new(values)

            identity = LegacyAdapter.apply(entity)

            assert_equal 'legacy_adapter', identity.drawer_source
            assert_equal 'drawer_slide_left', Metadata.drawer_object_type(entity)
            values.each { |key, value| assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key) }
          end

          def test_explicit_adaptation_can_link_legacy_parts_to_one_system
            system_id = Identity.generate_system_id
            side = drawer_box_entity('drawer_side_left')
            slide = slide_entity('drawer_slide_left')

            side_identity = LegacyAdapter.apply(side, system_id: system_id)
            slide_identity = LegacyAdapter.apply(slide, system_id: system_id)

            assert_equal system_id, side_identity.drawer_system_id
            assert_equal system_id, slide_identity.drawer_system_id
          end

          def test_unsupported_legacy_entity_is_not_falsely_classified
            entity = EntityStub.new(
              'part_kind' => 'carcass',
              'part_role' => 'side_left',
              'drawer_index' => 1,
              'name' => 'Drawer box'
            )

            detection = LegacyAdapter.detect(entity)

            refute detection[:recognized]
            assert_nil detection[:inferred_object_type]
            error = assert_raises(LegacyAdapter::LegacyError) do
              LegacyAdapter.to_drawer_identity(entity)
            end
            assert_equal :unsupported_legacy_entity, error.code
          end

          def test_supported_role_without_drawer_index_is_not_adapted
            entity = EntityStub.new(
              'part_kind' => 'drawer_box',
              'part_role' => 'drawer_back'
            )

            refute LegacyAdapter.detect(entity)[:recognized]
          end

          private

          def drawer_box_entity(role)
            EntityStub.new(
              'part_kind' => 'drawer_box',
              'part_role' => role,
              'drawer_index' => 1,
              'owner_part_key' => 'mat_ngan_keo_1'
            )
          end

          def slide_entity(role)
            EntityStub.new(
              'part_kind' => 'hardware',
              'part_role' => role,
              'hardware_type' => role,
              'drawer_index' => 1,
              'owner_part_key' => 'mat_ngan_keo_1'
            )
          end
        end
      end
    end
  end
end
