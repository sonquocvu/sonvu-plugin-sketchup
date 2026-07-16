# frozen_string_literal: true

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticExecution
        class EntityUniquenessContext
          def initialize
            @current_by_original_object_id = {}
          end

          def current(original)
            @current_by_original_object_id[original.object_id]
          end

          def record(original, current)
            @current_by_original_object_id[original.object_id] = current
          end
        end

        class ExecutionEntityReference
          attr_reader :identity, :original_path, :active_path, :entity

          def initialize(identity:, entity:, path:, transform_snapshots:,
                         active_path:, active_path_snapshot:)
            @identity = identity
            @entity = entity
            @original_path = path.freeze
            @transform_snapshots = transform_snapshots.freeze
            @active_path = active_path.freeze
            @active_path_snapshot = active_path_snapshot.freeze
            @original_full_path = (@active_path + @original_path).freeze
            @full_transform_snapshots = (@active_path_snapshot + @transform_snapshots).freeze
            @route_indices = build_route_indices
            @current_full_path = @original_full_path.dup
          end

          def validate!
            unless entity && original_path.last.equal?(entity) && valid_entity?(entity)
              fail_integrity('referenced_entity_invalid')
            end
            validate_identity!
            validate_transform_path!(@original_full_path, @full_transform_snapshots)
            parent_world_transform.inverse
            validate_uniqueness_capability!
            true
          end

          def validate_boolean_capability!(role)
            unless entity.respond_to?(:manifold?) && entity.manifold?
              fail_integrity('target_not_solid', role: role)
            end
            method_name = role.to_sym == :male ? :union : :subtract
            fail_integrity('boolean_not_supported', role: role) unless entity.respond_to?(method_name)
          end

          def ensure_unique!(context)
            current_path = []
            @original_full_path.each_with_index do |original, index|
              current = context.current(original)
              unless current
                current = if index.zero?
                            original
                          else
                            children = child_entities(current_path.last)
                            children[@route_indices[index - 1]]
                          end
              end
              fail_integrity('entity_path_changed') unless current && valid_entity?(current)

              context.record(original, current)
              if shared_component_instance?(current)
                fail_integrity('shared_component_cannot_be_unique') unless current.respond_to?(:make_unique)

                current.make_unique
              end
              current_path << current
            end
            @current_full_path = current_path
            @entity = current_path.last
            self
          end

          def replace_entity(result, context)
            fail_integrity('boolean_result_invalid') unless result && valid_entity?(result)

            @entity = result
            @current_full_path[-1] = result
            context.record(original_path.last, result)
            self
          end

          def parent_world_transform
            transforms = @current_full_path[0...-1]
            transforms.inject(AutomaticPlanning::Transform3.identity) do |combined, current|
              combined * entity_transform(current)
            end
          end

          def parent_entities
            parent = entity.respond_to?(:parent) ? entity.parent : nil
            return parent if parent && parent.respond_to?(:add_group)
            return parent.entities if parent && parent.respond_to?(:entities)

            raise JointExecutionFailure.new(
              'parent_entities_unavailable',
              'Không tìm thấy ngữ cảnh chứa chi tiết để tạo mộng.',
              part_id: identity.stable_id
            )
          end

          private

          def build_route_indices
            @original_full_path.each_cons(2).map do |parent, child|
              index = child_entities(parent).index { |candidate| candidate.equal?(child) }
              fail_integrity('entity_path_changed') unless index

              index
            end.freeze
          end

          def validate_identity!
            if identity.persistent_id && persistent_identity(entity) != identity.persistent_id.to_s
              fail_integrity('persistent_identity_changed')
            end
            definition = entity.respond_to?(:definition) ? entity.definition : nil
            if identity.definition_id && definition && definition.respond_to?(:persistent_id) &&
               definition.persistent_id.to_s != identity.definition_id.to_s
              fail_integrity('definition_identity_changed')
            end
          end

          def validate_transform_path!(path, snapshots)
            fail_integrity('transform_path_changed') unless path.length == snapshots.length

            path.each_with_index do |current, index|
              fail_integrity('referenced_entity_invalid') unless valid_entity?(current)
              unless entity_transform(current).values == snapshots[index]
                fail_integrity('transform_changed')
              end
            end
          end

          def validate_uniqueness_capability!
            @original_full_path.each do |current|
              next unless shared_component_instance?(current)

              fail_integrity('shared_component_cannot_be_unique') unless current.respond_to?(:make_unique)
            end
          end

          def shared_component_instance?(current)
            definition = current.respond_to?(:definition) ? current.definition : nil
            return false unless definition && definition.respond_to?(:instances)

            definition.instances.length > 1
          end

          def child_entities(current)
            container = if current.respond_to?(:entities)
                          current.entities
                        elsif current.respond_to?(:definition) && current.definition.respond_to?(:entities)
                          current.definition.entities
                        end
            container ? container.to_a : []
          end

          def entity_transform(current)
            transformation = current.respond_to?(:transformation) ? current.transformation : nil
            AutomaticPlanning::Transform3.from_sketchup(transformation)
          end

          def persistent_identity(current)
            return current.persistent_id.to_s if current.respond_to?(:persistent_id)
            return current.entityID.to_s if current.respond_to?(:entityID)

            "object-#{current.object_id}"
          end

          def valid_entity?(current)
            !current.respond_to?(:valid?) || current.valid?
          end

          def fail_integrity(code, extra = {})
            raise JointExecutionFailure.new(
              code,
              'Mô hình hoặc bản xem trước đã thay đổi. Vui lòng phân tích lại trước khi tạo mộng.',
              { part_id: identity.stable_id }.merge(extra)
            )
          end
        end

        class ExecutionEntityRegistry
          def initialize(resolution)
            @resolution = resolution
            @references = {}
            @uniqueness_context = EntityUniquenessContext.new
          end

          def reference_for(identity)
            existing = @references[identity.stable_id]
            if existing
              unless same_identity?(existing.identity, identity)
                raise JointExecutionFailure.new(
                  'conflicting_part_identity',
                  'Mô hình hoặc bản xem trước đã thay đổi. Vui lòng phân tích lại trước khi tạo mộng.',
                  part_id: identity.stable_id
                )
              end
              return existing
            end

            @references[identity.stable_id] = build_reference(identity)
          end

          def validate_for!(identity, role)
            reference = reference_for(identity)
            reference.validate!
            reference.validate_boolean_capability!(role)
            reference
          end

          def ensure_unique_all!
            @references.keys.sort.each do |part_id|
              @references[part_id].ensure_unique!(@uniqueness_context)
            end
          end

          def replace(identity, result)
            reference_for(identity).replace_entity(result, @uniqueness_context)
          end

          private

          def same_identity?(first, second)
            first.stable_id == second.stable_id &&
              first.persistent_id == second.persistent_id &&
              first.definition_id == second.definition_id
          end

          def build_reference(identity)
            part_id = identity.stable_id
            entity = @resolution.entity_by_part_id[part_id]
            path = @resolution.entity_paths_by_part_id[part_id]
            snapshots = @resolution.transform_snapshots_by_part_id[part_id]
            unless entity && path && snapshots
              raise JointExecutionFailure.new(
                'referenced_entity_missing',
                'Mô hình hoặc bản xem trước đã thay đổi. Vui lòng phân tích lại trước khi tạo mộng.',
                part_id: part_id
              )
            end

            ExecutionEntityReference.new(
              identity: identity,
              entity: entity,
              path: path,
              transform_snapshots: snapshots,
              active_path: @resolution.active_path_entities,
              active_path_snapshot: @resolution.active_path_snapshot
            )
          end
        end
      end
    end
  end
end
