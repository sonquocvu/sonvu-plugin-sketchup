# frozen_string_literal: true

require_relative '../../shared/ui_helpers'
require_relative 'role_assignment'
require_relative 'system_picker'
require_relative 'command_messages'
require_relative 'specification_editor'
require_relative 'toolbar'

# Vietnamese SketchUp command layer for assigning semantic drawer roles. The
# command owns the exact named model operation and calls Step 5 services with
# manage_operation: false to avoid nested operations.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module Commands
          JOIN_EXISTING_ROLES = %i[
            drawer_slide_left drawer_slide_right drawer_box
          ].freeze
          ICON_BASENAMES = {
            drawer_opening: 'drawer_opening',
            drawer_slide_left: 'drawer_slide_left',
            drawer_slide_right: 'drawer_slide_right',
            drawer_box: 'drawer_box'
          }.freeze

          module_function

          def register_menu(root_menu = nil)
            register_menu_items(root_menu)
            register_context_menu
            Toolbar.register
          end

          def register_menu_items(root_menu = nil)
            return if @menu_registered

            root_menu ||= CNCPlugins.extension_menu
            drawer_menu = root_menu.add_submenu(CommandMessages::MENU_DRAWER)
            assignment_menu = drawer_menu.add_submenu(CommandMessages::MENU_ASSIGN_ROLE)
            add_assignment_items(assignment_menu, include_unassign: true)
            drawer_menu.add_separator
            drawer_menu.add_item(edit_specification_command)
            @menu_registered = true
          end

          def register_context_menu
            return if @context_menu_registered

            UI.add_context_menu_handler do |menu|
              model = Sketchup.active_model
              validation = SelectionValidator.validate_single_assignable_entity(model.selection)
              next unless validation[:success]

              drawer_menu = menu.add_submenu(CommandMessages::MENU_DRAWER)
              assignment_menu = drawer_menu.add_submenu(CommandMessages::MENU_ASSIGN_ROLE)
              add_assignment_items(
                assignment_menu,
                include_unassign: RoleAssignment.assigned?(validation[:entity])
              )
              if standalone_assigned?(validation[:entity])
                drawer_menu.add_separator
                drawer_menu.add_item(edit_specification_command)
              end
            end
            @context_menu_registered = true
          end

          def add_assignment_items(menu, include_unassign:)
            CommandMessages::COMMAND_LABELS.each_key do |role|
              menu.add_item(role_command(role))
            end
            if include_unassign
              menu.add_separator
              menu.add_item(unassign_command)
            end
          end

          def role_command(role)
            @role_commands ||= {}
            @role_commands[role.to_sym] ||= begin
              label = CommandMessages.command_label(role)
              command = UI::Command.new(label) { assign_selected(role) }
              command.tooltip = CommandMessages.command_tooltip(role)
              command.status_bar_text = CommandMessages.command_status_text(role)
              assign_command_icons(command, ICON_BASENAMES[role.to_sym])
              set_assignment_validation(command)
              command
            end
          end

          def unassign_command
            @unassign_command ||= begin
              command = UI::Command.new(CommandMessages::COMMAND_UNASSIGN) { unassign_selected }
              command.tooltip = 'Xóa vai trò ngăn kéo khỏi đối tượng đã chọn'
              command.status_bar_text = 'Chọn một đối tượng đã được gán vai trò ngăn kéo'
              assign_command_icons(command, 'drawer_unassign')
              set_assigned_entity_validation(command)
              command
            end
          end

          def edit_specification_command
            @edit_specification_command ||= begin
              label = CommandMessages::COMMAND_EDIT_SPECIFICATION
              command = UI::Command.new(label) { edit_selected_specification }
              command.tooltip = 'Chỉnh sửa kích thước và thông số ray của hệ ngăn kéo'
              command.status_bar_text = 'Chọn một đối tượng đã được gán vai trò ngăn kéo để chỉnh sửa'
              assign_command_icons(command, 'drawer_edit')
              set_assigned_entity_validation(command)
              command
            end
          end

          def edit_selected_specification
            return unless licensed?

            result = SpecificationEditor.open_selected(model: Sketchup.active_model)
            unless result[:success]
              CNCPlugins::UIHelpers.message(CommandMessages.error_message(result[:error_code]))
            end
            result
          rescue StandardError
            show_failure(:open_failed)
          end

          def assign_selected(role, target_system_id: nil)
            return unless licensed?

            model = Sketchup.active_model
            validation = SelectionValidator.validate_single_assignable_entity(model.selection)
            return show_validation_failure(validation) unless validation[:success]

            entity = validation[:entity]
            existing = Metadata.read(entity)
            unless identity_pair_valid?(existing)
              return show_failure(:invalid_system_id, entity: entity, role: role)
            end

            target_system_id = determine_target_system(
              model,
              role,
              existing,
              target_system_id
            )
            return cancelled_result(entity, role) if target_system_id == :cancelled

            action = assignment_action(
              existing,
              role,
              target_system_id,
              entity: entity
            )
            return action[:result] if action[:cancelled]

            execute_assignment_operation(
              model,
              entity,
              role,
              target_system_id,
              action[:method]
            )
          rescue Metadata::MetadataError => e
            show_failure(e.code, role: role)
          rescue StandardError
            show_failure(:unknown_error, role: role)
          end

          def unassign_selected
            return unless licensed?

            model = Sketchup.active_model
            validation = SelectionValidator.validate_single_assignable_entity(model.selection)
            return show_validation_failure(validation) unless validation[:success]

            entity = validation[:entity]
            unless RoleAssignment.assigned?(entity)
              CNCPlugins::UIHelpers.message(CommandMessages::NO_ROLE)
              return SelectionValidator.failure_result(:entity_not_assigned, entity: entity)
            end
            return cancelled_result(entity, RoleAssignment.assigned_role(entity)) unless confirmed?(
              CommandMessages::UNASSIGN_CONFIRMATION
            )

            execute_operation(model, CommandMessages::COMMAND_UNASSIGN) do
              RoleAssignment.unassign(
                entity: entity,
                model: model,
                manage_operation: false
              )
            end
          rescue Metadata::MetadataError => e
            show_failure(e.code)
          rescue StandardError
            show_failure(:unknown_error)
          end

          def determine_target_system(model, role, existing, explicit_system_id)
            return explicit_system_id.to_s if explicit_system_id
            return existing[:drawer_system_id] if existing[:drawer_system_id]
            return nil unless JOIN_EXISTING_ROLES.include?(role.to_sym)

            choice = SystemPicker.choose(model.active_entities)
            return choice[:drawer_system_id] if choice[:status] == :selected
            return nil if choice[:status] == :create_new

            :cancelled
          end

          def assignment_action(existing, requested_role, target_system_id, entity:)
            current_role = existing[:drawer_object_type]
            current_system_id = existing[:drawer_system_id]
            return { method: :assign, cancelled: false } unless current_role

            same_role = current_role == requested_role.to_s
            same_system = target_system_id.nil? || current_system_id == target_system_id.to_s
            return { method: :assign, cancelled: false } if same_role && same_system

            unless same_role
              confirmation = CommandMessages.reassign_confirmation(current_role, requested_role)
              return cancellation_action(entity, requested_role) unless confirmed?(confirmation)
            end
            unless same_system
              return cancellation_action(entity, requested_role) unless confirmed?(
                CommandMessages::MOVE_CONFIRMATION
              )
            end

            method = if same_system
                       :reassign
                     elsif same_role
                       :move
                     else
                       :move_and_reassign
                     end
            { method: method, cancelled: false }
          end

          def execute_assignment_operation(model, entity, role, target_system_id, method)
            execute_operation(model, CommandMessages.command_label(role), role: role) do
              service_arguments = {
                entity: entity,
                scope: model.active_entities,
                model: model,
                manage_operation: false
              }
              case method
              when :assign
                RoleAssignment.assign(
                  **service_arguments,
                  role: role,
                  drawer_system_id: target_system_id
                )
              when :reassign
                RoleAssignment.reassign(
                  **service_arguments,
                  role: role,
                  drawer_system_id: target_system_id
                )
              when :move
                RoleAssignment.move(
                  **service_arguments,
                  drawer_system_id: target_system_id
                )
              when :move_and_reassign
                RoleAssignment.move_and_reassign(
                  **service_arguments,
                  role: role,
                  drawer_system_id: target_system_id
                )
              else
                SelectionValidator.failure_result(:invalid_assignment_mode, entity: entity, role: role)
              end
            end
          end

          def execute_operation(model, operation_name, role: nil)
            started = false
            model.start_operation(operation_name, true)
            started = true
            result = yield
            if result[:success]
              model.commit_operation
              started = false
            else
              model.abort_operation
              started = false
            end
            CNCPlugins::UIHelpers.message(CommandMessages.message_for_result(result, role: role))
            result
          rescue StandardError
            model.abort_operation if started
            show_failure(:unknown_error, role: role)
          end

          def identity_pair_valid?(values)
            role = values[:drawer_object_type]
            system_id = values[:drawer_system_id]
            (role.nil? && system_id.nil?) || (!role.nil? && !system_id.nil?)
          end

          def standalone_assigned?(entity)
            values = Metadata.read(entity)
            Identity.valid_object_type?(values[:drawer_object_type]) &&
              Identity.valid_system_id?(values[:drawer_system_id])
          rescue Metadata::MetadataError
            false
          end

          def set_assignment_validation(command)
            return unless command.respond_to?(:set_validation_proc)

            command.set_validation_proc do
              command_state(assignment_selection_available?)
            end
          end

          def set_assigned_entity_validation(command)
            return unless command.respond_to?(:set_validation_proc)

            command.set_validation_proc do
              command_state(assigned_selection_available?)
            end
          end

          def assignment_selection_available?
            model = Sketchup.active_model
            return false unless model

            SelectionValidator.validate_single_assignable_entity(model.selection)[:success]
          rescue StandardError
            false
          end

          def assigned_selection_available?
            model = Sketchup.active_model
            return false unless model

            validation = SelectionValidator.validate_single_assignable_entity(model.selection)
            validation[:success] && standalone_assigned?(validation[:entity])
          rescue StandardError
            false
          end

          def command_state(enabled)
            enabled ? enabled_command_state : disabled_command_state
          end

          def enabled_command_state
            defined?(::MF_ENABLED) ? ::MF_ENABLED : 0
          end

          def disabled_command_state
            defined?(::MF_GRAYED) ? ::MF_GRAYED : 1
          end

          def assign_command_icons(command, basename)
            return if basename.nil? || basename.to_s.empty?

            root = File.expand_path('icons', __dir__)
            small = File.join(root, "#{basename}_small.svg")
            large = File.join(root, "#{basename}_large.svg")
            command.small_icon = small if File.exist?(small)
            command.large_icon = large if File.exist?(large)
          end

          def show_validation_failure(result)
            CNCPlugins::UIHelpers.message(CommandMessages.error_message(result[:error_code]))
            result
          end

          def show_failure(error_code, entity: nil, role: nil)
            result = SelectionValidator.failure_result(error_code, entity: entity, role: role)
            CNCPlugins::UIHelpers.message(CommandMessages.error_message(error_code))
            result
          end

          def cancellation_action(entity, role)
            { cancelled: true, result: cancelled_result(entity, role) }
          end

          def cancelled_result(entity, role)
            SelectionValidator.failure_result(:cancelled, entity: entity, role: role)
          end

          def confirmed?(message)
            result = UI.messagebox(message, yes_no_flag)
            result == yes_result
          end

          def yes_no_flag
            defined?(::MB_YESNO) ? ::MB_YESNO : 4
          end

          def yes_result
            defined?(::IDYES) ? ::IDYES : 6
          end

          def licensed?
            CNCPlugins::Licensing::Manager.require_feature(
              CNCPlugins::Licensing::Config::FEATURE_FURNITURE_BUILDER
            )
          end
        end
      end
    end
  end
end
