# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../identity'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class IdentityTest < Minitest::Test
          def test_accepts_every_supported_object_type
            Identity::OBJECT_TYPES.each do |object_type|
              identity = Identity.create(object_type: object_type)

              assert_equal object_type, identity.drawer_object_type
              assert Identity.valid_system_id?(identity.drawer_system_id)
            end
          end

          def test_rejects_an_unsupported_object_type
            error = assert_raises(Identity::IdentityError) do
              Identity.create(object_type: 'drawer_front')
            end

            assert_equal :unsupported_object_type, error.code
            assert_equal :drawer_object_type, error.field
          end

          def test_generated_system_id_is_a_stable_uuid_value
            identity = Identity.create(object_type: 'drawer_opening')
            restored = Identity.from_h(identity.to_h)

            assert Identity.valid_system_id?(identity.drawer_system_id)
            assert_equal identity.drawer_system_id, restored.drawer_system_id
          end

          def test_multiple_roles_can_share_one_system_id
            system_id = Identity.generate_system_id
            opening = Identity.create(object_type: 'drawer_opening', system_id: system_id)
            box = Identity.create(object_type: 'drawer_box', system_id: system_id)

            assert_equal opening.drawer_system_id, box.drawer_system_id
            refute_equal opening.drawer_object_id, box.drawer_object_id
          end

          def test_different_systems_receive_different_ids
            first = Identity.create(object_type: 'drawer_system')
            second = Identity.create(object_type: 'drawer_system')

            refute_equal first.drawer_system_id, second.drawer_system_id
          end

          def test_plain_hash_serialization_and_string_key_restoration
            identity = Identity.create(
              object_type: 'drawer_slide_left',
              source: 'user_assigned',
              drawer_index: 3
            )
            plain = identity.to_h
            restored = Identity.from_h(plain.transform_keys(&:to_s))

            assert_instance_of Hash, plain
            assert_equal plain, restored.to_h
            assert_equal 'user_assigned', restored.drawer_source
            assert_equal 3, restored.drawer_index
            assert restored.frozen?
          end

          def test_rejects_invalid_system_id
            error = assert_raises(Identity::IdentityError) do
              Identity.create(object_type: 'drawer_box', system_id: 'entity-123')
            end

            assert_equal :invalid_system_id, error.code
          end

          def test_rejects_invalid_source
            error = assert_raises(Identity::IdentityError) do
              Identity.create(object_type: 'drawer_box', source: 'guessed')
            end

            assert_equal :invalid_source, error.code
          end

          def test_rejects_unknown_future_version
            error = assert_raises(Identity::IdentityError) do
              Identity.from_h(
                drawer_object_type: 'drawer_box',
                drawer_system_id: Identity.generate_system_id,
                drawer_version: Identity::CURRENT_VERSION + 1
              )
            end

            assert_equal :future_metadata_version, error.code
          end

          def test_missing_version_uses_current_version
            identity = Identity.from_h(
              drawer_object_type: 'drawer_box',
              drawer_system_id: Identity.generate_system_id
            )

            assert_equal Identity::CURRENT_VERSION, identity.drawer_version
          end
        end
      end
    end
  end
end
