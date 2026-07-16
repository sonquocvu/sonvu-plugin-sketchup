# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../command_messages'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class CommandMessagesTest < Minitest::Test
          EXPECTED_ERROR_CODES = %i[
            empty_selection multiple_selection unsupported_entity
            shared_component_definition_risk deleted_entity role_already_assigned
            entity_assigned_to_different_system move_required
            entity_assigned_to_different_role entity_assignment_conflict
            reassignment_required locked_entity invalid_system_id
            invalid_metadata_version future_metadata_version
            unsupported_object_type invalid_drawer_index invalid_source
            invalid_specification invalid_role entity_not_assigned
          ].freeze

          def test_all_command_labels_are_vietnamese
            assert_equal(
              [
                'Gán làm khoang ngăn kéo',
                'Gán làm ray trái',
                'Gán làm ray phải',
                'Gán làm thùng ngăn kéo',
                'Gán làm hệ ngăn kéo'
              ],
              CommandMessages::COMMAND_LABELS.values
            )
            assert_equal 'Bỏ gán vai trò ngăn kéo', CommandMessages::COMMAND_UNASSIGN
          end

          def test_every_expected_error_code_maps_to_vietnamese_text
            EXPECTED_ERROR_CODES.each do |code|
              message = CommandMessages.error_message(code)

              refute_empty message
              refute_includes message, code.to_s
              assert message.encoding == Encoding::UTF_8
            end
          end

          def test_required_error_messages_match_command_contract
            assert_equal 'Vui lòng chọn một đối tượng.', CommandMessages.error_message(:empty_selection)
            assert_equal 'Vui lòng chỉ chọn một đối tượng.', CommandMessages.error_message(:multiple_selection)
            assert_equal(
              'Hệ ngăn kéo này đã có đối tượng giữ vai trò tương ứng.',
              CommandMessages.error_message(:role_already_assigned)
            )
            assert_equal(
              'Không thể thay đổi đối tượng đang bị khóa.',
              CommandMessages.error_message(:locked_entity)
            )
          end

          def test_unknown_internal_code_never_leaks_to_user
            message = CommandMessages.error_message(:internal_secret_failure)

            assert_equal CommandMessages::UNKNOWN_ERROR, message
            refute_includes message, 'internal_secret_failure'
          end

          def test_success_and_idempotent_messages
            assert_equal(
              'Đã gán đối tượng làm khoang ngăn kéo.',
              CommandMessages.success_message(:drawer_opening, :assigned)
            )
            assert_equal(
              'Đối tượng đã được gán vai trò này.',
              CommandMessages.success_message(:drawer_opening, :unchanged)
            )
          end

          def test_reassignment_confirmation_uses_readable_role_names
            message = CommandMessages.reassign_confirmation(
              :drawer_slide_left,
              :drawer_slide_right
            )

            assert_equal(
              'Đối tượng đang được gán làm ray trái. Bạn có muốn đổi thành ray phải không?',
              message
            )
            refute_includes message, 'drawer_slide_left'
          end
        end
      end
    end
  end
end
