# frozen_string_literal: true

require_relative '../../shared/units'
require_relative 'slide_configurations'
require_relative 'calculator'
require_relative 'system_registry'
require_relative 'opening_geometry'

# Read-only conversion of drawer-system data into a safe Vietnamese UI payload.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SpecificationEditorPresenter
          ROLE_LABELS = {
            drawer_opening: 'Khoang ngăn kéo',
            drawer_slide_left: 'Ray trái',
            drawer_slide_right: 'Ray phải',
            drawer_box: 'Thùng ngăn kéo',
            drawer_system: 'Hệ ngăn kéo'
          }.freeze

          SOURCE_LABELS = {
            'plugin_generated' => 'Do plugin tạo',
            'user_assigned' => 'Người dùng gán',
            'legacy_adapter' => 'Dữ liệu tương thích cũ'
          }.freeze

          module_function

          def present(scope:, drawer_system_id:, selected_entity:, specification: nil)
            selected = Metadata.read(selected_entity)
            roles = SystemRegistry.roles_for_system(scope, drawer_system_id)
            opening_entity = SystemRegistry.entity_for_role(
              scope,
              drawer_system_id,
              :drawer_opening
            )
            unit_system = specification ? specification.unit_system : Specification::DEFAULT_UNIT_SYSTEM
            {
              title: 'Thông số ngăn kéo',
              source_label: SOURCE_LABELS.fetch(selected[:drawer_source].to_s, 'Chưa xác định'),
              selected_role_label: ROLE_LABELS.fetch(selected[:drawer_object_type].to_s.to_sym, 'Vai trò ngăn kéo'),
              system_state: SystemRegistry.system_state(scope, drawer_system_id),
              role_summary: role_summary(roles),
              slide_options: SlideConfigurations.options.map do |identifier, label|
                { value: identifier, label: label }
              end,
              preset_options: [
                { value: '', label: 'Không dùng mẫu ray' },
                {
                  value: SlideConfigurations::LEGACY_PRESET_KEY,
                  label: SlideConfigurations::LEGACY_PRESET_NAME
                }
              ],
              opening: opening_payload(
                specification&.opening,
                selected[:drawer_object_type],
                unit_system,
                model_depth: OpeningGeometry.depth(opening_entity)
              ),
              slides: slides_payload(specification&.slides, selected[:drawer_object_type], unit_system),
              box: box_payload(specification&.box, selected[:drawer_object_type], unit_system)
            }
          end

          def opening_payload(
            values,
            selected_role,
            unit_system = Specification::DEFAULT_UNIT_SYSTEM,
            model_depth: nil
          )
            section = values || {}
            displayed_depth = display_length(section[:opening_depth], unit_system)
            if displayed_depth.nil?
              displayed_depth = display_length(model_depth, Specification::DEFAULT_UNIT_SYSTEM)
            end
            {
              enabled: !values.nil? || %w[drawer_opening drawer_system].include?(selected_role.to_s),
              opening_width: display_length(section[:opening_width], unit_system),
              opening_height: display_length(section[:opening_height], unit_system),
              opening_depth: displayed_depth
            }
          end

          def slides_payload(values, selected_role, unit_system = Specification::DEFAULT_UNIT_SYSTEM)
            section = values || {}
            strategy = section[:calculation_strategy].to_s
            supported = Calculator::SUPPORTED_STRATEGIES.include?(strategy)
            {
              enabled: !values.nil? || %w[drawer_slide_left drawer_slide_right drawer_system].include?(selected_role.to_s),
              slide_type: section[:slide_type].to_s,
              preset_name: preset_value(section),
              manufacturer: section[:manufacturer].to_s,
              left_clearance: display_length(section[:left_clearance], unit_system),
              right_clearance: display_length(section[:right_clearance], unit_system),
              top_clearance: display_length(section[:top_clearance], unit_system),
              bottom_clearance: display_length(section[:bottom_clearance], unit_system),
              front_setback: display_length(section[:front_setback], unit_system),
              rear_clearance: display_length(section[:rear_clearance], unit_system),
              slide_thickness: display_length(section[:slide_thickness], unit_system),
              slide_height: display_length(section[:slide_height], unit_system),
              slide_length: display_length(section[:slide_length], unit_system),
              minimum_drawer_depth: display_length(section[:minimum_drawer_depth], unit_system),
              maximum_drawer_depth: display_length(section[:maximum_drawer_depth], unit_system),
              automatic_supported: values.nil? || supported,
              unsupported_message: values && !supported ?
                'Chưa có công thức tính tự động cho loại ray này.' : nil,
              clearances_editable: true
            }
          end

          def box_payload(values, selected_role, unit_system = Specification::DEFAULT_UNIT_SYSTEM)
            section = values || {}
            mode = section[:dimension_mode].to_s
            mode = 'calculated' unless %w[calculated manual].include?(mode)
            {
              enabled: !values.nil? || %w[drawer_box drawer_system].include?(selected_role.to_s),
              dimension_mode: mode,
              dimension_mode_label: mode == 'manual' ? 'Nhập kích thước thủ công' : 'Tự động tính theo khoang và ray',
              dimension_indicator: mode == 'manual' ? 'Nhập thủ công' : 'Tự động tính',
              box_width: display_length(section[:box_width], unit_system),
              box_height: display_length(section[:box_height], unit_system),
              box_depth: display_length(section[:box_depth], unit_system),
              board_thickness: display_length(section[:board_thickness], unit_system),
              bottom_thickness: display_length(section[:bottom_thickness], unit_system),
              front_thickness: display_length(section[:front_thickness], unit_system),
              back_thickness: display_length(section[:back_thickness], unit_system)
            }
          end

          def preset_value(section)
            if SlideConfigurations.legacy_preset?(section[:slide_type].to_s, section[:preset_name])
              SlideConfigurations::LEGACY_PRESET_KEY
            else
              section[:preset_name].to_s
            end
          end

          def role_summary(roles)
            labels = roles.map { |role| ROLE_LABELS[role] }.compact
            if roles == [:drawer_box]
              'Hệ hiện có: Chỉ có thùng ngăn kéo'
            elsif labels.empty?
              'Hệ hiện có: Chưa có thành phần'
            else
              "Hệ hiện có: #{labels.join(', ')}"
            end
          end

          def display_length(value, unit_system = Specification::DEFAULT_UNIT_SYSTEM)
            return nil if value.nil?

            number = if unit_system.to_s == 'millimeters'
                       value.to_f
                     else
                       CNCPlugins::Units.model_units_to_millimeters(value)
                     end
            rounded = number.to_f.round(4)
            rounded == rounded.to_i ? rounded.to_i : rounded
          end
        end
      end
    end
  end
end
