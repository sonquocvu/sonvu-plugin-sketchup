# frozen_string_literal: true

require 'minitest/autorun'

MB_YESNO = 4 unless defined?(::MB_YESNO)
IDYES = 6 unless defined?(::IDYES)
IDNO = 7 unless defined?(::IDNO)
MF_ENABLED = 0 unless defined?(::MF_ENABLED)
MF_GRAYED = 1 unless defined?(::MF_GRAYED)

module UI
  class Command
    attr_reader :name
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon

    def initialize(name, &block)
      @name = name
      @block = block
    end

    def call
      @block.call
    end

    def set_validation_proc(&block)
      @validation_proc = block
    end

    def validation_state
      @validation_proc ? @validation_proc.call : MF_ENABLED
    end
  end

  class Toolbar
    attr_reader :name, :entries, :restore_count

    def initialize(name)
      @name = name
      @entries = []
      @restore_count = 0
      UI.toolbars << self
    end

    def add_item(command)
      @entries << { type: :item, command: command }
      @entries.length
    end

    def add_separator
      @entries << { type: :separator }
    end

    def restore
      @restore_count += 1
    end
  end

  class Menu
    attr_reader :label, :entries

    def initialize(label = nil)
      @label = label
      @entries = []
    end

    def add_submenu(label)
      submenu = self.class.new(label)
      @entries << { type: :submenu, label: label, menu: submenu }
      submenu
    end

    def add_item(command)
      label = command.respond_to?(:name) ? command.name : command.to_s
      @entries << { type: :item, label: label, command: command }
      @entries.length
    end

    def add_separator
      @entries << { type: :separator }
    end

    def submenu(label)
      entry = @entries.find { |item| item[:type] == :submenu && item[:label] == label }
      entry && entry[:menu]
    end
  end

  class << self
    attr_reader :messages, :input_calls, :context_handlers, :toolbars

    def reset
      @messages = []
      @confirmation_answers = []
      @input_answers = []
      @input_calls = []
      @context_handlers = []
      @toolbars = []
    end

    def queue_confirmations(*answers)
      @confirmation_answers.concat(answers)
    end

    def queue_inputs(*answers)
      @input_answers.concat(answers)
    end

    def messagebox(message, *flags)
      @messages << message
      return nil if flags.empty?

      @confirmation_answers.empty? ? IDNO : @confirmation_answers.shift
    end

    def inputbox(prompts, defaults, lists, title)
      @input_calls << [prompts, defaults, lists, title]
      @input_answers.shift
    end

    def add_context_menu_handler(&block)
      @context_handlers << block
    end
  end

  reset
end

module Sketchup
  class << self
    attr_accessor :active_model
  end
end

module SonVu
  module CNCPlugins
    module Licensing
      module Config
        FEATURE_FURNITURE_BUILDER = 'furniture_builder' unless const_defined?(:FEATURE_FURNITURE_BUILDER, false)
      end

      module Manager
        class << self
          attr_accessor :allowed
          attr_reader :feature_calls
        end

        module_function

        def reset
          @allowed = true
          @feature_calls = []
        end

        def require_feature(feature)
          @feature_calls << feature
          @allowed
        end

        reset
      end
    end
  end
end

