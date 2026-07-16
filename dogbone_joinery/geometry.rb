# frozen_string_literal: true

# Geometry routines for Dogbone Joinery. The first generator creates standalone
# grouped templates only and does not modify any selected model geometry.

require_relative 'vertical_tbone_geometry'

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
        TENON_UNION_OVERLAP_MM = 0.5
        MORTISE_CUT_OVERLAP_MM = 0.1
        MORTISE_FACE_MATCH_TOLERANCE_MM = 0.01
        BOOLEAN_TRANSFORM_EPSILON = 1.0e-8
        BOOLEAN_ORTHOGONAL_TOLERANCE = 1.0e-6
        BOOLEAN_VOLUME_RELATIVE_TOLERANCE = 1.0e-7
        BOOLEAN_VOLUME_ABSOLUTE_TOLERANCE = 1.0e-9
        BOOLEAN_BOUNDS_TOLERANCE_MM = 0.25
        DOGBONE_ARC_SEGMENTS = 24
        DIAGONAL_CENTER_OFFSET_FACTOR = 0.5
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

        def cut_mortise_into_solid(target, params, origin: Geom::Point3d.new(0, 0, 0), transformation: nil,
                                   manage_operation: true, create_backup: true, parent_entities: nil,
                                   preserve_target_properties: false, normalize_target_scale: false)
          model = Sketchup.active_model
          execute_model_operation(model, 'Cắt mộng âm xương chó vào khối', manage_operation) do
            normalize_solid_scale_for_boolean!(target) if normalize_target_scale
            properties = capture_target_properties(target) if preserve_target_properties
            create_cut_backup(target) if create_backup
            cutter_params, cutter_origin = mortise_cut_geometry(params, origin)
            cutter = create_mortise_cutter(
              cutter_params,
              origin: cutter_origin,
              entities: parent_entities
            )
            cutter.transform!(transformation) if transformation
            unless boolean_solid?(cutter)
              raise 'Khối cắt mộng âm chưa phải solid hợp lệ.'
            end

            protected_siblings = boolean_sibling_snapshot(parent_entities, target, cutter)
            target_contract = boolean_geometry_contract(target)
            target_before = boolean_entity_diagnostic(target)
            cutter_before = boolean_entity_diagnostic(cutter)
            # SketchUp defines the argument as the solid that the receiver is
            # subtracted from, so cutter.subtract(target) produces target-cutter.
            result = cutter.subtract(target)
            unless boolean_solid?(result)
              raise 'SketchUp subtract không trả về solid hợp lệ. ' \
                    "result=#{boolean_entity_diagnostic(result)}; " \
                    "target_before=#{target_before}; cutter_before=#{cutter_before}"
            end
            validate_subtract_contract!(result, target_contract)
            validate_boolean_siblings!(protected_siblings)

            if preserve_target_properties
              result = restore_target_container(result, properties)
              apply_target_properties(result, properties, fallback_name: 'Dogbone_Cut_Result')
            else
              name_boolean_result(result)
            end

            result
          end
        end

        def union_tenons_into_solid(target, params, origin: Geom::Point3d.new(0, 0, 0), transformation: nil,
                                    manage_operation: true, create_backup: true, ensure_unique: true,
                                    update_selection: true, parent_entities: nil,
                                    preserve_target_properties: false,
                                    apply_template_material: true, normalize_target_scale: false)
          model = Sketchup.active_model
          execute_model_operation(model, 'Hợp mộng dương vào chi tiết CNC', manage_operation) do
            raise 'Đối tượng chứa mặt đã chọn không còn hợp lệ.' unless target && target.valid?
            raise 'Đối tượng chứa mặt đã chọn không phải solid hợp lệ.' unless target.manifold?
            raise 'Phiên bản SketchUp này không hỗ trợ phép hợp khối.' unless target.respond_to?(:union)

            target.make_unique if ensure_unique && target.respond_to?(:make_unique)
            normalize_solid_scale_for_boolean!(target) if normalize_target_scale
            original_name = target.respond_to?(:name) ? target.name.to_s : ''
            original_material = target.respond_to?(:material) ? target.material : nil
            original_layer = target.respond_to?(:layer) ? target.layer : nil
            properties = capture_target_properties(target) if preserve_target_properties
            create_tenon_union_backup(
              target,
              original_name,
              parent_entities: parent_entities
            ) if create_backup

            union_params, union_origin = tenon_union_geometry(params, origin)
            tenons = create_tenon_template(
              union_params,
              origin: union_origin,
              entities: parent_entities,
              apply_material: apply_template_material
            )
            tenons.transform!(transformation) if transformation
            raise 'Khối mộng dương tạo ra chưa phải solid hợp lệ.' unless tenons.manifold?

            protected_siblings = boolean_sibling_snapshot(parent_entities, target, tenons)
            target_contract = boolean_geometry_contract(target)
            tenons_contract = boolean_geometry_contract(tenons)
            target_before = boolean_entity_diagnostic(target)
            tenons_before = boolean_entity_diagnostic(tenons)
            union_result = target.union(tenons)
            result = union_result
            outer_shell_result = nil
            if !boolean_solid?(result) && boolean_solid?(target) && boolean_solid?(tenons) &&
               target.respond_to?(:outer_shell)
              outer_shell_result = target.outer_shell(tenons)
              result = outer_shell_result
            end
            unless boolean_solid?(result)
              raise 'SketchUp union/outer_shell không trả về solid hợp lệ. ' \
                    "union_result=#{boolean_entity_diagnostic(union_result)}; " \
                    "outer_shell_result=#{boolean_entity_diagnostic(outer_shell_result)}; " \
                    "target_before=#{target_before}; tenons_before=#{tenons_before}"
            end
            validate_union_contract!(result, target_contract, tenons_contract)
            validate_boolean_siblings!(protected_siblings)

            if preserve_target_properties
              result = restore_target_container(result, properties)
              apply_target_properties(result, properties, fallback_name: 'SonVu_CNC_Tenon_Result')
            else
              result.name = original_name.empty? ? 'SonVu_CNC_Tenon_Result' : original_name if result.respond_to?(:name=)
              result.material = original_material if original_material && result.respond_to?(:material=)
              result.layer = original_layer if original_layer && result.respond_to?(:layer=)
            end
            result.delete_attribute(
              CNCPlugins::ATTRIBUTE_DICTIONARY,
              CNCPlugins::GENERATED_GROUP_ATTRIBUTE
            ) if result.respond_to?(:delete_attribute)

            if update_selection
              model.selection.clear
              model.selection.add(result)
            end
            result
          end
        end

        def execute_model_operation(model, operation_name, manage_operation)
          model.start_operation(operation_name, true) if manage_operation
          result = yield
          model.commit_operation if manage_operation
          result
        rescue StandardError
          model.abort_operation if manage_operation
          raise
        end

        def boolean_solid?(entity)
          entity &&
            (!entity.respond_to?(:valid?) || entity.valid?) &&
            entity.respond_to?(:manifold?) &&
            entity.manifold?
        rescue StandardError
          false
        end

        def boolean_entity_diagnostic(entity)
          return 'nil' unless entity

          values = ["class=#{entity.class}"]
          values << "valid=#{boolean_diagnostic_value(entity, :valid?)}"
          values << "manifold=#{boolean_diagnostic_value(entity, :manifold?)}"
          values << "persistent_id=#{boolean_diagnostic_value(entity, :persistent_id)}"
          values << "volume=#{boolean_volume(entity).inspect}"
          bounds = boolean_bounds_diagnostic(entity)
          values << "bounds=#{bounds}" if bounds
          "{#{values.join(', ')}}"
        rescue StandardError => error
          "{diagnostic_error=#{error.class}: #{error.message}}"
        end

        def boolean_geometry_contract(entity)
          {
            volume: boolean_volume(entity),
            bounds: boolean_bounds_values(entity)
          }
        end

        def boolean_volume(entity)
          return nil unless entity && entity.respond_to?(:volume)

          value = entity.volume
          return nil unless value.is_a?(Numeric)

          value.to_f.abs
        rescue StandardError
          nil
        end

        def boolean_bounds_values(entity)
          return nil unless entity && entity.respond_to?(:bounds)

          bounds = entity.bounds
          minimum = bounds.respond_to?(:min) ? bounds.min : nil
          maximum = bounds.respond_to?(:max) ? bounds.max : nil
          return nil unless minimum && maximum

          {
            min: [minimum.x.to_f, minimum.y.to_f, minimum.z.to_f],
            max: [maximum.x.to_f, maximum.y.to_f, maximum.z.to_f]
          }
        rescue StandardError
          nil
        end

        def validate_union_contract!(result, target_contract, tenons_contract)
          result_contract = boolean_geometry_contract(result)
          target_volume = target_contract[:volume]
          tenons_volume = tenons_contract[:volume]
          result_volume = result_contract[:volume]
          if target_volume && tenons_volume && result_volume
            tolerance = boolean_volume_tolerance(target_volume, tenons_volume, result_volume)
            unless result_volume > target_volume + tolerance &&
                   result_volume + tolerance >= tenons_volume &&
                   result_volume <= target_volume + tenons_volume + tolerance
              raise 'Kết quả hợp mộng dương không bảo toàn thể tích chi tiết gốc.'
            end
          end

          expected_bounds = boolean_union_bounds(target_contract[:bounds], tenons_contract[:bounds])
          unless boolean_bounds_match?(result_contract[:bounds], expected_bounds)
            raise 'Kết quả hợp mộng dương không bảo toàn phạm vi hình học của chi tiết gốc. ' \
                  "expected_bounds=#{expected_bounds.inspect}; " \
                  "result_bounds=#{result_contract[:bounds].inspect}; " \
                  "delta=#{boolean_bounds_delta(result_contract[:bounds], expected_bounds).inspect}"
          end

          result
        end

        def validate_subtract_contract!(result, target_contract)
          result_contract = boolean_geometry_contract(result)
          target_volume = target_contract[:volume]
          result_volume = result_contract[:volume]
          if target_volume && result_volume
            tolerance = boolean_volume_tolerance(target_volume, result_volume)
            unless result_volume.positive? && result_volume < target_volume - tolerance
              raise 'Kết quả cắt mộng âm không làm giảm thể tích chi tiết nhận mộng.'
            end
          end
          unless boolean_bounds_within?(result_contract[:bounds], target_contract[:bounds])
            raise 'Kết quả cắt mộng âm vượt ra ngoài phạm vi chi tiết gốc. ' \
                  "target_bounds=#{target_contract[:bounds].inspect}; " \
                  "result_bounds=#{result_contract[:bounds].inspect}; " \
                  "overflow=#{boolean_bounds_overflow(result_contract[:bounds], target_contract[:bounds]).inspect}"
          end

          result
        end

        def boolean_volume_tolerance(*values)
          maximum = values.compact.map(&:abs).max.to_f
          [maximum * BOOLEAN_VOLUME_RELATIVE_TOLERANCE,
           BOOLEAN_VOLUME_ABSOLUTE_TOLERANCE].max
        end

        def boolean_union_bounds(first, second)
          return nil unless first && second

          {
            min: first[:min].zip(second[:min]).map(&:min),
            max: first[:max].zip(second[:max]).map(&:max)
          }
        end

        def boolean_bounds_match?(actual, expected)
          return true unless actual && expected

          tolerance = boolean_bounds_tolerance
          [:min, :max].all? do |key|
            actual[key].zip(expected[key]).all? do |actual_value, expected_value|
              (actual_value - expected_value).abs <= tolerance
            end
          end
        end

        def boolean_bounds_within?(inner, outer)
          return true unless inner && outer

          tolerance = boolean_bounds_tolerance
          inner[:min].each_index.all? do |index|
            inner[:min][index] >= outer[:min][index] - tolerance &&
              inner[:max][index] <= outer[:max][index] + tolerance
          end
        end

        def boolean_bounds_delta(actual, expected)
          return nil unless actual && expected

          {
            min: actual[:min].zip(expected[:min]).map { |values| values[0] - values[1] },
            max: actual[:max].zip(expected[:max]).map { |values| values[0] - values[1] }
          }
        end

        def boolean_bounds_overflow(inner, outer)
          return nil unless inner && outer

          {
            below_min: inner[:min].zip(outer[:min]).map do |values|
              [values[1] - values[0], 0.0].max
            end,
            above_max: inner[:max].zip(outer[:max]).map do |values|
              [values[0] - values[1], 0.0].max
            end
          }
        end

        def boolean_bounds_tolerance
          CNCPlugins::Units.millimeters_to_model_units(BOOLEAN_BOUNDS_TOLERANCE_MM)
        end

        def boolean_sibling_snapshot(parent_entities, *operands)
          return [] unless parent_entities && parent_entities.respond_to?(:to_a)

          operand_ids = operands.compact.map(&:object_id)
          parent_entities.to_a.reject { |entity| operand_ids.include?(entity.object_id) }
        rescue StandardError
          []
        end

        def validate_boolean_siblings!(siblings)
          removed = siblings.reject do |entity|
            !entity.respond_to?(:valid?) || entity.valid?
          rescue StandardError
            false
          end
          return if removed.empty?

          raise "Phép Boolean đã xóa #{removed.length} đối tượng không phải mục tiêu."
        end

        def boolean_diagnostic_value(entity, method_name)
          return 'unsupported' unless entity.respond_to?(method_name)

          entity.public_send(method_name)
        rescue StandardError => error
          "#{error.class}:#{error.message}"
        end

        def boolean_bounds_diagnostic(entity)
          return nil unless entity.respond_to?(:bounds)

          bounds = entity.bounds
          return nil unless bounds

          minimum = bounds.respond_to?(:min) ? bounds.min : nil
          maximum = bounds.respond_to?(:max) ? bounds.max : nil
          dimensions = [:width, :height, :depth].map do |method_name|
            bounds.respond_to?(method_name) ? bounds.public_send(method_name) : nil
          end
          "min=#{boolean_point_diagnostic(minimum)}, " \
            "max=#{boolean_point_diagnostic(maximum)}, size=#{dimensions.inspect}"
        rescue StandardError => error
          "error=#{error.class}:#{error.message}"
        end

        def boolean_point_diagnostic(point)
          return nil unless point

          [point.x, point.y, point.z]
        rescue StandardError
          point.to_s
        end

        def normalize_solid_scale_for_boolean!(target)
          transformation = target.respond_to?(:transformation) ? target.transformation : nil
          return target unless transformation

          axes = transformation_axes(transformation)
          return target unless scale_normalization_required?(axes)

          normalized_axes = axes.map { |axis| normalized_boolean_axis(axis) }
          validate_orthogonal_boolean_axes!(normalized_axes)
          rigid = Geom::Transformation.axes(
            transformation.origin,
            normalized_axes[0],
            normalized_axes[1],
            normalized_axes[2]
          )
          local_bake = rigid.inverse * transformation
          entities = target_geometry_entities(target)
          content = entities.to_a
          transformed = entities.transform_entities(local_bake, content)
          if !content.empty? && transformed == false
            raise 'Không thể đưa tỷ lệ instance vào hình học trước phép Boolean.'
          end
          unless target.respond_to?(:transformation=)
            raise 'Không thể chuẩn hóa transformation của solid trước phép Boolean.'
          end

          target.transformation = rigid
          unless boolean_solid?(target)
            raise 'Solid không còn hợp lệ sau khi chuẩn hóa tỷ lệ instance.'
          end

          target
        end

        def transformation_axes(transformation)
          axes = [:xaxis, :yaxis, :zaxis].map do |method_name|
            unless transformation.respond_to?(method_name)
              raise 'Không đọc được các trục transformation của solid.'
            end

            transformation.public_send(method_name)
          end
          if axes.any? { |axis| boolean_axis_length(axis) <= BOOLEAN_TRANSFORM_EPSILON }
            raise 'Transformation của solid có trục tỷ lệ bằng 0.'
          end

          axes
        end

        def scale_normalization_required?(axes)
          axes.any? { |axis| (boolean_axis_length(axis) - 1.0).abs > BOOLEAN_TRANSFORM_EPSILON }
        end

        def normalized_boolean_axis(axis)
          length = boolean_axis_length(axis)
          Geom::Vector3d.new(axis.x / length, axis.y / length, axis.z / length)
        end

        def validate_orthogonal_boolean_axes!(axes)
          pairs = [[axes[0], axes[1]], [axes[0], axes[2]], [axes[1], axes[2]]]
          return if pairs.all? { |first, second| boolean_axis_dot(first, second).abs <= BOOLEAN_ORTHOGONAL_TOLERANCE }

          raise 'Transformation của solid có shear nên không thể chuẩn hóa an toàn cho phép Boolean.'
        end

        def target_geometry_entities(target)
          return target.entities if target.respond_to?(:entities)

          definition = target.respond_to?(:definition) ? target.definition : nil
          return definition.entities if definition && definition.respond_to?(:entities)

          raise 'Không tìm thấy hình học bên trong solid để chuẩn hóa tỷ lệ.'
        end

        def boolean_axis_length(axis)
          Math.sqrt((axis.x * axis.x) + (axis.y * axis.y) + (axis.z * axis.z))
        end

        def boolean_axis_dot(first, second)
          (first.x * second.x) + (first.y * second.y) + (first.z * second.z)
        end

        def capture_target_properties(target)
          definition = target.respond_to?(:definition) ? target.definition : nil
          {
            name: target.respond_to?(:name) ? target.name.to_s : '',
            material: target.respond_to?(:material) ? target.material : nil,
            layer: target.respond_to?(:layer) ? target.layer : nil,
            container_kind: component_instance_target?(target) ? :component_instance : :group,
            definition_name: definition && definition.respond_to?(:name) ? definition.name.to_s : '',
            entity_attributes: capture_attributes(target),
            definition_attributes: capture_attributes(definition)
          }
        end

        def restore_target_container(result, properties)
          return result unless properties[:container_kind] == :component_instance
          return result if component_instance_target?(result)
          unless result.respond_to?(:to_component)
            raise 'Không thể khôi phục loại ComponentInstance sau phép Boolean.'
          end

          converted = result.to_component
          unless converted && (!converted.respond_to?(:valid?) || converted.valid?)
            raise 'Không thể khôi phục ComponentInstance sau phép Boolean.'
          end
          converted
        end

        def component_instance_target?(entity)
          entity && entity.respond_to?(:definition) && !entity.respond_to?(:entities)
        end

        def apply_target_properties(result, properties, fallback_name:)
          name = properties[:name].to_s
          result.name = name.empty? ? fallback_name : name if result.respond_to?(:name=)
          if properties[:material] && result.respond_to?(:material=)
            result.material = properties[:material]
          end
          result.layer = properties[:layer] if properties[:layer] && result.respond_to?(:layer=)
          apply_attributes(result, properties[:entity_attributes])
          definition = result.respond_to?(:definition) ? result.definition : nil
          if definition && definition.respond_to?(:name=) && !properties[:definition_name].to_s.empty?
            definition.name = properties[:definition_name]
          end
          apply_attributes(definition, properties[:definition_attributes])
          result
        end

        def capture_attributes(entity)
          return {} unless entity && entity.respond_to?(:attribute_dictionaries)

          dictionaries = entity.attribute_dictionaries
          return {} unless dictionaries

          dictionaries.each_with_object({}) do |dictionary, result|
            values = {}
            dictionary.each_pair { |key, value| values[key.to_s] = value }
            result[dictionary.name.to_s] = values
          end
        end

        def apply_attributes(entity, dictionaries)
          return unless entity && entity.respond_to?(:set_attribute)

          dictionaries.to_h.each do |dictionary_name, values|
            values.each do |key, value|
              entity.set_attribute(dictionary_name, key, value)
            end
          end
        end

        def create_tenon_union_backup(target, original_name, parent_entities: nil)
          backup = if target.respond_to?(:copy)
                     target.copy
                   elsif target.respond_to?(:definition) && target.respond_to?(:transformation)
                     entities = parent_entities || Sketchup.active_model.active_entities
                     entities.add_instance(target.definition, target.transformation)
                   else
                     raise 'Không thể tạo bản sao lưu cho group/component chứa mặt đã chọn.'
                   end

          backup.make_unique if backup.respond_to?(:make_unique)
          backup.name = "SonVu_Backup_#{original_name.empty? ? 'ChiTietCNC' : original_name}" if backup.respond_to?(:name=)
          backup.material = target.material if target.respond_to?(:material) && backup.respond_to?(:material=)
          backup.layer = target.layer if target.respond_to?(:layer) && backup.respond_to?(:layer=)
          backup.hidden = true if backup.respond_to?(:hidden=)
          backup.set_attribute(
            CNCPlugins::ATTRIBUTE_DICTIONARY,
            'tenon_union_backup',
            true
          ) if backup.respond_to?(:set_attribute)
          backup
        end

        def tenon_union_geometry(params, origin)
          overlap = CNCPlugins::Units.millimeters_to_model_units(TENON_UNION_OVERLAP_MM)
          union_params = params.merge(tenon_projection: tenon_projection(params) + overlap)
          union_origin = Geom::Point3d.new(origin.x, origin.y, origin.z - overlap)
          [union_params, union_origin]
        end

        def mortise_cut_geometry(params, origin)
          overlap = CNCPlugins::Units.millimeters_to_model_units(MORTISE_CUT_OVERLAP_MM)
          cutter_params = params.merge(mortise_depth: params.fetch(:mortise_depth) + overlap)
          if mortise_spans_face_height?(params)
            cutter_params[:mortise_height] = params.fetch(:mortise_height) + (overlap * 2.0)
          end
          if params[:mortise_model_depth]
            cutter_params[:mortise_model_depth] = params[:mortise_model_depth] + overlap
          end
          cutter_origin = Geom::Point3d.new(origin.x, origin.y, origin.z + overlap)
          [cutter_params, cutter_origin]
        end

        def mortise_spans_face_height?(params)
          mortise_height = params[:mortise_height]
          face_height = params[:mortise_face_height]
          return false unless mortise_height&.positive? && face_height&.positive?

          tolerance = CNCPlugins::Units.millimeters_to_model_units(
            MORTISE_FACE_MATCH_TOLERANCE_MM
          )
          (mortise_height - face_height).abs <= tolerance
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

        def create_mortise_template(params, origin: Geom::Point3d.new(0, 0, 0), entities: nil)
          validate_mortise_against_face(params)
          group = (entities || Sketchup.active_model.active_entities).add_group
          group.name = MORTISE_GROUP_NAME

          points = centered_mortise_profile_points(params, origin)
          add_negative_z_profile_solid(group.entities, points, params.fetch(:mortise_depth))

          apply_group_material(group, mortise_material)
          mark_generated_group(group)
          group
        end

        def create_mortise_cutter(params, origin: Geom::Point3d.new(0, 0, 0), entities: nil)
          validate_mortise_against_face(params)
          group = (entities || Sketchup.active_model.active_entities).add_group
          group.name = MORTISE_CUTTER_GROUP_NAME

          points = centered_mortise_profile_points(params, origin)
          add_negative_z_profile_solid(group.entities, points, params.fetch(:mortise_depth))

          group
        end

        def create_tenon_template(params, origin: Geom::Point3d.new(0, 0, 0), entities: nil,
                                  apply_material: true)
          tenon_width = effective_tenon_width(params)
          tenon_height = effective_tenon_height(params)
          tenon_projection = tenon_projection(params)
          cutter_radius = tenon_cutter_radius(params)

          validate_tenon_clearance(params)
          validate_tenon_dimensions(tenon_width, tenon_height, tenon_projection)
          validate_tenon_layout(params)
          validate_tenon_relief_dimensions(tenon_width, tenon_projection, cutter_radius) if params.fetch(:tenon_relief_enabled, true)

          tenon_origin = tenon_template_origin(params, origin)

          group = (entities || Sketchup.active_model.active_entities).add_group
          group.name = TENON_GROUP_NAME

          tenon_origins(params, tenon_origin).each do |current_origin|
            profile = tenon_profile_points(current_origin, tenon_width, tenon_projection, cutter_radius, params)
            add_xz_profile_solid(group.entities, profile, tenon_height)
          end

          apply_group_material(group, tenon_material) if apply_material
          mark_generated_group(group)
          group
        end

        def centered_mortise_profile_points(params, origin = Geom::Point3d.new(0, 0, 0))
          profile = normalize_profile_points(points_for_dogbone_mortise_profile(params))
          min_x = profile.map(&:x).min
          max_x = profile.map(&:x).max
          min_y = profile.map(&:y).min
          max_y = profile.map(&:y).max
          center_x = (min_x + max_x) / 2.0
          center_y = (min_y + max_y) / 2.0
          translation = Geom::Point3d.new(origin.x - center_x, origin.y - center_y, origin.z)
          translate_points(profile, translation)
        end

        def validate_mortise_against_face(params)
          depth = params.fetch(:mortise_depth)
          model_depth = params[:mortise_model_depth]
          if model_depth&.positive? && depth > model_depth + 0.001
            raise "Chiều sâu mộng âm vượt quá chiều sâu model (mộng #{format_length_mm(depth)} mm, model #{format_length_mm(model_depth)} mm)."
          end

          nil
        end

        def tenon_template_origin(params, origin)
          base_origin = Geom::Point3d.new(
            origin.x + tenon_first_offset(params),
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
          (effective_tenon_width(params) * tenon_count(params)) +
            (tenon_gap(params) * (tenon_count(params) - 1))
        end

        def tenon_origins(params, origin)
          pitch = effective_tenon_width(params) + tenon_gap(params)
          (0...tenon_count(params)).map do |index|
            Geom::Point3d.new(origin.x + (index * pitch), origin.y, origin.z)
          end
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
            "Bán kính dao: #{format_length_mm(mortise_cutter_radius(params))} mm",
            "Độ hở lắp ráp: #{format_length_mm(params.fetch(:clearance))} mm"
          ]
        end

        def tenon_label_lines(tenon_width, tenon_height, params)
          [
            "Rộng mộng dương: #{format_length_mm(tenon_width)} mm",
            "Độ vươn mộng dương từ mặt đã chọn: #{format_length_mm(tenon_projection(params))} mm",
            "Chiều cao mộng dương sau độ hở: #{format_length_mm(tenon_height)} mm",
            "Bán kính dao: #{format_length_mm(tenon_cutter_radius(params))} mm",
            "Số lượng mộng dương: #{tenon_count(params)}",
            "Lề hai đầu cạnh: #{format_length_mm(tenon_edge_offset(params))} mm",
            "Khoảng cách trống tự động: #{format_length_mm(tenon_gap(params))} mm"
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
          raise 'Số lượng mộng dương phải lớn hơn 0.' unless tenon_count(params).positive?
          raise 'Lề hai đầu cạnh không được nhỏ hơn 0.' if tenon_edge_offset(params).negative?

          face_width = params[:tenon_face_width]
          if tenon_count(params) > 1 && !face_width&.positive?
            raise 'Không đọc được chiều rộng mặt để phân bố nhiều mộng dương.'
          end
          return unless face_width&.positive?

          required_width = if tenon_count(params) == 1
                             effective_tenon_width(params)
                           else
                             (tenon_edge_offset(params) * 2.0) +
                               (effective_tenon_width(params) * tenon_count(params))
                           end
          return if required_width <= face_width + 0.001

          raise "Bố trí mộng dương vượt quá chiều rộng mặt đã chọn (cần tối thiểu #{format_length_mm(required_width)} mm, có #{format_length_mm(face_width)} mm)."
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

        def tenon_count(params)
          params.fetch(:tenon_count, 1).to_i
        end

        def tenon_first_offset(params)
          face_width = params[:tenon_face_width]
          return tenon_edge_offset(params) unless tenon_count(params) == 1 && face_width&.positive?

          (face_width - effective_tenon_width(params)) / 2.0
        end

        def tenon_gap(params)
          return 0 if tenon_count(params) <= 1

          face_width = params[:tenon_face_width]
          return 0 unless face_width&.positive?

          available = face_width - (tenon_edge_offset(params) * 2.0)
          (available - (effective_tenon_width(params) * tenon_count(params))) /
            (tenon_count(params) - 1)
        end

        def validate_side_relief_dimensions(tenon_width, tenon_projection, cutter_radius)
          raise 'Bán kính dao phải lớn hơn 0.' unless cutter_radius.positive?

          minimum_size = cutter_radius * 2.0
          return if tenon_width > minimum_size && tenon_projection > minimum_size

          raise 'Mộng dương quá hẹp hoặc độ vươn quá ngắn để khoét bán nguyệt ở hai vai theo bán kính dao.'
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

        def tenon_cutter_radius(params)
          params.fetch(:tenon_cutter_radius) do
            params.fetch(:cutter_radius) { params.fetch(:cutter_diameter) / 2.0 }
          end
        end

        def mortise_cutter_radius(params)
          params.fetch(:cutter_radius) { params.fetch(:cutter_diameter) / 2.0 }
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
          radius = mortise_cutter_radius(params)
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
          radius = mortise_cutter_radius(params)
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
          radius = mortise_cutter_radius(params)
          centers = VerticalTBoneGeometry.relief_centers(
            width: width,
            height: height,
            radius: radius
          )

          # Vertical T-bone geometry moves each cutter center vertically outward
          # from the corner. Bottom reliefs extend toward negative Y, and top
          # reliefs extend toward positive Y.
          points_for_relief_centers(
            width: width,
            height: height,
            radius: radius,
            centers: {
              bottom_left: geom_point_from_xy(centers.fetch(:bottom_left)),
              bottom_right: geom_point_from_xy(centers.fetch(:bottom_right)),
              top_right: geom_point_from_xy(centers.fetch(:top_right)),
              top_left: geom_point_from_xy(centers.fetch(:top_left))
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
          VerticalTBoneGeometry.center_offset(radius)
        end

        def geom_point_from_xy(values)
          Geom::Point3d.new(values[0], values[1], 0)
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
