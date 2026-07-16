# frozen_string_literal: true

require 'json'
require_relative 'selection_validator'
require_relative 'specification_owner'
require_relative 'specification_editor_presenter'
require_relative 'specification_editor_parser'

# HtmlDialog coordinator for editing one assigned drawer system. The dialog is
# bound to the originally selected entity, role, owner, and system ID; browser
# payloads never choose the persistence target. This layer alone owns the
# single SketchUp operation created by a successful save.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SpecificationEditor
          DIALOG_TITLE = 'Thông số ngăn kéo'
          OPERATION_SAVE = 'Lưu thông số ngăn kéo'
          PREFERENCES_KEY = 'sonvu_drawer_specification_editor'
          UI_FILE = File.expand_path('ui/specification_editor.html', __dir__).freeze

          ERROR_MESSAGES = {
            entity_not_assigned: 'Đối tượng chưa được gán vai trò ngăn kéo.',
            invalid_system_id: 'Dữ liệu vai trò ngăn kéo của đối tượng không hợp lệ.',
            missing_system: 'Không tìm thấy dữ liệu hệ ngăn kéo.',
            duplicate_role: 'Hệ ngăn kéo có nhiều đối tượng cùng vai trò. Vui lòng kiểm tra lại.',
            stale_dialog: 'Dữ liệu hệ ngăn kéo đã thay đổi. Vui lòng đóng và mở lại cửa sổ.',
            deleted_entity: 'Đối tượng đã chọn không còn tồn tại.',
            invalid_specification: 'Dữ liệu ngăn kéo không hợp lệ.',
            unavailable_dialog: 'Phiên bản SketchUp này không hỗ trợ cửa sổ chỉnh sửa thông số.',
            save_failed: 'Không thể lưu thông số ngăn kéo.',
            open_failed: 'Không thể mở thông số ngăn kéo.'
          }.freeze

          Session = Struct.new(
            :dialog,
            :model,
            :scope,
            :entity,
            :selected_role,
            :drawer_system_id,
            :owner,
            :base_specification,
            :initial_payload
          )

          module_function

          def open_selected(model:)
            validation = SelectionValidator.validate_single_assignable_entity(model.selection)
            return validation unless validation[:success]

            entity = validation[:entity]
            identity = Metadata.read(entity)
            role = identity[:drawer_object_type]
            system_id = identity[:drawer_system_id]
            unless role && system_id
              return failure(:entity_not_assigned, entity: entity)
            end
            unless Identity.valid_object_type?(role) && Identity.valid_system_id?(system_id)
              return failure(:invalid_system_id, entity: entity)
            end

            show(
              model: model,
              scope: model.active_entities,
              entity: entity,
              drawer_system_id: system_id,
              selected_role: role
            )
          rescue Metadata::MetadataError => e
            failure(e.code, entity: entity)
          rescue StandardError
            failure(:open_failed, entity: entity)
          end

          def show(model:, scope:, entity:, drawer_system_id:, selected_role: nil)
            existing = sessions[drawer_system_id.to_s]
            if existing
              focus_dialog(existing.dialog)
              return success(existing, status: :focused)
            end
            return failure(:unavailable_dialog, entity: entity) unless html_dialog_available?

            owner = SpecificationOwner.find(
              scope: scope,
              drawer_system_id: drawer_system_id
            )
            return failure(:missing_system, entity: entity) unless owner

            specification = SpecificationOwner.read(
              scope: scope,
              drawer_system_id: drawer_system_id
            )
            if specification && specification.drawer_system_id &&
               specification.drawer_system_id != drawer_system_id.to_s
              return failure(:invalid_specification, entity: entity)
            end
            selected_role ||= Metadata.drawer_object_type(entity)
            payload = SpecificationEditorPresenter.present(
              scope: scope,
              drawer_system_id: drawer_system_id,
              selected_entity: entity,
              specification: specification
            )
            dialog = create_dialog
            session = Session.new(
              dialog,
              model,
              scope,
              entity,
              selected_role.to_s,
              drawer_system_id.to_s,
              owner,
              specification,
              deep_copy(payload)
            )
            sessions[session.drawer_system_id] = session
            configure_dialog(session)
            dialog.show
            success(session, status: :opened)
          rescue SpecificationOwner::OwnerError => e
            failure(e.code, entity: entity)
          rescue Metadata::MetadataError, Persistence::PersistenceError
            failure(:invalid_specification, entity: entity)
          rescue StandardError
            sessions.delete(drawer_system_id.to_s)
            failure(:open_failed, entity: entity)
          end

          def handle_ready(session)
            send_to_dialog(session, 'load', deep_copy(session.initial_payload))
            success(session, status: :ready)
          end

          def handle_preview(session, payload)
            verify_session!(session)
            preview = SpecificationEditorParser.calculate_preview(payload)
            send_to_dialog(session, 'showPreview', preview)
            success(session, status: :previewed, details: { preview: preview })
          rescue SpecificationEditorParser::ParserError => e
            callback_failure(session, e.code, e.message, field: e.field)
          rescue EditorStateError => e
            callback_failure(session, e.code, e.message)
          rescue StandardError
            callback_failure(session, :invalid_specification, ERROR_MESSAGES[:invalid_specification])
          end

          def handle_resolve_slide(session, payload)
            verify_session!(session)
            resolved = SpecificationEditorParser.resolve_slide_for_ui(payload)
            send_to_dialog(session, 'applySlideConfiguration', resolved)
            success(session, status: :slide_resolved, details: { slide: resolved })
          rescue SpecificationEditorParser::ParserError => e
            callback_failure(session, e.code, e.message, field: e.field)
          rescue EditorStateError => e
            callback_failure(session, e.code, e.message)
          rescue StandardError
            callback_failure(session, :invalid_specification, ERROR_MESSAGES[:invalid_specification])
          end

          def handle_reset(session)
            send_to_dialog(session, 'load', deep_copy(session.initial_payload))
            success(session, status: :reset)
          rescue StandardError
            callback_failure(session, :invalid_specification, ERROR_MESSAGES[:invalid_specification])
          end

          def handle_cancel(session)
            session.dialog.close if session.dialog.respond_to?(:close)
            cleanup(session)
            success(session, status: :cancelled)
          end

          def handle_save(session, payload)
            verify_session!(session)
            parsed = SpecificationEditorParser.parse(
              payload,
              drawer_system_id: session.drawer_system_id,
              base_specification: session.base_specification
            )
            verify_session!(session)

            started = false
            session.model.start_operation(OPERATION_SAVE, true)
            started = true
            SpecificationOwner.write(
              scope: session.scope,
              drawer_system_id: session.drawer_system_id,
              specification: parsed.specification
            )
            session.model.commit_operation
            started = false
            finish_successful_save(session, parsed.warnings)
            success(
              session,
              status: :saved,
              details: { specification: parsed.specification, warnings: parsed.warnings }
            )
          rescue SpecificationEditorParser::ParserError => e
            session.model.abort_operation if defined?(started) && started
            callback_failure(session, e.code, e.message, field: e.field)
          rescue EditorStateError => e
            session.model.abort_operation if defined?(started) && started
            callback_failure(session, e.code, e.message)
          rescue SpecificationOwner::OwnerError => e
            session.model.abort_operation if defined?(started) && started
            callback_failure(session, e.code, owner_error_message(e.code))
          rescue Metadata::MetadataError, Persistence::PersistenceError
            session.model.abort_operation if defined?(started) && started
            callback_failure(session, :save_failed, ERROR_MESSAGES[:save_failed])
          rescue StandardError
            session.model.abort_operation if defined?(started) && started
            callback_failure(session, :save_failed, ERROR_MESSAGES[:save_failed])
          end

          def configure_dialog(session)
            dialog = session.dialog
            dialog.set_file(UI_FILE)
            dialog.add_action_callback('drawer_editor_ready') do |_context|
              handle_ready(session)
            end
            dialog.add_action_callback('drawer_editor_preview') do |_context, payload|
              handle_preview(session, payload)
            end
            dialog.add_action_callback('drawer_editor_save') do |_context, payload|
              handle_save(session, payload)
            end
            dialog.add_action_callback('drawer_editor_cancel') do |_context|
              handle_cancel(session)
            end
            dialog.add_action_callback('drawer_editor_reset') do |_context|
              handle_reset(session)
            end
            dialog.add_action_callback('drawer_editor_resolve_slide') do |_context, payload|
              handle_resolve_slide(session, payload)
            end
            dialog.set_on_closed { cleanup(session) }
            dialog.center if dialog.respond_to?(:center)
          end

          def create_dialog
            UI::HtmlDialog.new(
              dialog_title: DIALOG_TITLE,
              preferences_key: PREFERENCES_KEY,
              scrollable: true,
              resizable: true,
              width: 920,
              height: 780,
              min_width: 720,
              min_height: 620,
              style: html_dialog_style
            )
          end

          def html_dialog_available?
            defined?(::UI::HtmlDialog)
          end

          def html_dialog_style
            if defined?(::UI::HtmlDialog::STYLE_DIALOG)
              ::UI::HtmlDialog::STYLE_DIALOG
            else
              1
            end
          end

          def focus_dialog(dialog)
            dialog.bring_to_front if dialog.respond_to?(:bring_to_front)
          end

          class EditorStateError < ArgumentError
            attr_reader :code

            def initialize(code, message)
              @code = code
              super(message)
            end
          end

          def verify_session!(session)
            if SelectionValidator.deleted_entity?(session.entity)
              raise EditorStateError.new(:deleted_entity, ERROR_MESSAGES[:deleted_entity])
            end
            identity = Metadata.read(session.entity)
            unless identity[:drawer_system_id] == session.drawer_system_id &&
                   identity[:drawer_object_type] == session.selected_role
              raise EditorStateError.new(:stale_dialog, ERROR_MESSAGES[:stale_dialog])
            end
            current_owner = SpecificationOwner.find(
              scope: session.scope,
              drawer_system_id: session.drawer_system_id
            )
            unless current_owner && current_owner.equal?(session.owner)
              raise EditorStateError.new(:stale_dialog, ERROR_MESSAGES[:stale_dialog])
            end

            true
          rescue SpecificationOwner::OwnerError => e
            raise EditorStateError.new(e.code, owner_error_message(e.code))
          rescue Metadata::MetadataError
            raise EditorStateError.new(:stale_dialog, ERROR_MESSAGES[:stale_dialog])
          end

          def send_to_dialog(session, function_name, payload)
            json = JSON.generate(payload)
            session.dialog.execute_script(
              "window.SonVuDrawerEditor.#{function_name}(#{json});"
            )
          end

          def finish_successful_save(session, warnings)
            send_to_dialog(
              session,
              'saved',
              { message: 'Đã lưu thông số ngăn kéo.', warnings: warnings }
            )
            show_warnings(warnings)
            session.dialog.close if session.dialog.respond_to?(:close)
          rescue StandardError
            # Persistence is already committed. A browser/window notification
            # failure must not report the committed model operation as failed.
            nil
          ensure
            cleanup(session)
          end

          def show_warnings(warnings)
            return if warnings.nil? || warnings.empty?
            return unless defined?(::UI) && ::UI.respond_to?(:messagebox)

            ::UI.messagebox(warnings.join("\n"))
          rescue StandardError
            nil
          end

          def callback_failure(session, code, message, field: nil)
            error = { code: code.to_s, message: message, field: field&.to_s }
            send_to_dialog(session, 'showError', error)
            failure(code, entity: session.entity, details: { message: message, field: field })
          rescue StandardError
            failure(code, entity: session.entity, details: { message: message, field: field })
          end

          def cleanup(session)
            current = sessions[session.drawer_system_id]
            sessions.delete(session.drawer_system_id) if current.equal?(session)
            true
          end

          def sessions
            @sessions ||= {}
          end

          def reset_sessions!
            @sessions = {}
          end

          def deep_copy(value)
            JSON.parse(JSON.generate(value), symbolize_names: true)
          end

          def success(session, status:, details: {})
            {
              success: true,
              entity: session.entity,
              drawer_system_id: session.drawer_system_id,
              error_code: nil,
              details: details.merge(status: status, session: session)
            }
          end

          def failure(code, entity: nil, details: {})
            {
              success: false,
              entity: entity,
              drawer_system_id: nil,
              error_code: code.to_sym,
              details: details
            }
          end

          def message_for(code)
            ERROR_MESSAGES.fetch(code.to_sym, ERROR_MESSAGES[:open_failed])
          rescue NoMethodError
            ERROR_MESSAGES[:open_failed]
          end

          def owner_error_message(code)
            ERROR_MESSAGES.fetch(code.to_sym, ERROR_MESSAGES[:stale_dialog])
          end
        end
      end
    end
  end
end
