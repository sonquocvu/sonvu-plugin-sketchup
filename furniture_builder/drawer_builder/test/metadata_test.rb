# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../metadata'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class MetadataTest < Minitest::Test
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

          def test_writes_and_reads_drawer_identity
            entity = EntityStub.new
            identity = Identity.create(
              object_type: 'drawer_slide_right',
              source: 'user_assigned',
              drawer_index: 2
            )

            result = Metadata.write(entity, identity.to_h)

            assert_instance_of Identity, result
            assert_equal identity.to_h, Metadata.read(entity)
            assert_equal 'drawer_slide_right', Metadata.drawer_object_type(entity)
            assert Metadata.drawer_entity?(entity)
          end

          def test_clear_removes_only_new_drawer_identity
            old_values = protected_values
            entity = EntityStub.new(old_values.merge('drawer_specification_json' => '{"opening":{}}'))
            Metadata.write(entity, Identity.create(object_type: 'drawer_box', drawer_index: 1))

            Metadata.clear_drawer_identity(entity)

            assert_equal({}, Metadata.read(entity))
            old_values.each { |key, value| assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key) }
            assert_equal '{"opening":{}}', entity.get_attribute(Metadata::DICTIONARY, 'drawer_specification_json')
          end

          def test_write_preserves_existing_furniture_and_hardware_metadata
            entity = EntityStub.new(protected_values)
            before = protected_values

            Metadata.write(entity, Identity.create(object_type: 'drawer_slide_left', drawer_index: 4))

            before.each { |key, value| assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key) }
          end

          def test_missing_drawer_metadata_returns_empty_hash
            entity = EntityStub.new(protected_values)

            assert_equal({}, Metadata.read(entity))
            refute Metadata.drawer_entity?(entity)
            assert_nil Metadata.drawer_object_type(entity)
          end

          def test_partial_drawer_metadata_is_read_safely
            entity = EntityStub.new('drawer_object_type' => 'drawer_opening')

            assert_equal({ drawer_object_type: 'drawer_opening' }, Metadata.read(entity))
            assert Metadata.drawer_entity?(entity)
          end

          def test_partial_identity_can_reuse_legacy_index_without_overwriting_it
            entity = EntityStub.new(
              'drawer_object_type' => 'drawer_box',
              'drawer_index' => 7
            )

            assert_equal 7, Metadata.read(entity)[:drawer_index]
            assert_equal 7, entity.get_attribute(Metadata::DICTIONARY, 'drawer_index')
          end

          def test_unknown_future_metadata_version_raises_structured_error
            entity = EntityStub.new(
              'drawer_object_type' => 'drawer_box',
              'drawer_version' => Identity::CURRENT_VERSION + 1
            )

            error = assert_raises(Metadata::MetadataError) { Metadata.read(entity) }

            assert_equal :future_metadata_version, error.code
            assert_equal :drawer_version, error.field
          end

          def test_invalid_object_type_is_rejected_on_read_and_write
            entity = EntityStub.new('drawer_object_type' => 'drawer_front')

            read_error = assert_raises(Metadata::MetadataError) { Metadata.read(entity) }
            write_error = assert_raises(Identity::IdentityError) do
              Metadata.write(
                EntityStub.new,
                drawer_object_type: 'drawer_front',
                drawer_system_id: Identity.generate_system_id
              )
            end

            assert_equal :unsupported_object_type, read_error.code
            assert_equal :unsupported_object_type, write_error.code
          end

          def test_invalid_persisted_system_id_is_rejected
            entity = EntityStub.new(
              'drawer_object_type' => 'drawer_box',
              'drawer_system_id' => 'entity-123'
            )

            error = assert_raises(Metadata::MetadataError) { Metadata.read(entity) }

            assert_equal :invalid_system_id, error.code
            assert_equal :drawer_system_id, error.field
          end

          def test_utf8_metadata_values_are_unchanged
            entity = EntityStub.new(
              protected_values.merge('part_name_vi' => 'Ngăn kéo bếp bên trái')
            )

            Metadata.write(entity, Identity.create(object_type: 'drawer_system'))

            assert_equal 'Ngăn kéo bếp bên trái', entity.get_attribute(Metadata::DICTIONARY, 'part_name_vi')
          end

          def test_unsupported_entity_raises_structured_error
            error = assert_raises(Metadata::MetadataError) { Metadata.read(Object.new) }

            assert_equal :unsupported_entity, error.code
          end

          private

          def protected_values
            {
              'part_kind' => 'hardware',
              'part_role' => 'drawer_slide_left',
              'drawer_index' => 4,
              'hardware_type' => 'drawer_slide_left',
              'owner_part_key' => 'mat_ngan_keo_4'
            }
          end
        end
      end
    end
  end
end
