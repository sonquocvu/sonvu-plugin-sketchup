# frozen_string_literal: true

if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/metadata'
else
  require_relative 'metadata'
end

# Read-only validation used by future Vietnamese role-assignment commands.
# Expected validation failures are returned with one consistent Hash contract.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SelectionValidator
          module_function

          def validate_single_assignable_entity(selection)
            entities = selection_entities(selection)
            if entities.empty?
              return failure_result(:empty_selection, details: { count: 0 })
            end
            if entities.length > 1
              return failure_result(:multiple_selection, details: { count: entities.length })
            end

            validate_entity(entities.first)
          end

          def validate_role_assignment(entity, role, drawer_system_id: nil)
            result = validate_entity(entity)
            return result unless result[:success]

            result = validate_role(role, entity: entity)
            return result unless result[:success]

            if drawer_system_id
              result = validate_system_id(drawer_system_id, entity: entity, role: role)
              return result unless result[:success]
            end

            validate_existing_assignment(entity, role, drawer_system_id)
          rescue Metadata::MetadataError => e
            failure_result(e.code, entity: entity, role: role, drawer_system_id: drawer_system_id,
                           details: { field: e.field })
          end

          def validate_system_membership(entity, drawer_system_id)
            result = validate_entity(entity)
            return result unless result[:success]

            result = validate_system_id(drawer_system_id, entity: entity)
            return result unless result[:success]

            values = Metadata.read(entity)
            assigned_system_id = values[:drawer_system_id]
            return success_result(entity: entity, drawer_system_id: drawer_system_id) unless assigned_system_id
            if assigned_system_id == drawer_system_id.to_s
              return success_result(
                entity: entity,
                drawer_system_id: assigned_system_id,
                details: { membership: :same_system }
              )
            end

            failure_result(
              :entity_assigned_to_different_system,
              entity: entity,
              drawer_system_id: drawer_system_id,
              details: { assigned_system_id: assigned_system_id }
            )
          rescue Metadata::MetadataError => e
            failure_result(e.code, entity: entity, drawer_system_id: drawer_system_id,
                           details: { field: e.field })
          end

          def validate_entity(entity, allow_locked: false)
            if shared_component_definition?(entity)
              return failure_result(:shared_component_definition_risk, entity: entity)
            end
            unless assignable_entity?(entity)
              return failure_result(:unsupported_entity, entity: entity)
            end
            if deleted_entity?(entity)
              return failure_result(:deleted_entity, entity: entity)
            end
            if !allow_locked && locked_entity?(entity)
              return failure_result(:locked_entity, entity: entity)
            end

            success_result(
              entity: entity,
              details: {
                identity_scope: :instance,
                shared_definition: shared_component_instance?(entity)
              }
            )
          end

          def validate_role(role, entity: nil)
            role_name = role.to_s
            return success_result(entity: entity, role: role_name.to_sym) if Identity.valid_object_type?(role_name)

            failure_result(:invalid_role, entity: entity, role: role)
          end

          def validate_system_id(drawer_system_id, entity: nil, role: nil)
            if Identity.valid_system_id?(drawer_system_id)
              return success_result(
                entity: entity,
                role: normalized_role(role),
                drawer_system_id: drawer_system_id.to_s
              )
            end

            failure_result(
              :invalid_system_id,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id
            )
          end

          def validate_existing_assignment(entity, role, drawer_system_id)
            values = Metadata.read(entity)
            assigned_role = values[:drawer_object_type]
            assigned_system_id = values[:drawer_system_id]
            requested_role = role.to_s
            requested_system_id = drawer_system_id&.to_s

            unless assigned_role
              return success_result(
                entity: entity,
                role: requested_role.to_sym,
                drawer_system_id: requested_system_id,
                details: { assignment_state: :unassigned }
              )
            end

            same_role = assigned_role == requested_role
            same_system = requested_system_id.nil? || assigned_system_id == requested_system_id
            if same_role && same_system
              return success_result(
                entity: entity,
                role: assigned_role.to_sym,
                drawer_system_id: assigned_system_id,
                details: { assignment_state: :same_role_same_system }
              )
            end

            details = {
              assigned_role: assigned_role.to_sym,
              assigned_system_id: assigned_system_id
            }
            if !same_role && same_system
              failure_result(:entity_assigned_to_different_role, entity: entity, role: role,
                             drawer_system_id: requested_system_id, details: details)
            elsif same_role
              failure_result(:entity_assigned_to_different_system, entity: entity, role: role,
                             drawer_system_id: requested_system_id, details: details)
            else
              failure_result(:entity_assignment_conflict, entity: entity, role: role,
                             drawer_system_id: requested_system_id, details: details)
            end
          end

          def success_result(entity: nil, role: nil, drawer_system_id: nil, details: {})
            {
              success: true,
              entity: entity,
              role: normalized_role(role),
              drawer_system_id: drawer_system_id,
              error_code: nil,
              details: details
            }
          end

          def failure_result(error_code, entity: nil, role: nil, drawer_system_id: nil, details: {})
            {
              success: false,
              entity: entity,
              role: normalized_role(role),
              drawer_system_id: drawer_system_id,
              error_code: error_code,
              details: details
            }
          end

          def assignable_entity?(entity)
            return false if entity.nil?

            stub_type = stub_entity_type(entity)
            return %i[group component_instance].include?(stub_type) if stub_type

            Metadata.supported_entity?(entity)
          end

          def deleted_entity?(entity)
            return true if entity.respond_to?(:deleted?) && entity.deleted?
            return !entity.valid? if entity.respond_to?(:valid?)

            false
          end

          def locked_entity?(entity)
            entity.respond_to?(:locked?) && entity.locked?
          end

          def shared_component_definition?(entity)
            return false if entity.nil?
            return true if stub_entity_type(entity) == :component_definition

            defined?(::Sketchup::ComponentDefinition) && entity.is_a?(::Sketchup::ComponentDefinition)
          end

          def shared_component_instance?(entity)
            return false unless component_instance?(entity)
            return false unless entity.respond_to?(:definition)

            definition = entity.definition
            definition.respond_to?(:instances) && definition.instances.length > 1
          rescue StandardError
            false
          end

          def component_instance?(entity)
            return true if stub_entity_type(entity) == :component_instance

            defined?(::Sketchup::ComponentInstance) && entity.is_a?(::Sketchup::ComponentInstance)
          end

          def stub_entity_type(entity)
            return nil unless entity.respond_to?(:drawer_assignment_entity_type)

            entity.drawer_assignment_entity_type.to_sym
          end

          def selection_entities(selection)
            return [] if selection.nil?
            return selection.to_a if selection.respond_to?(:to_a)

            Array(selection)
          end

          def normalized_role(role)
            text = role.to_s
            text.empty? ? nil : text.to_sym
          end
        end
      end
    end
  end
end
