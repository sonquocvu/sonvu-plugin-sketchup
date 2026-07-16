# frozen_string_literal: true

# Read-only SketchUp adapter. It extracts world-space descriptors from selected
# Groups and ComponentInstances without opening an operation or writing data.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class SketchupBoardScanner
          attr_reader :skipped_entities, :entity_by_part_id, :entity_paths_by_part_id,
                      :transform_snapshots_by_part_id

          def initialize(attribute_dictionary: CNCPlugins::ATTRIBUTE_DICTIONARY)
            @attribute_dictionary = attribute_dictionary
            @skipped_entities = []
            @entity_by_part_id = {}
            @entity_paths_by_part_id = {}
            @transform_snapshots_by_part_id = {}
          end

          def scan(candidate_entities, parent_transform: Transform3.identity, parent_path: [])
            @skipped_entities = []
            @entity_by_part_id = {}
            @entity_paths_by_part_id = {}
            @transform_snapshots_by_part_id = {}
            descriptors = []
            candidate_entities.to_a.each do |entity|
              scan_entity(entity, parent_transform, parent_path, descriptors, [])
            end
            unique = {}
            descriptors.each { |descriptor| unique[descriptor.identity.stable_id] ||= descriptor }
            unique.values
          end

          private

          def scan_entity(entity, parent_transform, parent_path, descriptors, entity_path)
            return unless board_candidate_entity?(entity)
            return unless visible_and_valid?(entity)

            entity_id = persistent_identity(entity)
            current_path = parent_path + [entity_id]
            current_entity_path = entity_path + [entity]
            world_transform = parent_transform * entity_transform(entity)
            faces = direct_faces(entity)
            if faces.empty?
              child_entities(entity).each do |child|
                scan_entity(child, world_transform, current_path, descriptors, current_entity_path)
              end
              return
            end

            identity = build_part_identity(entity, current_path)
            face_descriptors = faces.map do |face|
              build_face_descriptor(face, identity, world_transform)
            end.compact
            if face_descriptors.length < 4
              @skipped_entities << { entity_id: identity.stable_id, reason: 'insufficient_faces' }.freeze
              return
            end

            tolerance = 1.0e-6
            descriptor = BoardDescriptor.infer(
              identity: identity,
              faces: face_descriptors,
              tolerance: tolerance,
              source_data: source_data(entity)
            )
            descriptors << descriptor
            @entity_by_part_id[identity.stable_id] = entity
            @entity_paths_by_part_id[identity.stable_id] = current_entity_path.freeze
            @transform_snapshots_by_part_id[identity.stable_id] = current_entity_path.map do |path_entity|
              entity_transform(path_entity).values
            end.freeze
          rescue StandardError => error
            @skipped_entities << {
              entity_id: entity_id || fallback_object_id(entity),
              reason: 'descriptor_error',
              error_class: error.class.name,
              message: error.message
            }.freeze
          end

          def board_candidate_entity?(entity)
            return true if defined?(Sketchup::Group) && entity.is_a?(Sketchup::Group)
            return true if defined?(Sketchup::ComponentInstance) && entity.is_a?(Sketchup::ComponentInstance)

            %w[Group ComponentInstance].include?(entity.class.name.split('::').last)
          end

          def face_entity?(entity)
            return entity.is_a?(Sketchup::Face) if defined?(Sketchup::Face)

            entity.class.name.split('::').last == 'Face'
          end

          def visible_and_valid?(entity)
            return false if entity.respond_to?(:valid?) && !entity.valid?
            return false if entity.respond_to?(:hidden?) && entity.hidden?
            return false if entity.respond_to?(:visible?) && !entity.visible?
            return false if entity.respond_to?(:layer) && entity.layer &&
              entity.layer.respond_to?(:visible?) && !entity.layer.visible?

            true
          end

          def child_entities(entity)
            container_entities(entity).to_a.select { |child| board_candidate_entity?(child) }
          end

          def direct_faces(entity)
            container_entities(entity).to_a.select do |child|
              face_entity?(child) && visible_and_valid?(child)
            end
          end

          def container_entities(entity)
            return entity.entities if entity.respond_to?(:entities)
            return entity.definition.entities if entity.respond_to?(:definition) && entity.definition.respond_to?(:entities)

            []
          end

          def entity_transform(entity)
            transformation = entity.respond_to?(:transformation) ? entity.transformation : nil
            Transform3.from_sketchup(transformation)
          end

          def build_part_identity(entity, path)
            definition = entity.respond_to?(:definition) ? entity.definition : nil
            persistent_id = entity.respond_to?(:persistent_id) ? entity.persistent_id : nil
            definition_id = definition && definition.respond_to?(:persistent_id) ? definition.persistent_id : nil
            stable_id = "part:#{path.join('/')}"
            PartIdentity.new(
              stable_id: stable_id,
              persistent_id: persistent_id,
              definition_id: definition_id,
              instance_path: path,
              display_name: display_name(entity, definition),
              role_metadata: attribute_value(entity, definition, 'part_role')
            )
          end

          def build_face_descriptor(face, identity, world_transform)
            loop = face.respond_to?(:outer_loop) ? face.outer_loop : nil
            vertices = loop && loop.respond_to?(:vertices) ? loop.vertices : face.vertices
            points = vertices.map do |vertex|
              position = vertex.respond_to?(:position) ? vertex.position : vertex
              world_transform.apply_point(Point3.new(position.x, position.y, position.z))
            end
            FaceDescriptor.new(
              stable_id: "#{identity.stable_id}:face:#{persistent_identity(face)}",
              board_identity: identity,
              vertices: points,
              kind: 'unknown'
            )
          rescue ArgumentError
            nil
          end

          def source_data(entity)
            definition = entity.respond_to?(:definition) ? entity.definition : nil
            {
              part_key: attribute_value(entity, definition, 'part_key'),
              part_kind: attribute_value(entity, definition, 'part_kind'),
              furniture_panel: attribute_value(entity, definition, 'furniture_panel') == true
            }
          end

          def attribute_value(entity, definition, key)
            value = read_attribute(entity, key)
            value.nil? ? read_attribute(definition, key) : value
          end

          def read_attribute(entity, key)
            return nil unless entity && entity.respond_to?(:get_attribute)

            entity.get_attribute(@attribute_dictionary, key, nil)
          end

          def display_name(entity, definition)
            name = entity.respond_to?(:name) ? entity.name.to_s.strip : ''
            name = definition.name.to_s.strip if name.empty? && definition && definition.respond_to?(:name)
            name
          end

          def persistent_identity(entity)
            return entity.persistent_id.to_s if entity.respond_to?(:persistent_id)
            return entity.entityID.to_s if entity.respond_to?(:entityID)

            fallback_object_id(entity)
          end

          def fallback_object_id(entity)
            "object-#{entity.object_id}"
          end
        end

        class SketchupAnalyzer
          attr_reader :scanner

          def initialize(scanner: SketchupBoardScanner.new, analyzer: Analyzer.new)
            @scanner = scanner
            @analyzer = analyzer
          end

          def analyze(candidate_entities, specification, active_path: nil)
            parent_transform, parent_path = active_context(active_path)
            descriptors = scanner.scan(
              candidate_entities,
              parent_transform: parent_transform,
              parent_path: parent_path
            )
            @analyzer.analyze(descriptors, specification)
          end

          private

          def active_context(active_path)
            transform = Transform3.identity
            path = []
            active_path.to_a.each do |entity|
              transform = transform * Transform3.from_sketchup(entity.transformation)
              path << if entity.respond_to?(:persistent_id)
                        entity.persistent_id.to_s
                      else
                        "object-#{entity.object_id}"
                      end
            end
            [transform, path]
          end
        end
      end
    end
  end
end
