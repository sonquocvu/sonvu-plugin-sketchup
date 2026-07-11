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
          validate_mortise_against_face(params)
          group = Sketchup.active_model.active_entities.add_group
          group.name = MORTISE_GROUP_NAME

          points = positioned_mortise_profile_points(params, origin)
          add_negative_z_profile_solid(group.entities, points, params.fetch(:mortise_depth))

          apply_group_material(group, mortise_material)
          mark_generated_group(group)
          group
        end

        def create_mortise_cutter(params, origin: Geom::Point3d.new(0, 0, 0))
          validate_mortise_against_face(params)
          group = Sketchup.active_model.active_entities.add_group
          group.name = MORTISE_CUTTER_GROUP_NAME

          points = positioned_mortise_profile_points(params, origin)
          add_negative_z_profile_solid(group.entities, points, params.fetch(:mortise_depth))

          group
        end

        def create_tenon_template(params, origin: Geom::Point3d.new(0, 0, 0))
          tenon_width = effective_tenon_width(params)
          tenon_height = effective_tenon_height(params)
          tenon_projection = tenon_projection(params)
          cutter_radius = params.fetch(:cutter_diameter) / 2.0

          validate_tenon_clearance(params)
          validate_tenon_dimensions(tenon_width, tenon_height, tenon_projection)
          validate_tenon_layout(params)
          validate_tenon_relief_dimensions(tenon_width, tenon_projection, cutter_radius) if params.fetch(:tenon_relief_enabled, true)

          tenon_origin = tenon_template_origin(params, origin)

          group = Sketchup.active_model.active_entities.add_group
          group.name = TENON_GROUP_NAME

          profile = tenon_profile_points(tenon_origin, tenon_width, tenon_projection, cutter_radius, params)
          add_xz_profile_solid(group.entities, profile, tenon_height)

          apply_group_material(group, tenon_material)
          mark_generated_group(group)
          group
        end

        def positioned_mortise_profile_points(params, origin)
          profile = normalize_profile_points(points_for_dogbone_mortise_profile(params))
          min_x = profile.map(&:x).min
          min_y = profile.map(&:y).min
          target_x = origin.x + params.fetch(:mortise_offset_x, 0)
          target_y = origin.y + params.fetch(:mortise_offset_y, 0)
          translation = Geom::Point3d.new(target_x - min_x, target_y - min_y, origin.z)
          translate_points(profile, translation)
        end

        def validate_mortise_against_face(params)
          depth = params.fetch(:mortise_depth)
          model_depth = params[:mortise_model_depth]
          if model_depth&.positive? && depth > model_depth + 0.001
            raise "Chiều sâu mộng âm vượt quá chiều sâu model (mộng #{format_length_mm(depth)} mm, model #{format_length_mm(model_depth)} mm)."
          end

          profile = normalize_profile_points(points_for_dogbone_mortise_profile(params))
          profile_width = profile.map(&:x).max - profile.map(&:x).min
          profile_height = profile.map(&:y).max - profile.map(&:y).min
          offset_x = params.fetch(:mortise_offset_x, 0)
          offset_y = params.fetch(:mortise_offset_y, 0)
          raise 'Khoảng cách từ hai mép mặt không được nhỏ hơn 0.' if offset_x.negative? || offset_y.negative?

          face_width = params[:mortise_face_width]
          face_height = params[:mortise_face_height]
          if face_width&.positive? && offset_x + profile_width > face_width + 0.001
            raise 'Biên dạng dog-bone theo mép X vượt quá mặt đã chọn.'
          end
          if face_height&.positive? && offset_y + profile_height > face_height + 0.001
            raise 'Biên dạng dog-bone theo mép Y vượt quá mặt đã chọn.'
          end
        end

        def tenon_template_origin(params, origin)
          base_origin = Geom::Point3d.new(
            origin.x + tenon_edge_offset(params),
            origin.y + tenon_vertical_inset(params),
            origin.z
          )
          return base_origin unless params[:create_mortise]

          Geom::Point3d.new(
            origin.x + mortise_profile_right_extent(params) + template_gap + tenon_edge_offset(params),
            origin.y + tenon_vertical_inset(params),
            origin.z
          )
        end

        def tenon_layout_width(params)
          effective_tenon_width(params)
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
          tenon_width = effective_tenon_width(params)
          tenon_height = effective_tenon_height(params)
          tenon_origin_x = tenon_template_origin(params, origin).x
          label_origin = Geom::Point3d.new(
            tenon_origin_x + tenon_layout_width(params) + label_gap,
            origin.y - label_gap,
            origin.z + tenon_projection(params)
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
            "Độ vươn mộng dương từ mặt đã chọn: #{format_length_mm(tenon_projection(params))} mm",
            "Chiều cao mộng dương sau độ hở: #{format_length_mm(tenon_height)} mm",
            "Khoảng cách từ mép cạnh: #{format_length_mm(tenon_edge_offset(params))} mm"
          ]
        end

        def validate_tenon_dimensions(width, height, length)
          raise 'Rộng mộng dương sau độ hở phải lớn hơn 0.' unless width.positive?
          raise 'Chiều cao mộng dương sau độ hở phải lớn hơn 0.' unless height.positive?
          raise 'Độ vươn mộng dương từ mặt đã chọn phải lớn hơn 0.' unless length.positive?
        end

        def validate_tenon_clearance(params)
          raise 'Độ hở lắp ráp không được nhỏ hơn 0.' if tenon_clearance(params).negative?
        end

        def validate_tenon_layout(params)
          raise 'Khoảng cách từ mép cạnh không được nhỏ hơn 0.' if tenon_edge_offset(params).negative?

          face_width = params[:tenon_face_width]
          return unless face_width&.positive?

          required_width = tenon_edge_offset(params) + tenon_layout_width(params)
          return if required_width <= face_width + 0.001

          raise "Bố trí mộng dương vượt quá chiều rộng mặt đã chọn (cần #{format_length_mm(required_width)} mm, có #{format_length_mm(face_width)} mm)."
        end

        def validate_tenon_relief_dimensions(width, projection, cutter_radius)
          validate_side_relief_dimensions(width, projection, cutter_radius)
        end

        def add_xz_profile_solid(entities, base_points, thickness)
          base_points = normalize_profile_points(base_points)
          raise 'Không tạo được khối mộng dương.' if base_points.length < 3

          back_points = base_points.map do |point|
            Geom::Point3d.new(point.x, point.y + thickness, point.z)
          end

          face_sets = [
            base_points.reverse,
            back_points
          ]
          base_points.each_index do |index|
            next_index = (index + 1) % base_points.length
            face_sets << [
              base_points[index],
              base_points[next_index],
              back_points[next_index],
              back_points[index]
            ]
          end

          face_sets.each do |face_points|
            face = entities.add_face(face_points)
            raise 'Không tạo được khối mộng dương.' unless face
          end
        end

        def add_negative_z_profile_solid(entities, surface_points, depth)
          surface_points = normalize_profile_points(surface_points)
          raise 'Chiều sâu mộng âm phải lớn hơn 0.' unless depth.positive?
          raise 'Không tạo được khối mộng âm.' if surface_points.length < 3

          recessed_points = surface_points.map do |point|
            Geom::Point3d.new(point.x, point.y, point.z - depth)
          end

          face_sets = [surface_points, recessed_points.reverse]
          surface_points.each_index do |index|
            next_index = (index + 1) % surface_points.length
            face_sets << [
              surface_points[index],
              recessed_points[index],
              recessed_points[next_index],
              surface_points[next_index]
            ]
          end

          face_sets.each do |face_points|
            face = entities.add_face(face_points)
            raise 'Không tạo được khối mộng âm.' unless face
          end
        end

        def side_relief_arc_xz_points(center, radius, start_angle, end_angle)
          sweep = end_angle - start_angle

          (1...DOGBONE_ARC_SEGMENTS).map do |index|
            angle = start_angle + (sweep * index / DOGBONE_ARC_SEGMENTS)
            Geom::Point3d.new(
              center.x + (Math.cos(angle) * radius),
              center.y,
              center.z + (Math.sin(angle) * radius)
            )
          end
        end

        def tenon_profile_points(origin, width, projection, cutter_radius, params)
          return xz_rectangle_points(origin, width, projection) unless params.fetch(:tenon_relief_enabled, true)

          left_center = Geom::Point3d.new(origin.x, origin.y, origin.z + cutter_radius)
          right_x = origin.x + width
          right_center = Geom::Point3d.new(right_x, origin.y, origin.z + cutter_radius)

          points = [Geom::Point3d.new(origin.x, origin.y, origin.z)]
          points.concat(side_relief_arc_xz_points(left_center, cutter_radius, -Math::PI / 2.0, Math::PI / 2.0))
          points << Geom::Point3d.new(origin.x, origin.y, origin.z + (cutter_radius * 2.0))
          points << Geom::Point3d.new(origin.x, origin.y, origin.z + projection)
          points << Geom::Point3d.new(right_x, origin.y, origin.z + projection)
          points << Geom::Point3d.new(right_x, origin.y, origin.z + (cutter_radius * 2.0))
          points.concat(side_relief_arc_xz_points(right_center, cutter_radius, Math::PI / 2.0, Math::PI * 1.5))
          points << Geom::Point3d.new(right_x, origin.y, origin.z)
          remove_duplicate_neighbor_points(points)
        end

        def xz_rectangle_points(origin, width, projection)
          [
            Geom::Point3d.new(origin.x, origin.y, origin.z),
            Geom::Point3d.new(origin.x, origin.y, origin.z + projection),
            Geom::Point3d.new(origin.x + width, origin.y, origin.z + projection),
            Geom::Point3d.new(origin.x + width, origin.y, origin.z)
          ]
        end

        def tenon_edge_offset(params)
          params.fetch(:tenon_edge_offset, 0)
        end

        def validate_side_relief_dimensions(tenon_width, tenon_projection, cutter_radius)
          raise 'Bán kính dao phải lớn hơn 0.' unless cutter_radius.positive?

          minimum_size = cutter_radius * 2.0
          return if tenon_width > minimum_size && tenon_projection > minimum_size

          raise 'Mộng dương quá hẹp hoặc độ vươn quá ngắn để khoét bán nguyệt ở hai vai theo đường kính dao.'
        end

        def effective_tenon_width(params)
          params.fetch(:tenon_width) - tenon_clearance(params)
        end

        def effective_tenon_height(params)
          params.fetch(:tenon_height) - tenon_clearance(params)
        end

        def tenon_vertical_inset(params)
          tenon_clearance(params) / 2.0
        end

        def tenon_clearance(params)
          params.fetch(:clearance, 0)
        end

        def tenon_projection(params)
          params.fetch(:tenon_projection) { params.fetch(:tenon_thickness) }
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
          face = entities.add_face(normalize_profile_points(points))
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

        def normalize_profile_points(points)
          normalized = remove_duplicate_neighbor_points(points)
          normalized.pop if normalized.length > 1 && same_point?(normalized.first, normalized.last)
          normalized
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
          group.entities.each do |entity|
            case entity
            when Sketchup::Face
              entity.material = material
              entity.back_material = material
            when Sketchup::Group
              apply_group_material(entity, material)
            when Sketchup::ComponentInstance
              entity.material = material
              entity.definition.entities.grep(Sketchup::Face).each do |face|
                face.material = material
                face.back_material = material
              end
            end
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
