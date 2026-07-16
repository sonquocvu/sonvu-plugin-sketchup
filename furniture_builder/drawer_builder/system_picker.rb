# frozen_string_literal: true

if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/system_registry'
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/command_messages'
else
  require_relative 'system_registry'
  require_relative 'command_messages'
end

# Native SketchUp picker for joining an existing drawer system. Display labels
# are temporary and map back to stable UUIDs without persisting display indexes.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SystemPicker
          STATE_LABELS = {
            opening_only: 'chỉ có khoang',
            slides_only: 'chỉ có ray',
            opening_and_slides: 'có khoang và ray',
            opening_and_box: 'có khoang và thùng ngăn kéo',
            box_only: 'chỉ có thùng ngăn kéo',
            complete: 'hoàn chỉnh',
            custom_partial: 'chưa hoàn chỉnh'
          }.freeze

          module_function

          def systems(scope)
            ids = []
            seen = {}
            SystemRegistry.searchable_entities(scope).each do |entity|
              system_id = Metadata.read(entity)[:drawer_system_id]
              next unless Identity.valid_system_id?(system_id)
              next if seen[system_id]

              seen[system_id] = true
              ids << system_id
            end

            ids.each_with_index.map do |system_id, index|
              state = SystemRegistry.system_state(scope, system_id)
              {
                drawer_system_id: system_id,
                state: state,
                roles: SystemRegistry.roles_for_system(scope, system_id),
                label: system_label(index + 1, state)
              }
            end
          end

          def choose(scope, ui: nil)
            ui ||= ::UI
            options = systems(scope)
            return choose_new_system(options, ui) if options.empty?
            return confirm_single_system(options, ui) if options.length == 1

            choose_multiple_systems(options, ui)
          end

          def system_label(index, state)
            description = STATE_LABELS.fetch(state.to_sym, STATE_LABELS[:custom_partial])
            "Hệ ngăn kéo #{index} — #{description}"
          end

          def choose_new_system(options, ui)
            if confirmed?(ui, CommandMessages::NO_SYSTEM_CONFIRMATION)
              choice_result(:create_new, systems: options)
            else
              choice_result(:cancelled, systems: options)
            end
          end

          def confirm_single_system(options, ui)
            option = options.first
            if confirmed?(ui, CommandMessages::ONE_SYSTEM_CONFIRMATION)
              choice_result(
                :selected,
                drawer_system_id: option[:drawer_system_id],
                label: option[:label],
                systems: options
              )
            else
              choice_result(:cancelled, systems: options)
            end
          end

          def choose_multiple_systems(options, ui)
            labels = options.map { |option| option[:label] }
            input = ui.inputbox(
              ['Chọn hệ ngăn kéo:'],
              [labels.first],
              [labels.join('|')],
              'Chọn hệ ngăn kéo'
            )
            return choice_result(:cancelled, systems: options) unless input

            selected_label = input[0].to_s
            selected = options.find { |option| option[:label] == selected_label }
            return choice_result(:cancelled, systems: options) unless selected

            choice_result(
              :selected,
              drawer_system_id: selected[:drawer_system_id],
              label: selected[:label],
              systems: options
            )
          end

          def confirmed?(ui, message)
            result = ui.messagebox(message, yes_no_flag)
            result == yes_result
          end

          def yes_no_flag
            defined?(::MB_YESNO) ? ::MB_YESNO : 4
          end

          def yes_result
            defined?(::IDYES) ? ::IDYES : 6
          end

          def choice_result(status, drawer_system_id: nil, label: nil, systems: [])
            {
              status: status,
              drawer_system_id: drawer_system_id,
              label: label,
              systems: systems
            }
          end
        end
      end
    end
  end
end
