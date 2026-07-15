# frozen_string_literal: true

# Pure furniture layout calculations. Keeping this file independent from the
# SketchUp API makes the cabinet rules deterministic and easy to regression-test.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Specification
        Part = Struct.new(
          :key,
          :name,
          :role,
          :x,
          :y,
          :z,
          :size_x,
          :size_y,
          :size_z,
          :finished_length,
          :finished_width,
          :thickness,
          :grain_direction,
          :grain_axis,
          :edge_banding,
          :kind,
          :material_name,
          :assembly_index,
          :owner_part_key,
          :shape,
          keyword_init: true
        )

        REQUIRED_NUMERIC_KEYS = %i[
          width_mm
          height_mm
          depth_mm
          panel_thickness_mm
          back_thickness_mm
          plinth_height_mm
          plinth_setback_mm
          front_thickness_mm
          front_gap_mm
          top_drawer_height_mm
          drawer_side_clearance_mm
          drawer_box_depth_mm
          drawer_box_height_mm
          drawer_panel_thickness_mm
          drawer_bottom_thickness_mm
          drawer_front_setback_mm
          drawer_rear_clearance_mm
          handle_length_mm
          handle_width_mm
          handle_projection_mm
          handle_edge_offset_mm
          hinge_cup_diameter_mm
          hinge_cup_depth_mm
          hinge_edge_offset_mm
          hinge_end_offset_mm
          drawer_slide_length_mm
          drawer_slide_height_mm
          drawer_slide_thickness_mm
        ].freeze
        REQUIRED_INTEGER_KEYS = %i[shelf_count divider_count].freeze
        HARDWARE_INTEGER_KEYS = %i[hinge_count].freeze
        MAX_REPEAT_COUNT = 50
        MAX_HINGE_COUNT = 10
        HINGE_FRONT_ROLES = %w[door door_left door_right flap_front].freeze

        module_function

        def defaults(preset_key = Presets::DEFAULT_KEY)
          Presets.fetch(preset_key).merge(preset_key: preset_key.to_s)
        end

        def normalize(values)
          preset_key = value_for(values, :preset_key).to_s
          preset_key = Presets::DEFAULT_KEY unless Presets.valid_key?(preset_key)
          base = defaults(preset_key)
          base = base.merge(Presets::DEFAULT_FRONT_SETTINGS) unless front_settings_present?(values)
          base = base.merge(Presets::DEFAULT_DRAWER_SETTINGS) unless drawer_settings_present?(values)
          base = base.merge(Presets::DEFAULT_HARDWARE_SETTINGS) unless hardware_settings_present?(values)

          normalized = base.merge(
            preset_key: preset_key,
            cabinet_name: string_value(value_for(values, :cabinet_name), base[:cabinet_name]),
            material_name: string_value(value_for(values, :material_name), base[:material_name]),
            grain_mode: string_value(value_for(values, :grain_mode), base[:grain_mode]),
            front_layout: string_value(value_for(values, :front_layout), base[:front_layout]),
            front_cover_mode: string_value(value_for(values, :front_cover_mode), base[:front_cover_mode]),
            front_material_name: string_value(value_for(values, :front_material_name), base[:front_material_name]),
            front_grain_mode: string_value(value_for(values, :front_grain_mode), base[:front_grain_mode]),
            drawer_material_name: string_value(
              value_for(values, :drawer_material_name),
              base[:drawer_material_name]
            ),
            hardware_material_name: string_value(
              value_for(values, :hardware_material_name),
              base[:hardware_material_name]
            ),
            include_back: boolean_value(value_for(values, :include_back), base[:include_back]),
            edge_band_front: boolean_value(value_for(values, :edge_band_front), base[:edge_band_front]),
            front_edge_band_all: boolean_value(
              value_for(values, :front_edge_band_all),
              base[:front_edge_band_all]
            ),
            include_drawer_boxes: boolean_value(
              value_for(values, :include_drawer_boxes),
              base[:include_drawer_boxes]
            ),
            include_handles: boolean_value(
              value_for(values, :include_handles),
              base[:include_handles]
            ),
            include_hinges: boolean_value(
              value_for(values, :include_hinges),
              base[:include_hinges]
            ),
            include_drawer_slides: boolean_value(
              value_for(values, :include_drawer_slides),
              base[:include_drawer_slides]
            )
          )

          REQUIRED_NUMERIC_KEYS.each do |key|
            normalized[key] = numeric_value(value_for(values, key), base[key])
          end
          REQUIRED_INTEGER_KEYS.each do |key|
            normalized[key] = integer_value(value_for(values, key), base[key])
          end
          HARDWARE_INTEGER_KEYS.each do |key|
            normalized[key] = integer_value(value_for(values, key), base[key])
          end
          normalized
        end

        def validate(values)
          settings = normalize(values)
          return 'Tên tủ không được để trống.' if settings[:cabinet_name].empty?
          return 'Tên vật liệu không được để trống.' if settings[:material_name].empty?
          return 'Loại tủ không hợp lệ.' unless Presets.valid_key?(settings[:preset_key])
          return 'Hướng vân không hợp lệ.' unless Presets::GRAIN_OPTIONS.include?(settings[:grain_mode])
          return 'Kiểu mặt cánh không hợp lệ.' unless Presets::FRONT_LAYOUTS.key?(settings[:front_layout])
          return 'Kiểu phủ mặt cánh không hợp lệ.' unless Presets::COVER_OPTIONS.include?(settings[:front_cover_mode])
          return 'Hướng vân mặt cánh không hợp lệ.' unless Presets::GRAIN_OPTIONS.include?(settings[:front_grain_mode])
          return 'Vui lòng nhập số hợp lệ cho tất cả kích thước.' if REQUIRED_NUMERIC_KEYS.any? { |key| settings[key].nil? }
          return 'Vui lòng nhập số nguyên hợp lệ cho số hàng đợt và số vách đứng.' if REQUIRED_INTEGER_KEYS.any? { |key| settings[key].nil? }
          return 'Số bản lề phải là số nguyên hợp lệ.' if HARDWARE_INTEGER_KEYS.any? { |key| settings[key].nil? }

          %i[width_mm height_mm depth_mm panel_thickness_mm].each do |key|
            return 'Kích thước tủ và độ dày ván phải lớn hơn 0.' unless settings[key]&.positive?
          end
          return 'Độ dày hậu phải lớn hơn 0 khi bật tấm hậu.' if settings[:include_back] && !settings[:back_thickness_mm].positive?
          return 'Độ dày hậu không được âm.' if settings[:back_thickness_mm].negative?
          return 'Chiều cao chân tủ và độ lùi chân tủ không được âm.' if settings[:plinth_height_mm].negative? || settings[:plinth_setback_mm].negative?
          return "Số hàng đợt và số vách đứng không được vượt quá #{MAX_REPEAT_COUNT}." if repeat_count_invalid?(settings)

          thickness = settings[:panel_thickness_mm]
          return 'Chiều rộng tủ phải lớn hơn hai lần độ dày ván.' unless settings[:width_mm] > (2 * thickness)
          return 'Chiều cao tủ không đủ cho tấm nóc, tấm đáy và khoảng chân tủ.' unless settings[:height_mm] > (settings[:plinth_height_mm] + (2 * thickness))

          usable_depth = settings[:depth_mm] - (settings[:include_back] ? settings[:back_thickness_mm] : 0)
          return 'Chiều sâu tủ phải lớn hơn độ dày tấm hậu.' unless usable_depth.positive?
          return 'Độ lùi chân tủ phải nhỏ hơn chiều sâu sử dụng của tủ.' if settings[:plinth_height_mm].positive? && settings[:plinth_setback_mm] >= (usable_depth - thickness)

          internal_width = settings[:width_mm] - (2 * thickness)
          if settings[:divider_count].positive? && internal_width <= (settings[:divider_count] * thickness)
            return 'Chiều rộng trong tủ không đủ để bố trí số vách đứng đã nhập.'
          end

          internal_height = settings[:height_mm] - settings[:plinth_height_mm] - (2 * thickness)
          if settings[:shelf_count].positive? && internal_height <= (settings[:shelf_count] * thickness)
            return 'Chiều cao trong tủ không đủ để bố trí số hàng đợt đã nhập.'
          end

          front_error = validate_fronts(settings)
          return front_error if front_error
          drawer_error = validate_drawer_boxes(settings)
          return drawer_error if drawer_error
          hardware_error = validate_hardware(settings)
          return hardware_error if hardware_error

          nil
        end

        def parts(values)
          settings = normalize(values)
          error = validate(settings)
          raise ArgumentError, error if error

          parts = carcass_parts(settings)
          divider_specs = divider_parts(settings)
          parts.concat(divider_specs)
          parts.concat(shelf_parts(settings, divider_specs))
          parts << back_part(settings) if settings[:include_back]
          parts << plinth_part(settings) if settings[:plinth_height_mm].positive?
          parts.concat(front_parts(settings))
          parts.concat(drawer_box_parts(settings))
          parts.concat(hardware_parts(settings))
          parts
        end

        def drawer_box_parts(settings)
          return [] unless settings[:include_drawer_boxes]

          drawer_fronts = front_parts(settings).select { |front| front.role == 'drawer_front' }
          outer_width = drawer_outer_width(settings)
          depth = resolved_drawer_depth(settings)
          height = settings[:drawer_box_height_mm]
          x = settings[:panel_thickness_mm] + settings[:drawer_side_clearance_mm]
          y = settings[:drawer_front_setback_mm]

          drawer_fronts.each_with_index.flat_map do |front, index|
            drawer_index = index + 1
            z = front.z + ((front.size_z - height) / 2.0)
            drawer_box_panel_parts(
              settings,
              drawer_index: drawer_index,
              x: x,
              y: y,
              z: z,
              width: outer_width,
              depth: depth,
              height: height
            )
          end
        end

        def drawer_box_panel_parts(settings, drawer_index:, x:, y:, z:, width:, depth:, height:)
          panel = settings[:drawer_panel_thickness_mm]
          bottom = settings[:drawer_bottom_thickness_mm]
          inner_width = width - (2 * panel)
          inner_depth = depth - (2 * panel)
          prefix = "Ngăn kéo #{drawer_index}"
          key_prefix = "hoc_#{drawer_index}"

          [
            drawer_panel(
              settings, drawer_index, key: "#{key_prefix}_hong_trai", name: "#{prefix} - Hông trái",
              role: 'drawer_side_left', x: x, y: y, z: z,
              size_x: panel, size_y: depth, size_z: height,
              length: depth, width: height, thickness: panel
            ),
            drawer_panel(
              settings, drawer_index, key: "#{key_prefix}_hong_phai", name: "#{prefix} - Hông phải",
              role: 'drawer_side_right', x: x + width - panel, y: y, z: z,
              size_x: panel, size_y: depth, size_z: height,
              length: depth, width: height, thickness: panel
            ),
            drawer_panel(
              settings, drawer_index, key: "#{key_prefix}_truoc", name: "#{prefix} - Thành trước",
              role: 'drawer_inner_front', x: x + panel, y: y, z: z,
              size_x: inner_width, size_y: panel, size_z: height,
              length: inner_width, width: height, thickness: panel
            ),
            drawer_panel(
              settings, drawer_index, key: "#{key_prefix}_sau", name: "#{prefix} - Thành sau",
              role: 'drawer_back', x: x + panel, y: y + depth - panel, z: z,
              size_x: inner_width, size_y: panel, size_z: height,
              length: inner_width, width: height, thickness: panel
            ),
            drawer_panel(
              settings, drawer_index, key: "#{key_prefix}_day", name: "#{prefix} - Đáy",
              role: 'drawer_bottom', x: x + panel, y: y + panel, z: z,
              size_x: inner_width, size_y: inner_depth, size_z: bottom,
              length: inner_width, width: inner_depth, thickness: bottom
            )
          ]
        end

        def drawer_panel(settings, drawer_index, key:, name:, role:, x:, y:, z:, size_x:, size_y:, size_z:, length:, width:, thickness:)
          part(
            key: key,
            name: name,
            role: role,
            x: x,
            y: y,
            z: z,
            size_x: size_x,
            size_y: size_y,
            size_z: size_z,
            length: length,
            width: width,
            thickness: thickness,
            grain: 'ngang',
            edge_front: false,
            kind: 'drawer_box',
            material_name: settings[:drawer_material_name],
            assembly_index: drawer_index
          )
        end

        def hardware_parts(settings)
          fronts = front_parts(settings)
          parts = []
          parts.concat(handle_parts(settings, fronts)) if settings[:include_handles]
          parts.concat(hinge_parts(settings, fronts)) if settings[:include_hinges]
          parts.concat(drawer_slide_parts(settings, fronts)) if settings[:include_drawer_slides]
          parts
        end

        def handle_parts(settings, fronts)
          fronts.map do |front|
            vertical = HINGE_FRONT_ROLES.include?(front.role) && front.role != 'flap_front'
            if vertical
              handle_vertical_part(settings, front)
            else
              handle_horizontal_part(settings, front)
            end
          end
        end

        def handle_vertical_part(settings, front)
          width = settings[:handle_width_mm]
          length = settings[:handle_length_mm]
          offset = settings[:handle_edge_offset_mm]
          from_left = front.role == 'door_right'
          center_x = from_left ? front.x + offset : front.x + front.size_x - offset
          hardware_part(
            settings,
            key: "tay_nam_#{front.key}",
            name: "Tay nắm - #{front.name}",
            role: 'handle',
            x: center_x - (width / 2.0),
            y: front.y - settings[:handle_projection_mm],
            z: front.z + ((front.size_z - length) / 2.0),
            size_x: width,
            size_y: settings[:handle_projection_mm],
            size_z: length,
            length: length,
            width: width,
            thickness: settings[:handle_projection_mm],
            assembly_index: front.assembly_index,
            owner_part_key: front.key
          )
        end

        def handle_horizontal_part(settings, front)
          length = settings[:handle_length_mm]
          width = settings[:handle_width_mm]
          hardware_part(
            settings,
            key: "tay_nam_#{front.key}",
            name: "Tay nắm - #{front.name}",
            role: 'handle',
            x: front.x + ((front.size_x - length) / 2.0),
            y: front.y - settings[:handle_projection_mm],
            z: front.z + ((front.size_z - width) / 2.0),
            size_x: length,
            size_y: settings[:handle_projection_mm],
            size_z: width,
            length: length,
            width: width,
            thickness: settings[:handle_projection_mm],
            assembly_index: front.assembly_index,
            owner_part_key: front.key
          )
        end

        def hinge_parts(settings, fronts)
          fronts.select { |front| HINGE_FRONT_ROLES.include?(front.role) }.flat_map do |front|
            count = resolved_hinge_count(settings, front)
            positions = distributed_hinge_positions(settings, front, count)
            positions.each_with_index.map do |position, index|
              hinge_part(settings, front, position, index + 1)
            end
          end
        end

        def distributed_hinge_positions(settings, front, count)
          offset = settings[:hinge_end_offset_mm]
          span = front.role == 'flap_front' ? front.size_x : front.size_z
          distributed_positions(offset, span - offset, count)
        end

        def distributed_positions(first, last, count)
          return [first] if count == 1

          step = (last - first) / (count - 1).to_f
          count.times.map { |index| first + (step * index) }
        end

        def hinge_part(settings, front, position, number)
          diameter = settings[:hinge_cup_diameter_mm]
          depth = settings[:hinge_cup_depth_mm]
          radius = diameter / 2.0
          rear_y = front.y + front.size_y
          if front.role == 'flap_front'
            x = front.x + position - radius
            z = front.z + settings[:hinge_edge_offset_mm] - radius
          else
            center_x = if front.role == 'door_right'
                         front.x + front.size_x - settings[:hinge_edge_offset_mm]
                       else
                         front.x + settings[:hinge_edge_offset_mm]
                       end
            x = center_x - radius
            z = front.z + position - radius
          end
          hardware_part(
            settings,
            key: "ban_le_#{front.key}_#{number}",
            name: "Bản lề #{number} - #{front.name}",
            role: 'hinge_cup',
            x: x,
            y: rear_y - depth,
            z: z,
            size_x: diameter,
            size_y: depth,
            size_z: diameter,
            length: diameter,
            width: diameter,
            thickness: depth,
            assembly_index: front.assembly_index,
            owner_part_key: front.key,
            shape: 'cylinder_y'
          )
        end

        def drawer_slide_parts(settings, fronts)
          drawer_fronts = fronts.select { |front| front.role == 'drawer_front' }
          box_sides = drawer_box_parts(settings).select { |part| part.role == 'drawer_side_left' }
          box_sides.flat_map do |side|
            front = drawer_fronts.find { |item| item.assembly_index == side.assembly_index }
            drawer_slide_pair(settings, side, front)
          end
        end

        def drawer_slide_pair(settings, side, front)
          index = side.assembly_index
          thickness = settings[:drawer_slide_thickness_mm]
          height = settings[:drawer_slide_height_mm]
          length = resolved_drawer_slide_length(settings, side.size_y)
          z = side.z + ((side.size_z - height) / 2.0)
          owner_key = front&.key
          [
            hardware_part(
              settings,
              key: "ray_ngan_keo_#{index}_trai",
              name: "Ray ngăn kéo #{index} - Trái",
              role: 'drawer_slide_left',
              x: settings[:panel_thickness_mm], y: side.y, z: z,
              size_x: thickness, size_y: length, size_z: height,
              length: length, width: height, thickness: thickness,
              assembly_index: index, owner_part_key: owner_key
            ),
            hardware_part(
              settings,
              key: "ray_ngan_keo_#{index}_phai",
              name: "Ray ngăn kéo #{index} - Phải",
              role: 'drawer_slide_right',
              x: settings[:width_mm] - settings[:panel_thickness_mm] - thickness,
              y: side.y, z: z,
              size_x: thickness, size_y: length, size_z: height,
              length: length, width: height, thickness: thickness,
              assembly_index: index, owner_part_key: owner_key
            )
          ]
        end

        def hardware_part(settings, key:, name:, role:, x:, y:, z:, size_x:, size_y:, size_z:, length:, width:, thickness:, assembly_index: nil, owner_part_key: nil, shape: 'box')
          part(
            key: key, name: name, role: role,
            x: x, y: y, z: z,
            size_x: size_x, size_y: size_y, size_z: size_z,
            length: length, width: width, thickness: thickness,
            grain: 'không áp dụng', edge_front: false,
            kind: 'hardware', material_name: settings[:hardware_material_name],
            assembly_index: assembly_index, owner_part_key: owner_part_key,
            shape: shape
          )
        end

        def resolved_hinge_count(settings, front)
          requested = settings[:hinge_count]
          return requested if requested.positive?
          return 2 if front.role == 'flap_front' || front.size_z <= 900
          return 3 if front.size_z <= 1600
          return 4 if front.size_z <= 2200

          5
        end

        def resolved_drawer_slide_length(settings, maximum)
          requested = settings[:drawer_slide_length_mm]
          requested.positive? ? requested : maximum
        end

        def front_parts(settings)
          layout = settings[:front_layout]
          return [] if layout == Presets::FRONT_NONE

          bounds = front_bounds(settings)
          case layout
          when Presets::FRONT_SINGLE_DOOR
            [front_panel(settings, bounds, key: 'canh_1', name: 'Cánh tủ', role: 'door')]
          when Presets::FRONT_DOUBLE_DOOR
            double_door_fronts(settings, bounds)
          when Presets::FRONT_TOP_DRAWER_DOUBLE_DOOR
            top_drawer_double_door_fronts(settings, bounds)
          when Presets::FRONT_TWO_DRAWERS
            equal_drawer_fronts(settings, bounds, 2)
          when Presets::FRONT_THREE_DRAWERS
            equal_drawer_fronts(settings, bounds, 3)
          when Presets::FRONT_FOUR_DRAWERS
            equal_drawer_fronts(settings, bounds, 4)
          when Presets::FRONT_FLAP
            [front_panel(settings, bounds, key: 'canh_lat_1', name: 'Cánh lật', role: 'flap_front')]
          else
            []
          end
        end

        def double_door_fronts(settings, bounds, name_suffix: '')
          gap = settings[:front_gap_mm]
          width = (bounds[:width] - gap) / 2.0
          [
            front_panel(
              settings,
              bounds.merge(width: width),
              key: "canh_trai#{name_suffix}",
              name: 'Cánh trái',
              role: 'door_left'
            ),
            front_panel(
              settings,
              bounds.merge(x: bounds[:x] + width + gap, width: width),
              key: "canh_phai#{name_suffix}",
              name: 'Cánh phải',
              role: 'door_right'
            )
          ]
        end

        def top_drawer_double_door_fronts(settings, bounds)
          gap = settings[:front_gap_mm]
          drawer_height = settings[:top_drawer_height_mm]
          door_height = bounds[:height] - drawer_height - gap
          doors = double_door_fronts(settings, bounds.merge(height: door_height), name_suffix: '_duoi')
          drawer = front_panel(
            settings,
            bounds.merge(z: bounds[:z] + door_height + gap, height: drawer_height),
            key: 'mat_ngan_keo_tren',
            name: 'Mặt ngăn kéo trên',
            role: 'drawer_front',
            assembly_index: 1
          )
          doors + [drawer]
        end

        def equal_drawer_fronts(settings, bounds, count)
          gap = settings[:front_gap_mm]
          height = (bounds[:height] - ((count - 1) * gap)) / count.to_f
          count.times.map do |index|
            position_from_bottom = count - index - 1
            z = bounds[:z] + (position_from_bottom * (height + gap))
            front_panel(
              settings,
              bounds.merge(z: z, height: height),
              key: "mat_ngan_keo_#{index + 1}",
              name: "Mặt ngăn kéo #{index + 1}",
              role: 'drawer_front',
              assembly_index: index + 1
            )
          end
        end

        def front_panel(settings, bounds, key:, name:, role:, assembly_index: nil)
          front_thickness = settings[:front_thickness_mm]
          front_y = settings[:front_cover_mode] == Presets::COVER_INSET ? 0 : -front_thickness
          part(
            key: key,
            name: name,
            role: role,
            x: bounds[:x],
            y: front_y,
            z: bounds[:z],
            size_x: bounds[:width],
            size_y: front_thickness,
            size_z: bounds[:height],
            length: bounds[:height],
            width: bounds[:width],
            thickness: front_thickness,
            grain: installed_front_grain(settings, role),
            grain_axis: installed_front_grain_axis(settings, role),
            edge_front: false,
            edge_all: settings[:front_edge_band_all],
            kind: 'front',
            material_name: settings[:front_material_name],
            assembly_index: assembly_index
          )
        end

        def front_bounds(settings)
          gap = settings[:front_gap_mm]
          thickness = settings[:panel_thickness_mm]
          if settings[:front_cover_mode] == Presets::COVER_INSET
            {
              x: thickness + gap,
              z: settings[:plinth_height_mm] + thickness + gap,
              width: settings[:width_mm] - (2 * thickness) - (2 * gap),
              height: settings[:height_mm] - settings[:plinth_height_mm] - (2 * thickness) - (2 * gap)
            }
          else
            {
              x: gap,
              z: settings[:plinth_height_mm] + gap,
              width: settings[:width_mm] - (2 * gap),
              height: settings[:height_mm] - settings[:plinth_height_mm] - (2 * gap)
            }
          end
        end

        def validate_fronts(settings)
          return nil if settings[:front_layout] == Presets::FRONT_NONE
          return 'Tên vật liệu mặt cánh không được để trống.' if settings[:front_material_name].empty?
          return 'Độ dày mặt cánh phải lớn hơn 0.' unless settings[:front_thickness_mm].positive?
          return 'Khe hở mặt cánh không được âm.' if settings[:front_gap_mm].negative?

          bounds = front_bounds(settings)
          return 'Khe hở mặt cánh quá lớn so với chiều rộng hoặc chiều cao tủ.' unless bounds[:width].positive? && bounds[:height].positive?

          gap = settings[:front_gap_mm]
          case settings[:front_layout]
          when Presets::FRONT_DOUBLE_DOOR
            return 'Chiều rộng mặt cánh không đủ để chia hai cánh.' unless bounds[:width] > gap
          when Presets::FRONT_TOP_DRAWER_DOUBLE_DOOR
            return 'Chiều cao mặt ngăn kéo trên phải lớn hơn 0.' unless settings[:top_drawer_height_mm].positive?
            unless bounds[:width] > gap && bounds[:height] > (settings[:top_drawer_height_mm] + gap)
              return 'Kích thước mặt trước không đủ cho một ngăn kéo trên và hai cánh dưới.'
            end
          when Presets::FRONT_TWO_DRAWERS
            return drawer_layout_error(bounds, gap, 2)
          when Presets::FRONT_THREE_DRAWERS
            return drawer_layout_error(bounds, gap, 3)
          when Presets::FRONT_FOUR_DRAWERS
            return drawer_layout_error(bounds, gap, 4)
          end
          nil
        end

        def drawer_layout_error(bounds, gap, count)
          return nil if bounds[:height] > ((count - 1) * gap)

          "Chiều cao mặt trước không đủ để chia #{count} ngăn kéo."
        end

        def validate_drawer_boxes(settings)
          return nil unless settings[:include_drawer_boxes]
          unless Presets::DRAWER_FRONT_LAYOUTS.include?(settings[:front_layout])
            return 'Vui lòng chọn bố trí mặt trước có ngăn kéo trước khi tạo hộp ngăn kéo.'
          end
          return 'Tên vật liệu hộp ngăn kéo không được để trống.' if settings[:drawer_material_name].empty?
          return 'Độ hở ray mỗi bên không được âm.' if settings[:drawer_side_clearance_mm].negative?
          return 'Chiều sâu hộp ngăn kéo không được âm; nhập 0 để tự động.' if settings[:drawer_box_depth_mm].negative?
          return 'Chiều cao hộp ngăn kéo phải lớn hơn 0.' unless settings[:drawer_box_height_mm].positive?
          return 'Độ dày thành hộp ngăn kéo phải lớn hơn 0.' unless settings[:drawer_panel_thickness_mm].positive?
          return 'Độ dày đáy ngăn kéo phải lớn hơn 0.' unless settings[:drawer_bottom_thickness_mm].positive?
          if settings[:drawer_front_setback_mm].negative? || settings[:drawer_rear_clearance_mm].negative?
            return 'Khoảng lùi trước và khoảng hở sau của hộp ngăn kéo không được âm.'
          end

          width = drawer_outer_width(settings)
          panel = settings[:drawer_panel_thickness_mm]
          return 'Chiều rộng trong tủ không đủ cho độ hở ray và hai thành ngăn kéo.' unless width > (2 * panel)

          maximum_depth = maximum_drawer_depth(settings)
          return 'Chiều sâu trong tủ không đủ cho khoảng lùi và khoảng hở hộp ngăn kéo.' unless maximum_depth.positive?
          if settings[:drawer_box_depth_mm].positive? && settings[:drawer_box_depth_mm] > maximum_depth
            return 'Chiều sâu hộp ngăn kéo vượt quá chiều sâu sử dụng của tủ.'
          end
          return 'Chiều sâu hộp ngăn kéo không đủ cho thành trước và thành sau.' unless resolved_drawer_depth(settings) > (2 * panel)
          unless settings[:drawer_bottom_thickness_mm] < settings[:drawer_box_height_mm]
            return 'Độ dày đáy phải nhỏ hơn chiều cao hộp ngăn kéo.'
          end

          drawer_fronts = front_parts(settings).select { |front| front.role == 'drawer_front' }
          unless drawer_fronts.all? { |front| settings[:drawer_box_height_mm] < front.size_z }
            return 'Chiều cao hộp ngăn kéo phải nhỏ hơn chiều cao mỗi mặt ngăn kéo.'
          end
          nil
        end

        def validate_hardware(settings)
          enabled = settings[:include_handles] || settings[:include_hinges] ||
                    settings[:include_drawer_slides]
          return nil unless enabled
          return 'Tên vật liệu phụ kiện không được để trống.' if settings[:hardware_material_name].empty?

          fronts = front_parts(settings)
          handle_error = validate_handles(settings, fronts)
          return handle_error if handle_error
          hinge_error = validate_hinges(settings, fronts)
          return hinge_error if hinge_error
          validate_drawer_slides(settings)
        end

        def validate_handles(settings, fronts)
          return nil unless settings[:include_handles] && fronts.any?
          unless settings[:handle_length_mm].positive? && settings[:handle_width_mm].positive? &&
                 settings[:handle_projection_mm].positive?
            return 'Kích thước tay nắm phải lớn hơn 0.'
          end
          return 'Khoảng cách tay nắm đến cạnh không được âm.' if settings[:handle_edge_offset_mm].negative?

          fronts.each do |front|
            vertical = HINGE_FRONT_ROLES.include?(front.role) && front.role != 'flap_front'
            if vertical
              unless settings[:handle_length_mm] <= front.size_z &&
                     (settings[:handle_edge_offset_mm] + (settings[:handle_width_mm] / 2.0)) <= front.size_x
                return "Tay nắm không vừa mặt cánh #{front.name}."
              end
            elsif settings[:handle_length_mm] > front.size_x || settings[:handle_width_mm] > front.size_z
              return "Tay nắm không vừa #{front.name.downcase}."
            end
          end
          nil
        end

        def validate_hinges(settings, fronts)
          return nil unless settings[:include_hinges]

          count = settings[:hinge_count]
          unless count.zero? || count.between?(2, MAX_HINGE_COUNT)
            return "Số bản lề phải bằng 0 để tự động hoặc từ 2 đến #{MAX_HINGE_COUNT}."
          end
          unless settings[:hinge_cup_diameter_mm].positive? && settings[:hinge_cup_depth_mm].positive?
            return 'Đường kính và chiều sâu chén bản lề phải lớn hơn 0.'
          end
          if settings[:hinge_edge_offset_mm].negative? || settings[:hinge_end_offset_mm].negative?
            return 'Khoảng cách bản lề đến cạnh và hai đầu không được âm.'
          end
          if settings[:hinge_cup_depth_mm] > settings[:front_thickness_mm]
            return 'Chiều sâu chén bản lề không được lớn hơn độ dày mặt cánh.'
          end

          radius = settings[:hinge_cup_diameter_mm] / 2.0
          fronts.select { |front| HINGE_FRONT_ROLES.include?(front.role) }.each do |front|
            cross_span = front.role == 'flap_front' ? front.size_z : front.size_x
            main_span = front.role == 'flap_front' ? front.size_x : front.size_z
            unless settings[:hinge_edge_offset_mm] >= radius &&
                   (settings[:hinge_edge_offset_mm] + radius) <= cross_span
              return "Chén bản lề vượt khỏi cạnh của #{front.name.downcase}."
            end
            unless settings[:hinge_end_offset_mm] >= radius &&
                   (settings[:hinge_end_offset_mm] + radius) <= main_span &&
                   main_span > (2 * settings[:hinge_end_offset_mm])
              return "Khoảng cách bản lề hai đầu không phù hợp với #{front.name.downcase}."
            end
          end
          nil
        end

        def validate_drawer_slides(settings)
          return nil unless settings[:include_drawer_slides]

          sides = drawer_box_parts(settings).select { |part| part.role == 'drawer_side_left' }
          return nil if sides.empty?
          return 'Chiều dài ray ngăn kéo không được âm; nhập 0 để tự động.' if settings[:drawer_slide_length_mm].negative?
          unless settings[:drawer_slide_height_mm].positive? && settings[:drawer_slide_thickness_mm].positive?
            return 'Chiều cao và độ dày ray ngăn kéo phải lớn hơn 0.'
          end
          if settings[:drawer_slide_thickness_mm] > settings[:drawer_side_clearance_mm]
            return 'Độ dày ray không được lớn hơn độ hở ray mỗi bên.'
          end
          if sides.any? { |side| settings[:drawer_slide_height_mm] > side.size_z }
            return 'Chiều cao ray không được lớn hơn chiều cao hộp ngăn kéo.'
          end
          if settings[:drawer_slide_length_mm].positive? &&
             sides.any? { |side| settings[:drawer_slide_length_mm] > side.size_y }
            return 'Chiều dài ray vượt quá chiều sâu hộp ngăn kéo.'
          end
          nil
        end

        def drawer_outer_width(settings)
          settings[:width_mm] - (2 * settings[:panel_thickness_mm]) -
            (2 * settings[:drawer_side_clearance_mm])
        end

        def maximum_drawer_depth(settings)
          cabinet_usable_depth(settings) - settings[:drawer_front_setback_mm] -
            settings[:drawer_rear_clearance_mm]
        end

        def resolved_drawer_depth(settings)
          requested = settings[:drawer_box_depth_mm]
          requested.positive? ? requested : maximum_drawer_depth(settings)
        end

        def carcass_parts(settings)
          width = settings[:width_mm]
          height = settings[:height_mm]
          depth = settings[:depth_mm]
          thickness = settings[:panel_thickness_mm]
          usable_depth = cabinet_usable_depth(settings)
          internal_width = width - (2 * thickness)
          bottom_z = settings[:plinth_height_mm]

          [
            part(
              key: 'hong_trai', name: 'Hông trái', role: 'side_left',
              x: 0, y: 0, z: 0, size_x: thickness, size_y: depth, size_z: height,
              length: height, width: depth, thickness: thickness,
              grain: installed_grain(settings, :vertical),
              grain_axis: installed_grain_axis(settings, :vertical),
              edge_front: settings[:edge_band_front]
            ),
            part(
              key: 'hong_phai', name: 'Hông phải', role: 'side_right',
              x: width - thickness, y: 0, z: 0, size_x: thickness, size_y: depth, size_z: height,
              length: height, width: depth, thickness: thickness,
              grain: installed_grain(settings, :vertical),
              grain_axis: installed_grain_axis(settings, :vertical),
              edge_front: settings[:edge_band_front]
            ),
            part(
              key: 'noc', name: 'Nóc tủ', role: 'top',
              x: thickness, y: 0, z: height - thickness,
              size_x: internal_width, size_y: usable_depth, size_z: thickness,
              length: internal_width, width: usable_depth, thickness: thickness,
              grain: installed_grain(settings, :horizontal),
              grain_axis: installed_grain_axis(settings, :horizontal),
              edge_front: settings[:edge_band_front]
            ),
            part(
              key: 'day', name: 'Đáy tủ', role: 'bottom',
              x: thickness, y: 0, z: bottom_z,
              size_x: internal_width, size_y: usable_depth, size_z: thickness,
              length: internal_width, width: usable_depth, thickness: thickness,
              grain: installed_grain(settings, :horizontal),
              grain_axis: installed_grain_axis(settings, :horizontal),
              edge_front: settings[:edge_band_front]
            )
          ]
        end

        def divider_parts(settings)
          count = settings[:divider_count]
          return [] unless count.positive?

          thickness = settings[:panel_thickness_mm]
          internal_width = settings[:width_mm] - (2 * thickness)
          clear_width = (internal_width - (count * thickness)) / (count + 1).to_f
          z = settings[:plinth_height_mm] + thickness
          height = settings[:height_mm] - z - thickness
          usable_depth = cabinet_usable_depth(settings)

          count.times.map do |index|
            x = thickness + (clear_width * (index + 1)) + (thickness * index)
            part(
              key: "vach_#{index + 1}", name: "Vách đứng #{index + 1}", role: 'divider',
              x: x, y: 0, z: z, size_x: thickness, size_y: usable_depth, size_z: height,
              length: height, width: usable_depth, thickness: thickness,
              grain: installed_grain(settings, :vertical),
              grain_axis: installed_grain_axis(settings, :vertical),
              edge_front: settings[:edge_band_front]
            )
          end
        end

        def shelf_parts(settings, dividers)
          row_count = settings[:shelf_count]
          return [] unless row_count.positive?

          thickness = settings[:panel_thickness_mm]
          bottom = settings[:plinth_height_mm] + thickness
          top = settings[:height_mm] - thickness
          internal_height = top - bottom
          clear_height = (internal_height - (row_count * thickness)) / (row_count + 1).to_f
          bays = shelf_bays(settings, dividers)
          usable_depth = cabinet_usable_depth(settings)

          row_count.times.flat_map do |row_index|
            z = bottom + (clear_height * (row_index + 1)) + (thickness * row_index)
            bays.each_with_index.map do |bay, bay_index|
              suffix = bays.length > 1 ? " - Khoang #{bay_index + 1}" : ''
              part(
                key: "dot_#{row_index + 1}_#{bay_index + 1}",
                name: "Đợt #{row_index + 1}#{suffix}",
                role: 'shelf', x: bay[:x], y: 0, z: z,
                size_x: bay[:width], size_y: usable_depth, size_z: thickness,
                length: bay[:width], width: usable_depth, thickness: thickness,
                grain: installed_grain(settings, :horizontal),
                grain_axis: installed_grain_axis(settings, :horizontal),
                edge_front: settings[:edge_band_front]
              )
            end
          end
        end

        def shelf_bays(settings, dividers)
          thickness = settings[:panel_thickness_mm]
          cursor = thickness
          dividers.map do |divider|
            bay = { x: cursor, width: divider.x - cursor }
            cursor = divider.x + divider.size_x
            bay
          end.concat([{ x: cursor, width: settings[:width_mm] - thickness - cursor }])
        end

        def back_part(settings)
          thickness = settings[:back_thickness_mm]
          part(
            key: 'hau', name: 'Tấm hậu', role: 'back',
            x: 0, y: settings[:depth_mm] - thickness, z: 0,
            size_x: settings[:width_mm], size_y: thickness, size_z: settings[:height_mm],
            length: settings[:height_mm], width: settings[:width_mm], thickness: thickness,
            grain: installed_grain(settings, :vertical),
            grain_axis: installed_grain_axis(settings, :vertical), edge_front: false
          )
        end

        def plinth_part(settings)
          thickness = settings[:panel_thickness_mm]
          internal_width = settings[:width_mm] - (2 * thickness)
          part(
            key: 'chan_truoc', name: 'Chân tủ trước', role: 'plinth',
            x: thickness, y: settings[:plinth_setback_mm], z: 0,
            size_x: internal_width, size_y: thickness, size_z: settings[:plinth_height_mm],
            length: internal_width, width: settings[:plinth_height_mm], thickness: thickness,
            grain: installed_grain(settings, :horizontal),
            grain_axis: installed_grain_axis(settings, :horizontal), edge_front: false
          )
        end

        def cabinet_usable_depth(settings)
          settings[:depth_mm] - (settings[:include_back] ? settings[:back_thickness_mm] : 0)
        end

        def part(key:, name:, role:, x:, y:, z:, size_x:, size_y:, size_z:, length:, width:, thickness:, grain:, edge_front:, grain_axis: 'length', edge_all: false, kind: 'carcass', material_name: nil, assembly_index: nil, owner_part_key: nil, shape: 'box')
          edge_value = edge_all == true
          Part.new(
            key: key,
            name: name,
            role: role,
            x: x.to_f,
            y: y.to_f,
            z: z.to_f,
            size_x: size_x.to_f,
            size_y: size_y.to_f,
            size_z: size_z.to_f,
            finished_length: length.to_f,
            finished_width: width.to_f,
            thickness: thickness.to_f,
            grain_direction: grain,
            grain_axis: grain_axis,
            edge_banding: {
              front: edge_value || edge_front,
              back: edge_value,
              left: edge_value,
              right: edge_value
            },
            kind: kind,
            material_name: material_name,
            assembly_index: assembly_index,
            owner_part_key: owner_part_key,
            shape: shape
          )
        end

        def installed_grain(settings, automatic_direction)
          case settings[:grain_mode]
          when Presets::GRAIN_VERTICAL
            'dọc'
          when Presets::GRAIN_HORIZONTAL
            'ngang'
          else
            automatic_direction == :vertical ? 'dọc' : 'ngang'
          end
        end

        def installed_grain_axis(settings, automatic_direction)
          case settings[:grain_mode]
          when Presets::GRAIN_VERTICAL
            automatic_direction == :vertical ? 'length' : 'width'
          when Presets::GRAIN_HORIZONTAL
            automatic_direction == :horizontal ? 'length' : 'width'
          else
            'length'
          end
        end

        def installed_front_grain(settings, role)
          case settings[:front_grain_mode]
          when Presets::GRAIN_VERTICAL
            'dọc'
          when Presets::GRAIN_HORIZONTAL
            'ngang'
          else
            role == 'drawer_front' || role == 'flap_front' ? 'ngang' : 'dọc'
          end
        end

        def installed_front_grain_axis(settings, role)
          case settings[:front_grain_mode]
          when Presets::GRAIN_VERTICAL
            'length'
          when Presets::GRAIN_HORIZONTAL
            'width'
          else
            role == 'drawer_front' || role == 'flap_front' ? 'width' : 'length'
          end
        end

        def repeat_count_invalid?(settings)
          REQUIRED_INTEGER_KEYS.any? do |key|
            value = settings[key]
            value.nil? || value.negative? || value > MAX_REPEAT_COUNT
          end
        end

        def value_for(values, key)
          return nil unless values.respond_to?(:[])

          return values[key] if values.respond_to?(:key?) && values.key?(key)
          return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

          values[key]
        end

        def front_settings_present?(values)
          return false unless values.respond_to?(:key?)

          Presets::DEFAULT_FRONT_SETTINGS.keys.any? do |key|
            values.key?(key) || values.key?(key.to_s)
          end
        end

        def drawer_settings_present?(values)
          return false unless values.respond_to?(:key?)

          Presets::DEFAULT_DRAWER_SETTINGS.keys.any? do |key|
            values.key?(key) || values.key?(key.to_s)
          end
        end

        def hardware_settings_present?(values)
          return false unless values.respond_to?(:key?)

          Presets::DEFAULT_HARDWARE_SETTINGS.keys.any? do |key|
            values.key?(key) || values.key?(key.to_s)
          end
        end

        def string_value(value, fallback)
          result = value.nil? ? fallback.to_s : value.to_s.strip
          result.empty? ? fallback.to_s : result
        end

        def numeric_value(value, fallback)
          return fallback.to_f if value.nil? || value.to_s.strip.empty?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def integer_value(value, fallback)
          number = numeric_value(value, fallback)
          return nil unless number && number == number.to_i

          number.to_i
        end

        def boolean_value(value, fallback)
          return fallback if value.nil?
          return value if value == true || value == false

          %w[true yes 1 có].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
