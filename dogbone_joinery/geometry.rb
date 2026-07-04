# frozen_string_literal: true

# Geometry routines for Dogbone Joinery. The first generator creates standalone
# grouped templates only and does not modify any selected model geometry.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Geometry
        MORTISE_GROUP_NAME = 'Dogbone_Mortise_Template'
        MORTISE_PROFILE_GROUP_NAME = 'Dogbone_Mortise_2D_Profile'
        MORTISE_CUTTER_GROUP_NAME = 'Dogbone_Mortise_Cutter'
        TENON_GROUP_NAME = 'Dogbone_Tenon_Template'
        LABELS_GROUP_NAME = 'Dogbone_Joint_Labels'
        MORTISE_MATERIAL_NAME = 'SonVu CNC Mộng âm màu đỏ'
        TENON_MATERIAL_NAME = 'SonVu CNC Mộng dương màu xanh'
        TEMPLATE_GAP_MM = 10
        LABEL_GAP_MM = 8
        LABEL_LINE_SPACING_MM = 5
        DOGBONE_ARC_SEGMENTS = 24
        DIAGONAL_CENTER_OFFSET_FACTOR = 0.5
        TBONE_CENTER_OFFSET_FACTOR = 0.65
        DOGBONE_STYLE_DIAGONAL = 'Chéo'
        DOGBONE_STYLE_HORIZONTAL_TBONE = 'Ngang (T-bone)'
        DOGBONE_STYLE_VERTICAL_TBONE = 'Dọc (T-bone)'
        GENERATED_GROUP_NAMES = [
          MORTISE_GROUP_NAME,
          TENON_GROUP_NAME,
          LABELS_GROUP_NAME,
          MORTISE_PROFILE_GROUP_NAME
        ].freeze

        module_function

        def create_templates(params, origin: Geom::Point3d.new(0, 0, 0), transformation: nil)
          model = Sketchup.active_model
          model.start_operation('Tạo mẫu mộng xương chó', true)

          begin
            groups = []
            groups << create_mortise_template(params, origin: origin) if params[:create_mortise]
            groups << create_tenon_template(params, origin: origin) if params[:create_tenon]
            groups << create_labels(params, origin: origin) if params[:add_labels]
            groups.each { |group| mark_generated_group(group) }
            groups.each { |group| group.transform!(transformation) } if transformation

            model.commit_operation
            groups
          rescue StandardError
            model.abort_operation
            raise
          end
        end

        def create_dogbone_mortise_profile(params, origin: Geom::Point3d.new(0, 0, 0))
          group = Sketchup.active_model.active_entities.add_group
          group.name = MORTISE_PROFILE_GROUP_NAME

          points = translate_points(points_for_dogbone_mortise_profile(params), origin)
          add_polyline_face(group.entities, points)

          mark_generated_group(group)
          group
        end

        def cut_mortise_into_solid(target, params, origin: Geom::Point3d.new(0, 0, 0), transformation: nil)
          model = Sketchup.active_model
          model.start_operation('Cắt mộng âm xương chó vào khối', true)

          begin
            backup = create_cut_backup(target)
            cutter = create_mortise_cutter(params, origin: origin)
            cutter.transform!(transformation) if transformation

            result = target.subtract(cutter)
            raise 'SketchUp không cắt được khối. Vui lòng kiểm tra khối có phải solid hợp lệ không.' unless result && result.valid?

            cutter.erase! if cutter.valid?
            target.erase! if target.valid? && target != result
            name_boolean_result(result)

            model.commit_operation
            result
          rescue StandardError
            model.abort_operation
            raise
          end
        end

        def create_cut_backup(target)
          backup = target.copy
          backup.name = backup_name(target)
          move_backup_aside(backup, target)
          backup
        end

        def move_backup_aside(backup, target)
          bounds = target.bounds
          offset = [bounds.width, bounds.height, bounds.depth].max + template_gap
          backup.transform!(Geom::Transformation.translation([offset, 0, 0]))
        end

        def backup_name(target)
          base_name = target.name.to_s.strip
          base_name = 'Khoi_Da_Chon' if base_name.empty?
          "Dogbone_Backup_#{base_name}"
        end

        def name_boolean_result(result)
          result.name = 'Dogbone_Cut_Result' if result.respond_to?(:name=)
        end

        def generated_group?(entity)
          entity.is_a?(Sketchup::Group) &&
            GENERATED_GROUP_NAMES.include?(entity.name) &&
            entity.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, CNCPlugins::GENERATED_GROUP_ATTRIBUTE) == true
        end

        def mark_generated_group(group)
          group.set_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, CNCPlugins::GENERATED_GROUP_ATTRIBUTE, true)
          group
        end

        def create_mortise_template(params, origin: Geom::Point3d.new(0, 0, 0))
          group = Sketchup.active_model.active_entities.add_group
          group.name = MORTISE_GROUP_NAME

          points = translate_points(points_for_dogbone_mortise_profile(params), origin)
          face = add_polyline_face(group.entities, points)
          # Mortise represents material to be cut away, so extrude inward from
          # the placement plane. On selected faces, local -Z maps opposite the
          # face normal and visually reads as a recess into the board.
          face.pushpull(-params.fetch(:mortise_depth))

          apply_group_material(group, mortise_material)
          mark_generated_group(group)
          group
        end

        def create_mortise_cutter(params, origin: Geom::Point3d.new(0, 0, 0))
          group = Sketchup.active_model.active_entities.add_group
          group.name = MORTISE_CUTTER_GROUP_NAME

          points = translate_points(points_for_dogbone_mortise_profile(params), origin)
          face = add_polyline_face(group.entities, points)
          face.pushpull(-params.fetch(:mortise_depth))

          group
        end

        def create_tenon_template(params, origin: Geom::Point3d.new(0, 0, 0))
          tenon_width = params.fetch(:tenon_width)
          tenon_height = params.fetch(:tenon_height)
          tenon_thickness = params.fetch(:tenon_thickness)

          validate_tenon_dimensions(tenon_width, tenon_height, tenon_thickness)

          tenon_origin = tenon_template_origin(params, origin)

          group = Sketchup.active_model.active_entities.add_group
          group.name = TENON_GROUP_NAME

          points = translate_points(build_tenon_profile_points(params), tenon_origin)
          face = add_polyline_face(group.entities, points)
          # The tenon is generated from a closed 2D CNC profile first, then
          # extruded into a clean grouped solid.
          face.pushpull(tenon_thickness)

          apply_group_material(group, tenon_material)
          mark_generated_group(group)
          group
        end

        def tenon_template_origin(params, origin)
          return origin unless params[:create_mortise]

          Geom::Point3d.new(origin.x + mortise_profile_right_extent(params) + template_gap, origin.y, origin.z)
        end

        def create_labels(params, origin: Geom::Point3d.new(0, 0, 0))
          group = Sketchup.active_model.active_entities.add_group
          group.name = LABELS_GROUP_NAME

          add_mortise_labels(group.entities, params, origin) if params[:create_mortise]
          add_tenon_labels(group.entities, params, origin) if params[:create_tenon]

          mark_generated_group(group)
          group
        end

        def add_mortise_labels(entities, params, origin)
          label_origin = Geom::Point3d.new(
            origin.x,
            origin.y + params.fetch(:mortise_height) + label_gap,
            origin.z + params.fetch(:mortise_depth)
          )
          add_text_lines(entities, mortise_label_lines(params), label_origin)
        end

        def add_tenon_labels(entities, params, origin)
          tenon_width = params.fetch(:tenon_width)
          tenon_height = params.fetch(:tenon_height)
          tenon_origin_x = tenon_template_origin(params, origin).x
          label_origin = Geom::Point3d.new(
            tenon_origin_x + tenon_width + label_gap,
            origin.y - label_gap,
            origin.z + params.fetch(:tenon_thickness)
          )
          add_text_lines(entities, tenon_label_lines(tenon_width, tenon_height, params), label_origin)
        end

        def add_text_lines(entities, lines, origin)
          lines.each_with_index do |line, index|
            point = Geom::Point3d.new(origin.x, origin.y - (index * label_line_spacing), origin.z)
            entities.add_text(line, point)
          end
        end

        def mortise_label_lines(params)
          [
            "Rộng mộng âm: #{format_length_mm(params.fetch(:mortise_width))} mm",
            "Cao mộng âm: #{format_length_mm(params.fetch(:mortise_height))} mm",
            "Sâu mộng âm: #{format_length_mm(params.fetch(:mortise_depth))} mm",
            "Đường kính dao CNC: #{format_length_mm(params.fetch(:cutter_diameter))} mm",
            "Độ hở lắp ráp: #{format_length_mm(params.fetch(:clearance))} mm"
          ]
        end

        def tenon_label_lines(tenon_width, tenon_height, params)
          [
            "Rộng mộng dương: #{format_length_mm(tenon_width)} mm",
            "Cao mộng dương theo mặt chọn: #{format_length_mm(tenon_height)} mm",
            "Dày mộng dương: #{format_length_mm(params.fetch(:tenon_thickness))} mm"
          ]
        end

        def validate_tenon_dimensions(width, height, length)
          raise 'Rộng mộng dương phải lớn hơn 0.' unless width.positive?
          raise 'Cao mộng dương phải lớn hơn 0.' unless height.positive?
          raise 'Dày mộng dương phải lớn hơn 0.' unless length.positive?
        end

        def build_tenon_profile_points(params)
          tenon_width = params.fetch(:tenon_width)
          tenon_height = params.fetch(:tenon_height)
          tenon_thickness = params.fetch(:tenon_thickness)

          validate_tenon_dimensions(tenon_width, tenon_height, tenon_thickness)
          return rectangle_points(Geom::Point3d.new(0, 0, 0), tenon_width, tenon_height) unless params.fetch(:tenon_relief_enabled, true)

          add_side_semicircle_reliefs(tenon_width, tenon_height, params.fetch(:cutter_diameter) / 2.0)
        end

        def add_side_semicircle_reliefs(tenon_width, tenon_height, cutter_radius)
          validate_side_relief_dimensions(tenon_width, tenon_height, cutter_radius)

          relief_center_y = tenon_height / 2.0

          # Side-edge reliefs:
          # The tenon is a rectangular tab across the selected side face. The
          # cutter-radius half-circles are cut into the left and right ends,
          # matching the side-root relief shape shown in the reference model.
          points = [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(tenon_width, 0, 0),
            Geom::Point3d.new(tenon_width, relief_center_y - cutter_radius, 0)
          ]
          points.concat(
            side_relief_arc_points(
              Geom::Point3d.new(tenon_width, relief_center_y, 0),
              cutter_radius,
              -Math::PI / 2.0,
              -Math::PI * 1.5
            )
          )
          points << Geom::Point3d.new(tenon_width, tenon_height, 0)
          points << Geom::Point3d.new(0, tenon_height, 0)
          points << Geom::Point3d.new(0, relief_center_y + cutter_radius, 0)
          points.concat(
            side_relief_arc_points(
              Geom::Point3d.new(0, relief_center_y, 0),
              cutter_radius,
              Math::PI / 2.0,
              -Math::PI / 2.0
            )
          )
          remove_duplicate_neighbor_points(points)
        end

        def validate_side_relief_dimensions(tenon_width, tenon_height, cutter_radius)
          raise 'Bán kính dao phải lớn hơn 0.' unless cutter_radius.positive?

          minimum_size = cutter_radius * 2.0
          return if tenon_width > minimum_size && tenon_height > minimum_size

          raise 'Mộng dương quá nhỏ để khoét bán nguyệt ở hai đầu theo bán kính dao.'
        end

        def side_relief_arc_points(center, radius, start_angle, end_angle)
          sweep = end_angle - start_angle

          (1..DOGBONE_ARC_SEGMENTS).map do |index|
            angle = start_angle + (sweep * index / DOGBONE_ARC_SEGMENTS)
            Geom::Point3d.new(
              center.x + (Math.cos(angle) * radius),
              center.y + (Math.sin(angle) * radius),
              0
            )
          end
        end

        def points_for_dogbone_mortise_profile(params)
          case params.fetch(:dogbone_style, DOGBONE_STYLE_DIAGONAL)
          when DOGBONE_STYLE_DIAGONAL
            points_for_diagonal_dogbone(params)
          when DOGBONE_STYLE_HORIZONTAL_TBONE
            points_for_horizontal_tbone(params)
          when DOGBONE_STYLE_VERTICAL_TBONE
            points_for_vertical_tbone(params)
          else
            raise unsupported_style_message(params[:dogbone_style])
          end
        end

        def points_for_diagonal_dogbone(params)
          width = params.fetch(:mortise_width)
          height = params.fetch(:mortise_height)
          radius = params.fetch(:cutter_diameter) / 2.0
          offset = diagonal_center_offset(radius)

          # Dog-bone geometry:
          # The base mortise is a rectangle on the ground plane. Each relief is
          # a cutter-radius circle with its center offset diagonally outward from
          # a rectangle corner. The profile follows the outer circle arcs between
          # the adjacent rectangle edges, giving a CNC cutter room to clear the
          # otherwise sharp internal corners.
          points_for_relief_centers(
            width: width,
            height: height,
            radius: radius,
            centers: {
              bottom_left: Geom::Point3d.new(-offset, -offset, 0),
              bottom_right: Geom::Point3d.new(width + offset, -offset, 0),
              top_right: Geom::Point3d.new(width + offset, height + offset, 0),
              top_left: Geom::Point3d.new(-offset, height + offset, 0)
            }
          )
        end

        def points_for_horizontal_tbone(params)
          width = params.fetch(:mortise_width)
          height = params.fetch(:mortise_height)
          radius = params.fetch(:cutter_diameter) / 2.0
          offset = tbone_center_offset(radius)

          # Horizontal T-bone geometry moves each cutter center horizontally
          # outward from the corner. Reliefs on the left extend toward negative
          # X, and reliefs on the right extend toward positive X.
          points_for_relief_centers(
            width: width,
            height: height,
            radius: radius,
            centers: {
              bottom_left: Geom::Point3d.new(-offset, 0, 0),
              bottom_right: Geom::Point3d.new(width + offset, 0, 0),
              top_right: Geom::Point3d.new(width + offset, height, 0),
              top_left: Geom::Point3d.new(-offset, height, 0)
            },
            preferences: {
              bottom_left: { left: :max, bottom: :min },
              bottom_right: { bottom: :max, right: :max },
              top_right: { right: :min, top: :max },
              top_left: { top: :min, left: :min }
            }
          )
        end

        def points_for_vertical_tbone(params)
          width = params.fetch(:mortise_width)
          height = params.fetch(:mortise_height)
          radius = params.fetch(:cutter_diameter) / 2.0
          offset = tbone_center_offset(radius)

          # Vertical T-bone geometry moves each cutter center vertically outward
          # from the corner. Bottom reliefs extend toward negative Y, and top
          # reliefs extend toward positive Y.
          points_for_relief_centers(
            width: width,
            height: height,
            radius: radius,
            centers: {
              bottom_left: Geom::Point3d.new(0, -offset, 0),
              bottom_right: Geom::Point3d.new(width, -offset, 0),
              top_right: Geom::Point3d.new(width, height + offset, 0),
              top_left: Geom::Point3d.new(0, height + offset, 0)
            },
            preferences: {
              bottom_left: { left: :min, bottom: :max },
              bottom_right: { bottom: :min, right: :min },
              top_right: { right: :max, top: :min },
              top_left: { top: :max, left: :max }
            }
          )
        end

        def points_for_relief_centers(width:, height:, radius:, centers:, preferences: default_relief_preferences)
          bottom_left = {
            center: centers.fetch(:bottom_left),
            left: vertical_circle_intersection(
              centers.fetch(:bottom_left),
              radius,
              0,
              preferences.dig(:bottom_left, :left)
            ),
            bottom: horizontal_circle_intersection(
              centers.fetch(:bottom_left),
              radius,
              0,
              preferences.dig(:bottom_left, :bottom)
            )
          }
          bottom_right = {
            center: centers.fetch(:bottom_right),
            bottom: horizontal_circle_intersection(
              centers.fetch(:bottom_right),
              radius,
              0,
              preferences.dig(:bottom_right, :bottom)
            ),
            right: vertical_circle_intersection(
              centers.fetch(:bottom_right),
              radius,
              width,
              preferences.dig(:bottom_right, :right)
            )
          }
          top_right = {
            center: centers.fetch(:top_right),
            right: vertical_circle_intersection(
              centers.fetch(:top_right),
              radius,
              width,
              preferences.dig(:top_right, :right)
            ),
            top: horizontal_circle_intersection(
              centers.fetch(:top_right),
              radius,
              height,
              preferences.dig(:top_right, :top)
            )
          }
          top_left = {
            center: centers.fetch(:top_left),
            top: horizontal_circle_intersection(
              centers.fetch(:top_left),
              radius,
              height,
              preferences.dig(:top_left, :top)
            ),
            left: vertical_circle_intersection(
              centers.fetch(:top_left),
              radius,
              0,
              preferences.dig(:top_left, :left)
            )
          }

          points = [bottom_left[:bottom], bottom_right[:bottom]]
          points.concat(dogbone_arc_points(bottom_right[:center], radius, bottom_right[:bottom], bottom_right[:right]))
          points << top_right[:right]
          points.concat(dogbone_arc_points(top_right[:center], radius, top_right[:right], top_right[:top]))
          points << top_left[:top]
          points.concat(dogbone_arc_points(top_left[:center], radius, top_left[:top], top_left[:left]))
          points << bottom_left[:left]
          points.concat(dogbone_arc_points(bottom_left[:center], radius, bottom_left[:left], bottom_left[:bottom]))
          remove_duplicate_neighbor_points(points)
        end

        def default_relief_preferences
          {
            bottom_left: { left: :max, bottom: :max },
            bottom_right: { bottom: :min, right: :max },
            top_right: { right: :min, top: :min },
            top_left: { top: :max, left: :min }
          }
        end

        def horizontal_circle_intersection(center, radius, y, preferred_x)
          delta_y = y - center.y
          delta_x = Math.sqrt((radius * radius) - (delta_y * delta_y))
          x_values = [center.x - delta_x, center.x + delta_x]
          Geom::Point3d.new(x_values.public_send(preferred_x), y, 0)
        end

        def vertical_circle_intersection(center, radius, x, preferred_y)
          delta_x = x - center.x
          delta_y = Math.sqrt((radius * radius) - (delta_x * delta_x))
          y_values = [center.y - delta_y, center.y + delta_y]
          Geom::Point3d.new(x, y_values.public_send(preferred_y), 0)
        end

        def add_polyline_face(entities, points)
          face = entities.add_face(points)
          raise 'Không tạo được mặt biên dạng mộng xương chó.' unless face

          face
        end

        def diagonal_center_offset(radius)
          radius * DIAGONAL_CENTER_OFFSET_FACTOR
        end

        def tbone_center_offset(radius)
          radius * TBONE_CENTER_OFFSET_FACTOR
        end

        def mortise_profile_right_extent(params)
          points_for_dogbone_mortise_profile(params).map(&:x).max
        end

        def unsupported_style_message(style)
          supported_styles = [
            DOGBONE_STYLE_DIAGONAL,
            DOGBONE_STYLE_HORIZONTAL_TBONE,
            DOGBONE_STYLE_VERTICAL_TBONE
          ].join(', ')
          "Kiểu khoét góc mộng âm không hỗ trợ: #{style}. Các kiểu hợp lệ: #{supported_styles}."
        end

        def dogbone_arc_points(center, radius, start_point, end_point)
          start_angle = angle_from_center(center, start_point)
          end_angle = angle_from_center(center, end_point)
          sweep = shortest_angle_sweep(start_angle, end_angle)

          (1..DOGBONE_ARC_SEGMENTS).map do |index|
            angle = start_angle + (sweep * index / DOGBONE_ARC_SEGMENTS)
            Geom::Point3d.new(
              center.x + (Math.cos(angle) * radius),
              center.y + (Math.sin(angle) * radius),
              0
            )
          end
        end

        def angle_from_center(center, point)
          Math.atan2(point.y - center.y, point.x - center.x)
        end

        def shortest_angle_sweep(start_angle, end_angle)
          sweep = end_angle - start_angle
          two_pi = Math::PI * 2.0
          sweep += two_pi while sweep <= -Math::PI
          sweep -= two_pi while sweep > Math::PI
          sweep
        end

        def remove_duplicate_neighbor_points(points)
          points.each_with_object([]) do |point, unique_points|
            unique_points << point unless same_point?(point, unique_points.last)
          end
        end

        def same_point?(first, second)
          return false unless first && second

          first.distance(second) < 0.001
        end

        def translate_points(points, origin)
          points.map do |point|
            Geom::Point3d.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
          end
        end

        def create_rectangular_solid(group_name:, width:, height:, depth:, origin:, material: nil)
          group = Sketchup.active_model.active_entities.add_group
          group.name = group_name

          # Coordinate system:
          # X axis = template width, Y axis = template height, Z axis = depth.
          # Each rectangle is drawn on the ground plane (Z = 0) and pushed
          # upward along positive Z so all generated geometry stays in its group.
          points = rectangle_points(origin, width, height)

          face = group.entities.add_face(points)
          raise "Không tạo được mặt cho nhóm #{group_name}." unless face

          face.pushpull(depth)
          apply_group_material(group, material) if material
          mark_generated_group(group) if GENERATED_GROUP_NAMES.include?(group.name)
          group
        end

        def apply_group_material(group, material)
          group.material = material
          group.entities.grep(Sketchup::Face).each do |face|
            face.material = material
            face.back_material = material
          end
        end

        def mortise_material
          CNCPlugins::Materials.find_or_create_material(
            MORTISE_MATERIAL_NAME,
            Sketchup::Color.new(255, 120, 120),
            0.55
          )
        end

        def tenon_material
          CNCPlugins::Materials.find_or_create_material(
            TENON_MATERIAL_NAME,
            Sketchup::Color.new(120, 220, 140),
            0.55
          )
        end

        def template_gap
          CNCPlugins::Units.millimeters_to_model_units(TEMPLATE_GAP_MM)
        end

        def label_gap
          CNCPlugins::Units.millimeters_to_model_units(LABEL_GAP_MM)
        end

        def label_line_spacing
          CNCPlugins::Units.millimeters_to_model_units(LABEL_LINE_SPACING_MM)
        end

        def format_length_mm(length)
          millimeters = CNCPlugins::Units.model_units_to_millimeters(length)
          format('%.3f', millimeters).sub(/\.?0+$/, '')
        end

        def rectangle_points(origin, width, height)
          [
            Geom::Point3d.new(origin.x, origin.y, origin.z),
            Geom::Point3d.new(origin.x + width, origin.y, origin.z),
            Geom::Point3d.new(origin.x + width, origin.y + height, origin.z),
            Geom::Point3d.new(origin.x, origin.y + height, origin.z)
          ]
        end
      end
    end
  end
end