require_relative '../commands'
require_relative '../legacy_adapter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class CommandsTest < Minitest::Test
          class ModelStub
            attr_reader :selection, :active_entities, :operations, :commits, :aborts

            def initialize
              @selection = []
              @active_entities = []
              @operations = []
              @commits = 0
              @aborts = 0
            end

            def start_operation(name, transparent)
              @operations << [name, transparent]
            end

            def commit_operation
              @commits += 1
            end

            def abort_operation
              @aborts += 1
            end
          end

          class EntityStub
            attr_reader :model, :writes, :deletes

            def initialize(model:, type: :group, valid: true, locked: false, values: {})
              @model = model
              @type = type
              @valid = valid
              @locked = locked
              @attributes = {}
              @writes = []
              @deletes = []
              values.each { |key, value| @attributes[[Metadata::DICTIONARY, key.to_s]] = value }
              model.active_entities << self
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
              @writes << [dictionary, key, value]
              @attributes[[dictionary, key]] = value
            end

            def delete_attribute(dictionary, key)
              @deletes << [dictionary, key]
              @attributes.delete([dictionary, key])
            end
          end

          class UnsupportedStub
            def drawer_assignment_entity_type
              :face
            end
          end

          def setup
            UI.reset
            Licensing::Manager.reset
            @model = ModelStub.new
            Sketchup.active_model = @model
          end

          def test_empty_selection
            result = Commands.assign_selected(:drawer_opening)

            assert_failure result, :empty_selection
            assert_equal 'Vui lòng chọn một đối tượng.', UI.messages.last
            assert_empty @model.operations
          end

          def test_multiple_selection
            select_entities(new_entity, new_entity)

            result = Commands.assign_selected(:drawer_opening)

            assert_failure result, :multiple_selection
            assert_equal 'Vui lòng chỉ chọn một đối tượng.', UI.messages.last
          end

          def test_valid_group_assigns_opening_to_new_system_and_commits
            entity = new_entity
            select_entities(entity)

            result = Commands.assign_selected(:drawer_opening)

            assert_success result, :assigned
            assert Identity.valid_system_id?(result[:drawer_system_id])
            assert_equal :drawer_opening, RoleAssignment.assigned_role(entity)
            assert_equal 'Đã gán đối tượng làm khoang ngăn kéo.', UI.messages.last
            assert_operation 'Gán làm khoang ngăn kéo', commits: 1, aborts: 0
          end

          def test_valid_component_instance_assigns_system_role
            entity = new_entity(type: :component_instance)
            select_entities(entity)

            result = Commands.assign_selected(:drawer_system)

            assert_success result, :assigned
            assert_equal :drawer_system, RoleAssignment.assigned_role(entity)
            assert_operation 'Gán làm hệ ngăn kéo', commits: 1, aborts: 0
          end

          def test_unsupported_face_selection
            @model.selection << UnsupportedStub.new

            result = Commands.assign_selected(:drawer_box)

            assert_failure result, :unsupported_entity
            assert_equal 'Vui lòng chọn một Group hoặc Component hợp lệ.', UI.messages.last
          end

          def test_assigns_left_slide_to_one_existing_system_after_confirmation
            system_id = existing_system(:drawer_opening)
            entity = new_entity
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_slide_left)

            assert_success result, :assigned
            assert_equal system_id, result[:drawer_system_id]
            assert_includes UI.messages, CommandMessages::ONE_SYSTEM_CONFIRMATION
          end

          def test_assigns_right_slide_to_existing_system
            system_id = existing_system(:drawer_opening)
            entity = new_entity
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_slide_right)

            assert_success result, :assigned
            assert_equal system_id, Metadata.read(entity)[:drawer_system_id]
          end

          def test_assigns_box_to_existing_system
            system_id = existing_system(:drawer_opening)
            entity = new_entity
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_box)

            assert_success result, :assigned
            assert_equal system_id, Metadata.read(entity)[:drawer_system_id]
          end

          def test_no_existing_system_creates_partial_system_after_confirmation
            entity = new_entity
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_slide_left)

            assert_success result, :assigned
            assert Identity.valid_system_id?(result[:drawer_system_id])
            assert_equal CommandMessages::NO_SYSTEM_CONFIRMATION, UI.messages.first
          end

          def test_no_existing_system_creation_can_be_cancelled
            entity = new_entity
            select_entities(entity)
            UI.queue_confirmations(IDNO)

            result = Commands.assign_selected(:drawer_slide_left)

            assert_failure result, :cancelled
            refute RoleAssignment.assigned?(entity)
            assert_empty @model.operations
          end

          def test_multiple_system_picker_uses_selected_readable_label
            first_id = existing_system(:drawer_opening)
            second_id = existing_system(:drawer_box)
            entity = new_entity
            select_entities(entity)
            options = SystemPicker.systems(@model.active_entities)
            selected_option = options.find { |option| option[:drawer_system_id] == second_id }
            UI.queue_inputs([selected_option[:label]])

            result = Commands.assign_selected(:drawer_slide_left)

            assert_success result, :assigned
            assert_equal second_id, result[:drawer_system_id]
            refute_equal first_id, result[:drawer_system_id]
            refute_includes UI.input_calls.last[2].first, second_id
          end

          def test_same_role_is_idempotent_information_success
            entity = new_entity
            system_id = assign_direct(entity, :drawer_opening)
            select_entities(entity)
            writes = entity.writes.length

            result = Commands.assign_selected(:drawer_opening)

            assert_success result, :unchanged
            assert_equal system_id, result[:drawer_system_id]
            assert_equal writes, entity.writes.length
            assert_equal CommandMessages::SAME_ROLE, UI.messages.last
          end

          def test_role_reassignment_can_be_cancelled
            entity = new_entity
            assign_direct(entity, :drawer_slide_left)
            select_entities(entity)
            UI.queue_confirmations(IDNO)

            result = Commands.assign_selected(:drawer_slide_right)

            assert_failure result, :cancelled
            assert_equal :drawer_slide_left, RoleAssignment.assigned_role(entity)
            assert_empty @model.operations
          end

          def test_explicit_role_reassignment_after_confirmation
            entity = new_entity
            assign_direct(entity, :drawer_slide_left)
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_slide_right)

            assert_success result, :reassigned
            assert_equal :drawer_slide_right, RoleAssignment.assigned_role(entity)
            assert_operation 'Gán làm ray phải', commits: 1, aborts: 0
          end

          def test_system_move_can_be_cancelled
            entity = new_entity
            original_id = assign_direct(entity, :drawer_box)
            target_id = Identity.generate_system_id
            select_entities(entity)
            UI.queue_confirmations(IDNO)

            result = Commands.assign_selected(:drawer_box, target_system_id: target_id)

            assert_failure result, :cancelled
            assert_equal original_id, Metadata.read(entity)[:drawer_system_id]
            assert_empty @model.operations
          end

          def test_explicit_move_to_another_system_after_confirmation
            entity = new_entity
            original_id = assign_direct(entity, :drawer_box)
            target_id = Identity.generate_system_id
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.assign_selected(:drawer_box, target_system_id: target_id)

            assert_success result, :moved
            refute_equal original_id, result[:drawer_system_id]
            assert_equal target_id, Metadata.read(entity)[:drawer_system_id]
            assert_operation 'Gán làm thùng ngăn kéo', commits: 1, aborts: 0
          end

          def test_locked_entity_is_rejected
            entity = new_entity(locked: true)
            select_entities(entity)

            result = Commands.assign_selected(:drawer_opening)

            assert_failure result, :locked_entity
            assert_equal 'Không thể thay đổi đối tượng đang bị khóa.', UI.messages.last
            assert_empty @model.operations
          end

          def test_unassign_success_preserves_legacy_metadata
            legacy = {
              'part_kind' => 'drawer_box',
              'part_role' => 'drawer_bottom',
              'drawer_index' => 3,
              'hardware_type' => 'drawer_slide_left',
              'owner_part_key' => 'mat_ngan_keo_3'
            }
            entity = new_entity(values: legacy)
            assign_direct(entity, :drawer_box)
            select_entities(entity)
            UI.queue_confirmations(IDYES)

            result = Commands.unassign_selected

            assert_success result, :unassigned
            refute RoleAssignment.assigned?(entity)
            legacy.each do |key, value|
              assert_equal value, entity.get_attribute(Metadata::DICTIONARY, key)
            end
            assert_equal CommandMessages::UNASSIGN_SUCCESS, UI.messages.last
            assert_operation CommandMessages::COMMAND_UNASSIGN, commits: 1, aborts: 0
          end

          def test_unassign_can_be_cancelled
            entity = new_entity
            assign_direct(entity, :drawer_box)
            select_entities(entity)
            UI.queue_confirmations(IDNO)

            result = Commands.unassign_selected

            assert_failure result, :cancelled
            assert RoleAssignment.assigned?(entity)
            assert_empty @model.operations
          end

          def test_unassign_when_no_role_exists
            entity = new_entity
            select_entities(entity)

            result = Commands.unassign_selected

            assert_failure result, :entity_not_assigned
            assert_equal CommandMessages::NO_ROLE, UI.messages.last
            assert_empty @model.operations
          end

          def test_service_failure_aborts_command_operation
            system_id = existing_system(:drawer_opening)
            entity = new_entity
            select_entities(entity)

            result = Commands.assign_selected(
              :drawer_opening,
              target_system_id: system_id
            )

            assert_failure result, :role_already_assigned
            assert_equal 0, @model.commits
            assert_equal 1, @model.aborts
            assert_equal(
              'Hệ ngăn kéo này đã có đối tượng giữ vai trò tương ứng.',
              UI.messages.last
            )
          end

          def test_license_gate_runs_at_command_boundary
            entity = new_entity
            select_entities(entity)
            Licensing::Manager.allowed = false

            result = Commands.assign_selected(:drawer_opening)

            assert_nil result
            assert_equal [Licensing::Config::FEATURE_FURNITURE_BUILDER], Licensing::Manager.feature_calls
            refute RoleAssignment.assigned?(entity)
            assert_empty @model.operations
          end

          def test_editor_license_gate_runs_at_command_boundary
            entity = new_entity
            assign_direct(entity, :drawer_opening)
            select_entities(entity)
            Licensing::Manager.allowed = false

            result = Commands.edit_selected_specification

            assert_nil result
            assert_equal [Licensing::Config::FEATURE_FURNITURE_BUILDER], Licensing::Manager.feature_calls
            assert_empty @model.operations
          end

          def test_toolbar_license_gate_uses_the_shared_command
            entity = new_entity
            select_entities(entity)
            Licensing::Manager.allowed = false
            command = Commands.role_command(:drawer_opening)

            result = command.call

            assert_nil result
            assert_same command, Commands.role_command(:drawer_opening)
            assert_equal [Licensing::Config::FEATURE_FURNITURE_BUILDER], Licensing::Manager.feature_calls
            refute RoleAssignment.assigned?(entity)
          end

          def test_toolbar_is_registered_once_in_the_required_order_with_shared_commands
            reset_registration
            root = UI::Menu.new('SonVu CNC Plugins')

            Commands.register_menu(root)
            Commands.register_menu(root)

            assert_equal 1, UI.toolbars.length
            toolbar = UI.toolbars.first
            assert_equal Toolbar::TOOLBAR_NAME, toolbar.name
            assert_equal 1, toolbar.restore_count
            assert_equal 7, toolbar.entries.length
            assert_equal :separator, toolbar.entries[4][:type]
            expected = [
              Commands.role_command(:drawer_opening),
              Commands.role_command(:drawer_slide_left),
              Commands.role_command(:drawer_slide_right),
              Commands.role_command(:drawer_box),
              Commands.edit_specification_command,
              Commands.unassign_command
            ]
            actual = toolbar.entries.select { |entry| entry[:type] == :item }.map { |entry| entry[:command] }
            expected.zip(actual).each { |wanted, found| assert_same wanted, found }
            refute_includes actual, Commands.role_command(:drawer_system)

            role_menu = root.submenu(CommandMessages::MENU_DRAWER).submenu(CommandMessages::MENU_ASSIGN_ROLE)
            menu_commands = role_menu.entries.select { |entry| entry[:type] == :item }.map { |entry| entry[:command] }
            expected.first(4).each { |command| assert_includes menu_commands, command }
            assert_empty @model.operations
          end

          def test_toolbar_commands_have_vietnamese_copy_and_resolved_icons
            expectations = {
              Commands.role_command(:drawer_opening) => [
                'Gán Group hoặc Component đã chọn làm khoang ngăn kéo',
                'Chọn một Group hoặc Component để gán làm khoang ngăn kéo'
              ],
              Commands.role_command(:drawer_slide_left) => [
                'Gán đối tượng đã chọn làm ray trái',
                'Chọn một Group hoặc Component để gán làm ray trái'
              ],
              Commands.role_command(:drawer_slide_right) => [
                'Gán đối tượng đã chọn làm ray phải',
                'Chọn một Group hoặc Component để gán làm ray phải'
              ],
              Commands.role_command(:drawer_box) => [
                'Gán đối tượng đã chọn làm thùng ngăn kéo',
                'Chọn một Group hoặc Component để gán làm thùng ngăn kéo'
              ],
              Commands.edit_specification_command => [
                'Chỉnh sửa kích thước và thông số ray của hệ ngăn kéo',
                'Chọn một đối tượng đã được gán vai trò ngăn kéo để chỉnh sửa'
              ],
              Commands.unassign_command => [
                'Xóa vai trò ngăn kéo khỏi đối tượng đã chọn',
                'Chọn một đối tượng đã được gán vai trò ngăn kéo'
              ]
            }

            expectations.each do |command, (tooltip, status)|
              assert_equal tooltip, command.tooltip
              assert_equal status, command.status_bar_text
              assert File.file?(command.small_icon), command.small_icon.inspect
              assert File.file?(command.large_icon), command.large_icon.inspect
              assert command.small_icon.end_with?('_small.svg')
              assert command.large_icon.end_with?('_large.svg')
            end
          end

          def test_toolbar_validation_is_selection_aware_and_read_only
            opening = Commands.role_command(:drawer_opening)
            edit = Commands.edit_specification_command
            unassign = Commands.unassign_command

            assert_equal MF_GRAYED, opening.validation_state
            assert_equal MF_GRAYED, edit.validation_state
            assert_equal MF_GRAYED, unassign.validation_state

            @model.selection << UnsupportedStub.new
            assert_equal MF_GRAYED, opening.validation_state
            @model.selection.clear

            entity = new_entity
            select_entities(entity)
            assert_equal MF_ENABLED, opening.validation_state
            assert_equal MF_GRAYED, edit.validation_state
            assert_equal MF_GRAYED, unassign.validation_state
            writes = entity.writes.length
            deletes = entity.deletes.length

            assign_direct(entity, :drawer_opening)
            assigned_writes = entity.writes.length
            assigned_deletes = entity.deletes.length
            assert_equal MF_ENABLED, opening.validation_state
            assert_equal MF_ENABLED, edit.validation_state
            assert_equal MF_ENABLED, unassign.validation_state
            assert_equal assigned_writes, entity.writes.length
            assert_equal assigned_deletes, entity.deletes.length
            assert_operator assigned_writes, :>, writes
            assert_operator assigned_deletes, :>=, deletes

            locked = new_entity(locked: true)
            select_entities(locked)
            assert_equal MF_GRAYED, opening.validation_state
            assert_equal MF_GRAYED, edit.validation_state
            assert_equal MF_GRAYED, unassign.validation_state
            assert_empty @model.operations
          end

          def test_menu_registration_is_reload_safe_and_preserves_existing_entries
            reset_registration
            root = UI::Menu.new('SonVu CNC Plugins')
            root.add_item('Mục hiện có')

            Commands.register_menu(root)
            Commands.register_menu(root)

            assert_equal 1, root.entries.count { |entry| entry[:label] == 'Mục hiện có' }
            assert_equal 1, root.entries.count { |entry| entry[:label] == CommandMessages::MENU_DRAWER }
            role_menu = root.submenu(CommandMessages::MENU_DRAWER).submenu(CommandMessages::MENU_ASSIGN_ROLE)
            labels = role_menu.entries.select { |entry| entry[:type] == :item }.map { |entry| entry[:label] }
            assert_equal CommandMessages::COMMAND_LABELS.values + [CommandMessages::COMMAND_UNASSIGN], labels
            drawer_labels = item_labels(root.submenu(CommandMessages::MENU_DRAWER))
            assert_includes drawer_labels, CommandMessages::COMMAND_EDIT_SPECIFICATION
            assert_equal 1, UI.context_handlers.length
          end

          def test_context_menu_visibility_follows_selection_and_assignment
            reset_registration
            Commands.register_context_menu
            entity = new_entity
            select_entities(entity)

            unassigned_menu = UI::Menu.new
            UI.context_handlers.first.call(unassigned_menu)
            unassigned_roles = context_role_menu(unassigned_menu)
            assert_equal 5, item_labels(unassigned_roles).length
            refute_includes item_labels(unassigned_roles), CommandMessages::COMMAND_UNASSIGN
            refute_includes context_drawer_labels(unassigned_menu), CommandMessages::COMMAND_EDIT_SPECIFICATION

            assign_direct(entity, :drawer_opening)
            assigned_menu = UI::Menu.new
            UI.context_handlers.first.call(assigned_menu)
            assert_includes item_labels(context_role_menu(assigned_menu)), CommandMessages::COMMAND_UNASSIGN
            assert_includes context_drawer_labels(assigned_menu), CommandMessages::COMMAND_EDIT_SPECIFICATION

            @model.selection.replace([UnsupportedStub.new])
            unsupported_menu = UI::Menu.new
            UI.context_handlers.first.call(unsupported_menu)
            assert_nil unsupported_menu.submenu(CommandMessages::MENU_DRAWER)

            @model.selection.replace([new_entity, new_entity])
            multiple_menu = UI::Menu.new
            UI.context_handlers.first.call(multiple_menu)
            assert_nil multiple_menu.submenu(CommandMessages::MENU_DRAWER)

            @model.selection.replace([new_entity(valid: false)])
            deleted_menu = UI::Menu.new
            UI.context_handlers.first.call(deleted_menu)
            assert_nil deleted_menu.submenu(CommandMessages::MENU_DRAWER)

            @model.selection.clear
            empty_menu = UI::Menu.new
            UI.context_handlers.first.call(empty_menu)
            assert_nil empty_menu.submenu(CommandMessages::MENU_DRAWER)
          end

          private

          def new_entity(type: :group, valid: true, locked: false, values: {})
            EntityStub.new(
              model: @model,
              type: type,
              valid: valid,
              locked: locked,
              values: values
            )
          end

          def select_entities(*entities)
            @model.selection.replace(entities)
          end

          def existing_system(role)
            entity = new_entity
            assign_direct(entity, role)
          end

          def assign_direct(entity, role, system_id = nil)
            identity = Identity.create(object_type: role.to_s, system_id: system_id)
            Metadata.write(entity, identity)
            identity.drawer_system_id
          end

          def assert_success(result, status)
            assert_equal true, result[:success], result.inspect
            assert_nil result[:error_code]
            assert_equal status, result[:details][:status]
          end

          def assert_failure(result, code)
            assert_equal false, result[:success], result.inspect
            assert_equal code, result[:error_code]
          end

          def assert_operation(name, commits:, aborts:)
            assert_equal [[name, true]], @model.operations
            assert_equal commits, @model.commits
            assert_equal aborts, @model.aborts
          end

          def reset_registration
            Commands.instance_variable_set(:@menu_registered, nil)
            Commands.instance_variable_set(:@context_menu_registered, nil)
            Toolbar.instance_variable_set(:@registered, nil)
            Toolbar.instance_variable_set(:@toolbar, nil)
            UI.reset
          end

          def context_role_menu(menu)
            menu.submenu(CommandMessages::MENU_DRAWER).submenu(CommandMessages::MENU_ASSIGN_ROLE)
          end

          def context_drawer_labels(menu)
            item_labels(menu.submenu(CommandMessages::MENU_DRAWER))
          end

          def item_labels(menu)
            menu.entries.select { |entry| entry[:type] == :item }.map { |entry| entry[:label] }
          end
        end
      end
    end
  end
end
