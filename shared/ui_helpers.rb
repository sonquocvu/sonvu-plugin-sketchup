# frozen_string_literal: true

# Shared UI helpers for SonVu CNC Plugins. Keep common message boxes, dialogs,
# and menu utility methods here so feature modules stay focused on their domain.

module SonVu
  module CNCPlugins
    module UIHelpers
      module_function

      def message(text)
        UI.messagebox(text)
      end
    end
  end
end
