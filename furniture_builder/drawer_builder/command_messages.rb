# frozen_string_literal: true

# Central Vietnamese copy for the manual drawer role-assignment command layer.
# Internal error codes and UUID values must never be shown directly to users.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module CommandMessages
          MENU_DRAWER = 'Ngăn kéo'
          MENU_ASSIGN_ROLE = 'Gán vai trò'
          COMMAND_UNASSIGN = 'Bỏ gán vai trò ngăn kéo'
          COMMAND_EDIT_SPECIFICATION = 'Chỉnh sửa thông số ngăn kéo'

          COMMAND_LABELS = {
            drawer_opening: 'Gán làm khoang ngăn kéo',
            drawer_slide_left: 'Gán làm ray trái',
            drawer_slide_right: 'Gán làm ray phải',
            drawer_box: 'Gán làm thùng ngăn kéo',
            drawer_system: 'Gán làm hệ ngăn kéo'
          }.freeze

          ROLE_NAMES = {
            drawer_opening: 'khoang ngăn kéo',
            drawer_slide_left: 'ray trái',
            drawer_slide_right: 'ray phải',
            drawer_box: 'thùng ngăn kéo',
            drawer_system: 'hệ ngăn kéo'
          }.freeze

          COMMAND_TOOLTIPS = {
            drawer_opening: 'Gán Group hoặc Component đã chọn làm khoang ngăn kéo',
            drawer_slide_left: 'Gán đối tượng đã chọn làm ray trái',
            drawer_slide_right: 'Gán đối tượng đã chọn làm ray phải',
            drawer_box: 'Gán đối tượng đã chọn làm thùng ngăn kéo',
            drawer_system: 'Gán đối tượng đã chọn làm hệ ngăn kéo'
          }.freeze

          COMMAND_STATUS_TEXTS = {
            drawer_opening: 'Chọn một Group hoặc Component để gán làm khoang ngăn kéo',
            drawer_slide_left: 'Chọn một Group hoặc Component để gán làm ray trái',
            drawer_slide_right: 'Chọn một Group hoặc Component để gán làm ray phải',
            drawer_box: 'Chọn một Group hoặc Component để gán làm thùng ngăn kéo',
            drawer_system: 'Chọn một Group hoặc Component để gán làm hệ ngăn kéo'
          }.freeze

          SUCCESS_MESSAGES = {
            drawer_opening: 'Đã gán đối tượng làm khoang ngăn kéo.',
            drawer_slide_left: 'Đã gán đối tượng làm ray trái.',
            drawer_slide_right: 'Đã gán đối tượng làm ray phải.',
            drawer_box: 'Đã gán đối tượng làm thùng ngăn kéo.',
            drawer_system: 'Đã gán đối tượng làm hệ ngăn kéo.'
          }.freeze

          ERROR_MESSAGES = {
            empty_selection: 'Vui lòng chọn một đối tượng.',
            multiple_selection: 'Vui lòng chỉ chọn một đối tượng.',
            unsupported_entity: 'Vui lòng chọn một Group hoặc Component hợp lệ.',
            shared_component_definition_risk: 'Vui lòng chọn một Group hoặc Component hợp lệ.',
            deleted_entity: 'Vui lòng chọn một Group hoặc Component hợp lệ.',
            role_already_assigned: 'Hệ ngăn kéo này đã có đối tượng giữ vai trò tương ứng.',
            entity_assigned_to_different_system: 'Đối tượng đang thuộc một hệ ngăn kéo khác.',
            move_required: 'Đối tượng đang thuộc một hệ ngăn kéo khác.',
            entity_assigned_to_different_role: 'Đối tượng đã được gán một vai trò ngăn kéo khác.',
            entity_assignment_conflict: 'Đối tượng đã được gán một vai trò ngăn kéo khác.',
            reassignment_required: 'Đối tượng đã được gán một vai trò ngăn kéo khác.',
            locked_entity: 'Không thể thay đổi đối tượng đang bị khóa.',
            invalid_system_id: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            invalid_metadata_version: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            future_metadata_version: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            unsupported_object_type: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            invalid_drawer_index: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            invalid_source: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            invalid_role: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            entity_not_assigned: 'Đối tượng chưa được gán vai trò ngăn kéo.',
            missing_system: 'Không tìm thấy dữ liệu hệ ngăn kéo.',
            duplicate_role: 'Hệ ngăn kéo có nhiều đối tượng cùng vai trò. Vui lòng kiểm tra lại.',
            invalid_specification: 'Dữ liệu ngăn kéo không hợp lệ.',
            unavailable_dialog: 'Phiên bản SketchUp này không hỗ trợ cửa sổ chỉnh sửa thông số.',
            open_failed: 'Không thể mở thông số ngăn kéo.'
          }.freeze

          SAME_ROLE = 'Đối tượng đã được gán vai trò này.'
          UNKNOWN_ERROR = 'Không thể gán vai trò ngăn kéo. Vui lòng kiểm tra lại đối tượng.'
          NO_ROLE = 'Đối tượng chưa được gán vai trò ngăn kéo.'
          UNASSIGN_CONFIRMATION = 'Bạn có chắc muốn bỏ vai trò ngăn kéo của đối tượng đã chọn không?'
          UNASSIGN_SUCCESS = 'Đã bỏ vai trò ngăn kéo của đối tượng.'
          MOVE_CONFIRMATION = 'Đối tượng đang thuộc một hệ ngăn kéo khác. Bạn có muốn chuyển đối tượng sang hệ đã chọn không?'
          ONE_SYSTEM_CONFIRMATION = 'Đã tìm thấy một hệ ngăn kéo. Bạn có muốn gán đối tượng này vào hệ đó không?'
          NO_SYSTEM_CONFIRMATION = 'Chưa có hệ ngăn kéo phù hợp. Bạn có muốn tạo một hệ mới cho đối tượng này không?'

          module_function

          def command_label(role)
            COMMAND_LABELS.fetch(normalized_role(role), 'Gán vai trò ngăn kéo')
          end

          def role_name(role)
            ROLE_NAMES.fetch(normalized_role(role), 'vai trò ngăn kéo')
          end

          def command_tooltip(role)
            COMMAND_TOOLTIPS.fetch(normalized_role(role), 'Gán vai trò ngăn kéo cho đối tượng đã chọn')
          end

          def command_status_text(role)
            COMMAND_STATUS_TEXTS.fetch(normalized_role(role), 'Chọn một Group hoặc Component để gán vai trò ngăn kéo')
          end

          def success_message(role, status = nil)
            return SAME_ROLE if status.to_sym == :unchanged

            SUCCESS_MESSAGES.fetch(normalized_role(role), UNKNOWN_ERROR)
          rescue NoMethodError
            SUCCESS_MESSAGES.fetch(normalized_role(role), UNKNOWN_ERROR)
          end

          def error_message(error_code)
            ERROR_MESSAGES.fetch(error_code.to_sym, UNKNOWN_ERROR)
          rescue NoMethodError
            UNKNOWN_ERROR
          end

          def message_for_result(result, role: nil)
            return UNKNOWN_ERROR unless result.respond_to?(:[])

            if result[:success]
              status = result.fetch(:details, {})[:status]
              return UNASSIGN_SUCCESS if status == :unassigned

              success_message(role || result[:role], status)
            else
              error_message(result[:error_code])
            end
          end

          def reassign_confirmation(current_role, requested_role)
            "Đối tượng đang được gán làm #{role_name(current_role)}. " \
              "Bạn có muốn đổi thành #{role_name(requested_role)} không?"
          end

          def normalized_role(role)
            role.to_s.to_sym
          end
        end
      end
    end
  end
end
