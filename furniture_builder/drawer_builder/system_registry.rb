# frozen_string_literal: true

require_relative 'metadata'

# Read-only lookup over an explicit search scope. Passing a model searches its
# active editing context. Passing an Entities collection or Enumerable searches
# that supplied scope. Recursive traversal is limited to those supplied roots.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SystemRegistry
          CORE_ROLES = %w[
            drawer_opening drawer_slide_left drawer_slide_right drawer_box
          ].freeze

          module_function

          def entities_for_system(scope, drawer_system_id, recursive: true)
            validate_system_id!(drawer_system_id)
            searchable_entities(scope, recursive: recursive).select do |entity|
              values = Metadata.read(entity)
              values[:drawer_system_id] == drawer_system_id.to_s &&
                Identity.valid_object_type?(values[:drawer_object_type])
            end
          end

          def entities_for_role(scope, drawer_system_id, role, recursive: true)
            validate_role!(role)
            role_name = role.to_s
            entities_for_system(scope, drawer_system_id, recursive: recursive).select do |entity|
              Metadata.drawer_object_type(entity) == role_name
            end
          end

          def entity_for_role(scope, drawer_system_id, role, recursive: true)
            entities_for_role(scope, drawer_system_id, role, recursive: recursive).first
          end

          def roles_for_system(scope, drawer_system_id, recursive: true)
            present = entities_for_system(scope, drawer_system_id, recursive: recursive).each_with_object({}) do |entity, roles|
              role = Metadata.drawer_object_type(entity)
              roles[role] = true if role
            end
            Identity::OBJECT_TYPES.select { |role| present[role] }.map(&:to_sym)
          end

          def system_state(scope, drawer_system_id, recursive: true)
            roles = roles_for_system(scope, drawer_system_id, recursive: recursive).map(&:to_s)
            opening = roles.include?('drawer_opening')
            left_slide = roles.include?('drawer_slide_left')
            right_slide = roles.include?('drawer_slide_right')
            slides = left_slide || right_slide
            both_slides = left_slide && right_slide
            box = roles.include?('drawer_box')

            return :complete if opening && both_slides && box
            return :opening_and_slides if opening && slides && !box
            return :opening_and_box if opening && box && !slides
            return :opening_only if opening && !slides && !box
            return :slides_only if slides && !opening && !box
            return :box_only if box && !opening && !slides

            :custom_partial
          end

          def system_complete?(scope, drawer_system_id, recursive: true)
            system_state(scope, drawer_system_id, recursive: recursive) == :complete
          end

          def searchable_entities(scope, recursive: true)
            queue = root_entities(scope)
            found = []
            visited = {}

            until queue.empty?
              entity = queue.shift
              next if entity.nil?

              identifier = entity.object_id
              next if visited[identifier]

              visited[identifier] = true
              next if deleted_entity?(entity)

              found << entity if Metadata.supported_entity?(entity)
              queue.concat(nested_entities(entity)) if recursive
            end
            found
          end

          def root_entities(scope)
            return [] if scope.nil?
            if model_scope?(scope)
              collection = scope.active_entities
              return collection.respond_to?(:to_a) ? collection.to_a.dup : Array(collection)
            end
            return [scope] if Metadata.supported_entity?(scope)
            return scope.to_a.dup if scope.respond_to?(:to_a)
            if scope.respond_to?(:entities)
              collection = scope.entities
              return collection.respond_to?(:to_a) ? collection.to_a.dup : Array(collection)
            end

            []
          end

          def nested_entities(entity)
            collection = if entity.respond_to?(:entities)
                           entity.entities
                         elsif entity.respond_to?(:definition) && entity.definition.respond_to?(:entities)
                           entity.definition.entities
                         end
            return [] unless collection

            collection.respond_to?(:to_a) ? collection.to_a : Array(collection)
          rescue StandardError
            []
          end

          def model_scope?(scope)
            scope.respond_to?(:active_entities)
          end

          def deleted_entity?(entity)
            return true if entity.respond_to?(:deleted?) && entity.deleted?
            return !entity.valid? if entity.respond_to?(:valid?)

            false
          end

          def validate_system_id!(drawer_system_id)
            return true if Identity.valid_system_id?(drawer_system_id)

            raise Identity::IdentityError.new(
              :invalid_system_id,
              :drawer_system_id,
              'Drawer system ID must be a UUID.'
            )
          end

          def validate_role!(role)
            return true if Identity.valid_object_type?(role)

            raise Identity::IdentityError.new(
              :unsupported_object_type,
              :drawer_object_type,
              "Unsupported drawer object type: #{role}"
            )
          end
        end
      end
    end
  end
end
