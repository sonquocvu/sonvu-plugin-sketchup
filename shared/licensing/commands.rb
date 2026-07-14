# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module Licensing
      module Commands
        module_function

        def register_menu(root_menu)
          return if @menu_registered

          root_menu.add_item(license_manager_command)
          root_menu.add_separator
          @menu_registered = true
        end

        def license_manager_command
          @license_manager_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_LICENSE_MANAGER) { Dialog.show }
            command.tooltip = 'Quản lý giấy phép SonVu CNC Plugins'
            command.status_bar_text = 'Kích hoạt, làm mới hoặc hủy kích hoạt giấy phép.'
            command
          end
        end
      end
    end
  end
end
