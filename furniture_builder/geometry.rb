# frozen_string_literal: true

require 'json'
require 'securerandom'

# SketchUp entity generation for furniture carcasses, Phase 2A fronts, and
# Phase 2B drawer boxes, and Phase 2C hardware templates. Every public mutation
# is atomic and only rebuilds groups tagged by this feature.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Geometry
        CABINET_ATTRIBUTE = 'furniture_cabinet'
        PANEL_ATTRIBUTE = 'furniture_panel'
        SETTINGS_ATTRIBUTE = 'furniture_settings_json'
        CABINET_ID_ATTRIBUTE = 'furniture_cabinet_id'
        DEFINITION_PREFIX = 'SV Nội thất'
        DEFAULT_MATERIAL_COLOR = [205, 180, 140].freeze
        DEFAULT_FRONT_MATERIAL_COLOR = [224, 220, 210].freeze
        DEFAULT_DRAWER_MATERIAL_COLOR = [190, 170, 145].freeze
        DEFAULT_HARDWARE_MATERIAL_COLOR = [115, 120, 125].freeze

        module_function

        def create(settings, transformation: nil)
          normalized = validated_settings(settings)
          model = Sketchup.active_model
          model.start_operation('Tạo tủ nội thất SonVu', true)
          begin
            group = model.active_entities.add_group
            group.transformation = transformation if transformation
            build_group(group, normalized, SecureRandom.uuid)
            model.selection.clear
            model.selection.add(group)
            model.commit_operation
            group
          rescue StandardError
            model.abort_operation
            raise
          end
        end

        def rebuild(group, settings)
          raise ArgumentError, 'Đối tượng đã chọn không phải tủ nội thất do SonVu tạo.' unless editable_group?(group)

          normalized = validated_settings(settings)
          model = Sketchup.active_model
          model.start_operation('Cập nhật tủ nội thất SonVu', true)
          begin
            cabinet_id = group.get_attribute(
              CNCPlugins::ATTRIBUTE_DICTIONARY,
              CABINET_ID_ATTRIBUTE,
              SecureRandom.uuid
            )
            remove_existing_panels(group, model)
            build_group(group, normalized, cabinet_id)
            model.selection.clear
            model.selection.add(group)
            model.commit_operation
            group
          rescue StandardError
            model.abort_operation
            raise
          end
        end

        def build_group(group, settings, cabinet_id)
          parts = Specification.parts(settings)
          materials = {
            'carcass' => find_or_create_material(settings[:material_name], DEFAULT_MATERIAL_COLOR)
          }
          if parts.any? { |part| part.kind == 'front' }
            materials['front'] = find_or_create_material(
              settings[:front_material_name],
              DEFAULT_FRONT_MATERIAL_COLOR
            )
          end
          if parts.any? { |part| part.kind == 'drawer_box' }
            materials['drawer_box'] = find_or_create_material(
              settings[:drawer_material_name],
              DEFAULT_DRAWER_MATERIAL_COLOR
            )
          end
          if parts.any? { |part| part.kind == 'hardware' }
            materials['hardware'] = find_or_create_material(
              settings[:hardware_material_name],
              DEFAULT_HARDWARE_MATERIAL_COLOR
            )
          end
          group.name = cabinet_group_name(settings)
          write_cabinet_attributes(group, settings, cabinet_id)

          parts.each do |part|
            add_panel_component(group, part, settings, cabinet_id, materials.fetch(part.kind))
          end
          group
        end

        def editable_group?(entity)
          return false unless entity.respond_to?(:get_attribute)

          entity.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, CABINET_ATTRIBUTE, false) == true
        end

        def settings_from_group(group)
          return nil unless editable_group?(group)

          payload = group.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, SETTINGS_ATTRIBUTE, '').to_s
          return nil if payload.empty?

          Specification.normalize(JSON.parse(payload))
        rescue JSON::ParserError
          nil
        end

        def cabinet_group_name(settings)
          format(
            'SV - %<name>s - %<width>g×%<height>g×%<depth>g mm',
            name: settings[:cabinet_name],
            width: settings[:width_mm],
            height: settings[:height_mm],
            depth: settings[:depth_mm]
          )
        end

        def write_cabinet_attributes(group, settings, cabinet_id)
          dictionary = CNCPlugins::ATTRIBUTE_DICTIONARY
          group.set_attribute(dictionary, CABINET_ATTRIBUTE, true)
          group.set_attribute(dictionary, CABINET_ID_ATTRIBUTE, cabinet_id)
          group.set_attribute(dictionary, SETTINGS_ATTRIBUTE, JSON.generate(settings))
          group.set_attribute(dictionary, 'furniture_preset', settings[:preset_key])
          group.set_attribute(dictionary, 'furniture_name_vi', settings[:cabinet_name])
          group.set_attribute(dictionary, 'furniture_width_mm', settings[:width_mm])
          group.set_attribute(dictionary, 'furniture_height_mm', settings[:height_mm])
          group.set_attribute(dictionary, 'furniture_depth_mm', settings[:depth_mm])
          group.set_attribute(dictionary, 'furniture_material', settings[:material_name])
          group.set_attribute(dictionary, 'furniture_front_layout', settings[:front_layout])
          group.set_attribute(dictionary, 'furniture_front_cover_mode', settings[:front_cover_mode])
          group.set_attribute(dictionary, 'furniture_front_material', settings[:front_material_name])
          group.set_attribute(dictionary, 'furniture_include_drawer_boxes', settings[:include_drawer_boxes])
          group.set_attribute(dictionary, 'furniture_drawer_material', settings[:drawer_material_name])
          group.set_attribute(dictionary, 'furniture_include_handles', settings[:include_handles])
          group.set_attribute(dictionary, 'furniture_include_hinges', settings[:include_hinges])
          group.set_attribute(dictionary, 'furniture_include_drawer_slides', settings[:include_drawer_slides])
          group.set_attribute(dictionary, 'furniture_hardware_material', settings[:hardware_material_name])
        end

        def add_panel_component(group, part, settings, cabinet_id, material)
          model = Sketchup.active_model
          definition_name = unique_definition_name(cabinet_id, part)
          definition = model.definitions.add(definition_name)
          if part.shape == 'cylinder_y'
            add_cylinder_y(definition.entities, mm(part.size_x), mm(part.size_y))
          else
            add_box(
              definition.entities,
              mm(part.size_x),
              mm(part.size_y),
              mm(part.size_z)
            )
          end

          transformation = Geom::Transformation.translation(
            Geom::Vector3d.new(mm(part.x), mm(part.y), mm(part.z))
          )
          instance = group.entities.add_instance(definition, transformation)
          instance.name = part.name
          instance.material = material if material
          write_panel_attributes(instance, definition, part, settings, cabinet_id)
          instance
        end

        def add_box(entities, size_x, size_y, size_z)
          points = [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(size_x, 0, 0),
            Geom::Point3d.new(size_x, size_y, 0),
            Geom::Point3d.new(0, size_y, 0),
            Geom::Point3d.new(0, 0, size_z),
            Geom::Point3d.new(size_x, 0, size_z),
            Geom::Point3d.new(size_x, size_y, size_z),
            Geom::Point3d.new(0, size_y, size_z)
          ]
          loops = [
            [0, 3, 2, 1],
            [4, 5, 6, 7],
            [0, 1, 5, 4],
            [1, 2, 6, 5],
            [2, 3, 7, 6],
            [3, 0, 4, 7]
          ]
          faces = loops.map { |indices| entities.add_face(indices.map { |index| points[index] }) }
          raise 'Không tạo được hình học tấm ván.' if faces.any?(&:nil?)

          faces
        end

        def add_cylinder_y(entities, diameter, depth, segments = 24)
          raise ArgumentError, 'Số đoạn tròn phải từ 8 trở lên.' if segments < 8

          radius = diameter / 2.0
          front = segments.times.map do |index|
            angle = (2.0 * Math::PI * index) / segments
            Geom::Point3d.new(radius + (Math.cos(angle) * radius), 0, radius + (Math.sin(angle) * radius))
          end
          back = front.map { |point| Geom::Point3d.new(point.x, depth, point.z) }
          faces = [entities.add_face(front.reverse), entities.add_face(back)]
          segments.times do |index|
            next_index = (index + 1) % segments
            faces << entities.add_face([front[index], front[next_index], back[next_index], back[index]])
          end
          raise 'Không tạo được hình học phụ kiện tròn.' if faces.any?(&:nil?)

          faces
        end

        def write_panel_attributes(instance, definition, part, settings, cabinet_id)
          attributes = {
            PANEL_ATTRIBUTE => true,
            CABINET_ID_ATTRIBUTE => cabinet_id,
            'part_key' => part.key,
            'part_name_vi' => part.name,
            'part_role' => part.role,
            'part_kind' => part.kind,
            'material_name' => part.material_name || settings[:material_name],
            'finished_length_mm' => rounded_mm(part.finished_length),
            'finished_width_mm' => rounded_mm(part.finished_width),
            'thickness_mm' => rounded_mm(part.thickness),
            'grain_direction' => part.grain_direction,
            'grain_axis' => part.grain_axis,
            'geometry_shape' => part.shape,
            'edge_band_front' => part.edge_banding[:front],
            'edge_band_back' => part.edge_banding[:back],
            'edge_band_left' => part.edge_banding[:left],
            'edge_band_right' => part.edge_banding[:right]
          }
          attributes['drawer_index'] = part.assembly_index if part.assembly_index
          attributes['owner_part_key'] = part.owner_part_key if part.owner_part_key
          attributes['hardware_type'] = part.role if part.kind == 'hardware'
          attributes.each do |key, value|
            instance.set_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, key, value)
            definition.set_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, key, value)
          end
        end

        def remove_existing_panels(group, model)
          panel_instances = group.entities.grep(Sketchup::ComponentInstance).select do |instance|
            instance.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, PANEL_ATTRIBUTE, false)
          end
          definitions = panel_instances.map(&:definition)
          panel_instances.each { |instance| instance.erase! if instance.valid? }
          definitions.uniq.each do |definition|
            next unless definition.respond_to?(:instances) && definition.instances.empty?
            next unless model.definitions.respond_to?(:remove)

            model.definitions.remove(definition)
          rescue StandardError
            # An unused plugin-owned definition is harmless if SketchUp keeps it.
          end
        end

        def find_or_create_material(name, default_color)
          model = Sketchup.active_model
          material = model.materials[name]
          return material if material

          material = model.materials.add(name)
          material.color = Sketchup::Color.new(*default_color)
          material
        end

        def unique_definition_name(cabinet_id, part)
          short_id = cabinet_id.to_s.delete('-')[0, 8]
          "#{DEFINITION_PREFIX} - #{short_id} - #{part.name}"
        end

        def validated_settings(settings)
          normalized = Specification.normalize(settings)
          error = Specification.validate(normalized)
          raise ArgumentError, error if error

          normalized
        end

        def mm(value)
          CNCPlugins::Units.millimeters_to_model_units(value)
        end

        def rounded_mm(value)
          value.to_f.round(3)
        end
      end
    end
  end
end
