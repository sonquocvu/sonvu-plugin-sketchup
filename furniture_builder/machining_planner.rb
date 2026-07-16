# frozen_string_literal: true

# Pure, machine-independent CNC preparation for Furniture Builder. Phases
# 5A–5B reconstruct panel-local operations and apply saved machining rules but
# never change model geometry or emit machine code.

require_relative 'machining_rules'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module MachiningPlanner
        SUPPORTED_OPERATION_TYPES = %w[hinge_cup].freeze
        REFERENCE_LABELS = {
          'handle' => 'Tay nắm',
          'drawer_slide_left' => 'Ray ngăn kéo',
          'drawer_slide_right' => 'Ray ngăn kéo'
        }.freeze

        module_function

        def plan(settings, cabinet_id: '', cabinet_name: nil, rules: nil)
          raise ArgumentError, 'Không đọc được thông số tủ.' if settings.nil?

          normalized = Specification.normalize(settings)
          normalized_rules = MachiningRules.normalize(rules || {})
          validation_error = Specification.validate(normalized)
          raise ArgumentError, validation_error if validation_error

          parts = Specification.parts(normalized)
          boards = parts.reject { |part| part.kind == 'hardware' }
          hardware = parts.select { |part| part.kind == 'hardware' }
          identity = cabinet_id.to_s.empty? ? normalized[:cabinet_name].to_s : cabinet_id.to_s
          name = cabinet_name.to_s.strip
          name = normalized[:cabinet_name].to_s if name.empty?
          panel_by_key = boards.to_h do |part|
            [part.key.to_s, panel_hash(part, identity, name, normalized[:material_name])]
          end
          references = []
          warnings = []

          hardware.each do |item|
            if item.role == 'hinge_cup'
              attach_hinge_operation(item, panel_by_key, warnings)
            else
              references << reference_hash(item)
            end
          end

          apply_rule_operations(normalized, boards, panel_by_key, normalized_rules, warnings)

          append_reference_warnings(references, warnings)
          panels = panel_by_key.values
          panels.each { |panel| validate_opposing_face_collisions(panel, warnings) }
          panels.each { |panel| panel[:operations].sort_by! { |operation| operation_sort_key(operation) } }
          operations = panels.flat_map { |panel| panel[:operations] }
          invalid_count = operations.count { |operation| operation[:status] != 'ready' }
          warnings << 'Tủ chưa có nguyên công khoan được hỗ trợ.' if operations.empty?

          {
            cabinet_id: identity,
            cabinet_name: name,
            panel_count: panels.length,
            operation_count: operations.length,
            ready_operation_count: operations.length - invalid_count,
            invalid_operation_count: invalid_count,
            reference_count: references.length,
            panels: panels,
            references: references,
            rules: normalized_rules,
            operation_types: operation_type_counts(operations),
            warnings: warnings.uniq
          }
        end

        def project(cabinets, scope: 'Tủ nội thất', rules: nil)
          normalized_rules = MachiningRules.normalize(rules || {})
          warnings = []
          plans = Array(cabinets).filter_map.with_index do |cabinet, index|
            begin
              plan(
                cabinet[:settings],
                cabinet_id: cabinet[:cabinet_id].to_s.empty? ? "tu-#{index + 1}" : cabinet[:cabinet_id],
                cabinet_name: cabinet[:cabinet_name],
                rules: normalized_rules
              )
            rescue ArgumentError => e
              name = cabinet[:cabinet_name].to_s.strip
              name = "Tủ #{index + 1}" if name.empty?
              warnings << "Bỏ qua #{name}: #{e.message}"
              nil
            end
          end
          warnings.concat(plans.flat_map { |item| item[:warnings].map { |warning| "#{item[:cabinet_name]}: #{warning}" } })

          {
            scope: scope.to_s,
            cabinet_count: plans.length,
            panel_count: plans.sum { |item| item[:panel_count] },
            operation_count: plans.sum { |item| item[:operation_count] },
            ready_operation_count: plans.sum { |item| item[:ready_operation_count] },
            invalid_operation_count: plans.sum { |item| item[:invalid_operation_count] },
            reference_count: plans.sum { |item| item[:reference_count] },
            operation_types: merge_operation_type_counts(plans),
            rules: normalized_rules,
            cabinets: plans,
            warnings: warnings.uniq
          }
        end

        def panel_hash(part, cabinet_id, cabinet_name, default_material)
          axes = axes_for(part)
          {
            id: "#{cabinet_id}:#{part.key}",
            key: part.key.to_s,
            name: part.name.to_s,
            role: part.role.to_s,
            kind: part.kind.to_s,
            cabinet_id: cabinet_id,
            cabinet_name: cabinet_name,
            material_name: (part.material_name || default_material).to_s,
            length_mm: rounded(part.finished_length),
            width_mm: rounded(part.finished_width),
            thickness_mm: rounded(part.thickness),
            grain_direction: part.grain_direction.to_s,
            length_axis: axes[:length],
            width_axis: axes[:width],
            thickness_axis: axes[:thickness],
            face_a: axes[:face_a],
            face_b: axes[:face_b],
            source_x_mm: rounded(part.x),
            source_y_mm: rounded(part.y),
            source_z_mm: rounded(part.z),
            operations: []
          }
        end

        def axes_for(part)
          if part.kind == 'front'
            return { length: 'Z', width: 'X', thickness: 'Y', face_a: '-Y', face_b: '+Y' }
          end

          case part.role
          when 'side_left', 'side_right', 'divider'
            { length: 'Z', width: 'Y', thickness: 'X', face_a: '-X', face_b: '+X' }
          when 'drawer_side_left', 'drawer_side_right'
            { length: 'Y', width: 'Z', thickness: 'X', face_a: '-X', face_b: '+X' }
          when 'top', 'bottom', 'shelf', 'drawer_bottom'
            { length: 'X', width: 'Y', thickness: 'Z', face_a: '-Z', face_b: '+Z' }
          else
            { length: 'X', width: 'Z', thickness: 'Y', face_a: '-Y', face_b: '+Y' }
          end
        end

        def attach_hinge_operation(hardware, panel_by_key, warnings)
          owner = panel_by_key[hardware.owner_part_key.to_s]
          unless owner
            warnings << "Không tìm thấy chi tiết chủ quản cho #{hardware.name}."
            return
          end

          diameter = hardware.size_x.to_f
          operation = {
            id: hardware.key.to_s,
            type: 'hinge_cup',
            shape: 'circle',
            label: 'Khoan chén bản lề',
            face: 'B',
            face_label: 'Mặt sau',
            x_mm: rounded((hardware.z + (diameter / 2.0)) - owner[:source_z_mm]),
            y_mm: rounded((hardware.x + (diameter / 2.0)) - owner[:source_x_mm]),
            diameter_mm: rounded(diameter),
            depth_mm: rounded(hardware.size_y),
            source_key: hardware.key.to_s,
            status: 'ready',
            errors: []
          }
          validate_operation(operation, owner)
          owner[:operations] << operation
          warnings.concat(operation[:errors].map { |error| "#{owner[:name]}: #{error}" })
        end

        def apply_rule_operations(settings, boards, panel_by_key, rules, warnings)
          board_by_key = boards.to_h { |part| [part.key.to_s, part] }
          add_connector_operations(board_by_key, panel_by_key, rules, warnings) if rules[:include_connectors]
          add_shelf_pin_operations(board_by_key, panel_by_key, rules, warnings) if rules[:include_shelf_pins]
          if rules[:include_back_grooves] && settings[:include_back]
            add_back_groove_operations(board_by_key, panel_by_key, rules, warnings)
          end
        end

        def add_connector_operations(board_by_key, panel_by_key, rules, warnings)
          joint_parts = board_by_key.values.select { |part| %w[top bottom].include?(part.role) }
          side_parts = board_by_key.values.select { |part| %w[side_left side_right].include?(part.role) }
          side_parts.each do |side|
            panel = panel_by_key[side.key.to_s]
            face = side.role == 'side_left' ? 'B' : 'A'
            joint_parts.each do |joint|
              x = joint.z + (joint.size_z / 2.0) - side.z
              connector_row_positions(panel, rules).each_with_index do |y, index|
                operation = circle_operation(
                  id: "chot_#{side.key}_#{joint.key}_#{index + 1}",
                  type: 'dowel', label: 'Khoan chốt gỗ', face: face,
                  x: x, y: y,
                  diameter: rules[:dowel_diameter_mm], depth: rules[:dowel_depth_mm]
                )
                attach_operation(panel, operation, warnings)
              end
            end
          end

          if rules[:include_cam_pockets]
            joint_parts.each do |joint|
              panel = panel_by_key[joint.key.to_s]
              face = joint.role == 'top' ? 'A' : 'B'
              x_positions = [rules[:cam_edge_offset_mm], panel[:length_mm] - rules[:cam_edge_offset_mm]]
              connector_row_positions(panel, rules).each_with_index do |y, row_index|
                x_positions.each_with_index do |x, column_index|
                  operation = circle_operation(
                    id: "cam_#{joint.key}_#{row_index + 1}_#{column_index + 1}",
                    type: 'cam_pocket', label: 'Khoan ổ cam', face: face,
                    x: x, y: y,
                    diameter: rules[:cam_diameter_mm], depth: rules[:cam_depth_mm]
                  )
                  attach_operation(panel, operation, warnings)
                end
              end
            end
          end
          warnings << 'Các lỗ khoan cạnh đối ứng của nóc và đáy sẽ được bổ sung ở bước xuất theo máy.'
        end

        def connector_row_positions(panel, rules)
          [
            rules[:connector_front_offset_mm],
            panel[:width_mm] - rules[:connector_rear_offset_mm]
          ].map { |value| rounded(value) }.uniq
        end

        def add_shelf_pin_operations(board_by_key, panel_by_key, rules, warnings)
          verticals = board_by_key.values.select do |part|
            %w[side_left side_right divider].include?(part.role)
          end
          verticals.each do |part|
            panel = panel_by_key[part.key.to_s]
            faces = case part.role
                    when 'side_left' then ['B']
                    when 'side_right' then ['A']
                    else %w[A B]
                    end
            y_positions = [
              rules[:shelf_pin_front_offset_mm],
              panel[:width_mm] - rules[:shelf_pin_rear_offset_mm]
            ].map { |value| rounded(value) }.uniq
            x_positions = distributed_shelf_pin_positions(panel[:length_mm], rules)
            faces.each do |face|
              x_positions.each_with_index do |x, x_index|
                y_positions.each_with_index do |y, y_index|
                  operation = circle_operation(
                    id: "lo_dot_#{part.key}_#{face}_#{x_index + 1}_#{y_index + 1}",
                    type: 'shelf_pin', label: 'Khoan hàng lỗ đợt', face: face,
                    x: x, y: y,
                    diameter: rules[:shelf_pin_diameter_mm], depth: rules[:shelf_pin_depth_mm]
                  )
                  attach_operation(panel, operation, warnings)
                end
              end
            end
          end
        end

        def distributed_shelf_pin_positions(length, rules)
          first = rules[:shelf_pin_bottom_margin_mm].to_f
          last = length.to_f - rules[:shelf_pin_top_margin_mm].to_f
          return [] if first > last

          positions = []
          cursor = first
          while cursor <= last + 0.001
            positions << rounded(cursor)
            cursor += rules[:shelf_pin_pitch_mm].to_f
          end
          positions
        end

        def add_back_groove_operations(board_by_key, panel_by_key, rules, warnings)
          grooved = board_by_key.values.select do |part|
            %w[side_left side_right top bottom].include?(part.role)
          end
          grooved.each do |part|
            panel = panel_by_key[part.key.to_s]
            face = case part.role
                   when 'side_left', 'bottom' then 'B'
                   else 'A'
                   end
            groove_width = rules[:back_groove_width_mm]
            y = panel[:width_mm] - rules[:back_groove_rear_offset_mm] - groove_width
            operation = {
              id: "ranh_hau_#{part.key}",
              type: 'back_groove',
              shape: 'groove',
              label: 'Phay rãnh hậu',
              face: face,
              face_label: face == 'A' ? 'Mặt A' : 'Mặt B',
              x_mm: 0.0,
              y_mm: rounded(y),
              length_mm: panel[:length_mm],
              width_mm: rounded(groove_width),
              depth_mm: rounded(rules[:back_groove_depth_mm]),
              status: 'ready',
              errors: []
            }
            attach_operation(panel, operation, warnings)
          end
        end

        def circle_operation(id:, type:, label:, face:, x:, y:, diameter:, depth:)
          {
            id: id,
            type: type,
            shape: 'circle',
            label: label,
            face: face,
            face_label: face == 'A' ? 'Mặt A' : 'Mặt B',
            x_mm: rounded(x),
            y_mm: rounded(y),
            diameter_mm: rounded(diameter),
            depth_mm: rounded(depth),
            status: 'ready',
            errors: []
          }
        end

        def attach_operation(panel, operation, warnings)
          validate_operation(operation, panel)
          panel[:operations] << operation
          warnings.concat(operation[:errors].map { |error| "#{panel[:name]}: #{error}" })
          operation
        end

        def validate_operation(operation, panel)
          errors = []
          errors << 'Chiều sâu khoan phải lớn hơn 0.' unless operation[:depth_mm].to_f.positive?
          if operation[:depth_mm].to_f > panel[:thickness_mm].to_f
            errors << 'Chiều sâu khoan vượt quá độ dày chi tiết.'
          end
          if operation[:shape] == 'groove'
            errors << 'Chiều dài và chiều rộng rãnh phải lớn hơn 0.' unless operation[:length_mm].to_f.positive? && operation[:width_mm].to_f.positive?
            unless within_rectangle?(operation[:x_mm], operation[:length_mm], panel[:length_mm])
              errors << 'Rãnh vượt giới hạn chiều dài chi tiết.'
            end
            unless within_rectangle?(operation[:y_mm], operation[:width_mm], panel[:width_mm])
              errors << 'Rãnh vượt giới hạn chiều rộng chi tiết.'
            end
          else
            radius = operation[:diameter_mm].to_f / 2.0
            errors << 'Đường kính khoan phải lớn hơn 0.' unless radius.positive?
            unless within_circle?(operation[:x_mm], radius, panel[:length_mm])
              errors << 'Tâm khoan vượt giới hạn chiều dài chi tiết.'
            end
            unless within_circle?(operation[:y_mm], radius, panel[:width_mm])
              errors << 'Tâm khoan vượt giới hạn chiều rộng chi tiết.'
            end
          end
          operation[:errors] = errors
          operation[:status] = errors.empty? ? 'ready' : 'invalid'
          operation
        end

        def within_circle?(center, radius, span)
          center.to_f - radius >= -0.001 && center.to_f + radius <= span.to_f + 0.001
        end

        def within_rectangle?(origin, size, span)
          origin.to_f >= -0.001 && origin.to_f + size.to_f <= span.to_f + 0.001
        end

        def operation_sort_key(operation)
          [operation[:face].to_s, operation[:type].to_s, operation[:x_mm].to_f, operation[:y_mm].to_f]
        end

        def validate_opposing_face_collisions(panel, warnings)
          face_a = panel[:operations].select { |operation| operation[:face] == 'A' && operation[:shape] == 'circle' }
          face_b = panel[:operations].select { |operation| operation[:face] == 'B' && operation[:shape] == 'circle' }
          face_a.product(face_b).each do |first, second|
            next unless circles_overlap?(first, second)
            next unless first[:depth_mm].to_f + second[:depth_mm].to_f > panel[:thickness_mm].to_f + 0.001

            message = 'Lỗ từ hai mặt đối diện giao nhau trong chiều dày chi tiết.'
            [first, second].each do |operation|
              operation[:errors] << message unless operation[:errors].include?(message)
              operation[:status] = 'invalid'
            end
            warnings << "#{panel[:name]}: #{message}"
          end
        end

        def circles_overlap?(first, second)
          dx = first[:x_mm].to_f - second[:x_mm].to_f
          dy = first[:y_mm].to_f - second[:y_mm].to_f
          distance_squared = (dx * dx) + (dy * dy)
          radii = (first[:diameter_mm].to_f + second[:diameter_mm].to_f) / 2.0
          distance_squared < (radii * radii) - 0.001
        end

        def operation_type_counts(operations)
          operations.group_by { |operation| operation[:type] }.transform_values(&:length)
        end

        def merge_operation_type_counts(plans)
          plans.each_with_object(Hash.new(0)) do |plan, totals|
            plan[:operation_types].each { |type, count| totals[type] += count }
          end.to_h
        end

        def reference_hash(item)
          {
            key: item.key.to_s,
            type: item.role.to_s,
            label: REFERENCE_LABELS.fetch(item.role.to_s, 'Phụ kiện'),
            owner_part_key: item.owner_part_key.to_s
          }
        end

        def append_reference_warnings(references, warnings)
          references.group_by { |item| reference_family(item[:type]) }.each do |type, items|
            label = type == 'drawer_slide' ? 'ray ngăn kéo' : REFERENCE_LABELS.fetch(type, 'Phụ kiện').downcase
            warnings << "#{items.length} #{label} chỉ là tham chiếu bố trí; cần mẫu khoan của nhà sản xuất."
          end
        end

        def reference_family(type)
          type.to_s.start_with?('drawer_slide_') ? 'drawer_slide' : type.to_s
        end

        def rounded(value)
          value.to_f.round(3)
        end
      end
    end
  end
end
