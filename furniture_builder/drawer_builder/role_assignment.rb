# frozen_string_literal: true

require_relative 'selection_validator'
require_relative 'system_registry'
require_relative 'persistence'

# Conservative service for assigning standalone drawer roles to existing
# instances. SketchUp writes are wrapped in one operation unless the caller
# passes manage_operation: false because it already owns the operation.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module RoleAssignment
          OPERATION_ASSIGN = 'Gán vai trò ngăn kéo'
          OPERATION_UNASSIGN = 'Bỏ gán vai trò ngăn kéo'
          OPERATION_MOVE = 'Chuyển sang hệ ngăn kéo khác'

          module_function

          def assign(entity:, role:, drawer_system_id: nil, source: :user_assigned,
                     specification: nil, scope: nil, model: nil, manage_operation: true)
            perform_change(
              mode: :assign,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              source: source,
              specification: specification,
              scope: scope,
              model: model,
              manage_operation: manage_operation
            )
          end

          def reassign(entity:, role:, drawer_system_id: nil, source: :user_assigned,
                       specification: nil, scope: nil, model: nil, manage_operation: true)
            perform_change(
              mode: :reassign,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              source: source,
              specification: specification,
              scope: scope,
              model: model,
              manage_operation: manage_operation
            )
          end

          def move(entity:, drawer_system_id:, specification: nil, scope: nil,
                   model: nil, manage_operation: true)
            validation = SelectionValidator.validate_entity(entity)
            return validation unless validation[:success]

            current_role = assigned_role(entity)
            unless current_role
              return SelectionValidator.failure_result(
                :entity_not_assigned,
                entity: entity,
                drawer_system_id: drawer_system_id
              )
            end
            perform_change(
              mode: :move,
              entity: entity,
              role: current_role,
              drawer_system_id: drawer_system_id,
              source: :user_assigned,
              specification: specification,
              scope: scope,
              model: model,
              manage_operation: manage_operation
            )
          end

          def move_and_reassign(entity:, role:, drawer_system_id:, source: :user_assigned,
                                specification: nil, scope: nil, model: nil,
                                manage_operation: true)
            perform_change(
              mode: :move_and_reassign,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              source: source,
              specification: specification,
              scope: scope,
              model: model,
              manage_operation: manage_operation
            )
          end

          def unassign(entity:, model: nil, manage_operation: true)
            validation = SelectionValidator.validate_entity(entity)
            return validation unless validation[:success]

            values = Metadata.read(entity)
            role = values[:drawer_object_type]
            system_id = values[:drawer_system_id]
            unless role
              return success_result(entity, nil, nil, :unchanged)
            end

            transaction_model = resolve_model(entity, model)
            with_operation(transaction_model, manage_operation, OPERATION_UNASSIGN) do
              Metadata.clear_drawer_identity(entity)
            end
            success_result(entity, role, system_id, :unassigned)
          rescue Identity::IdentityError, Metadata::MetadataError, Persistence::PersistenceError => e
            failure_from_error(e, entity: entity)
          end

          def assigned_role(entity)
            role = Metadata.drawer_object_type(entity)
            role&.to_sym
          end

          def assigned?(entity)
            !assigned_role(entity).nil?
          end

          def perform_change(mode:, entity:, role:, drawer_system_id:, source:, specification:,
                             scope:, model:, manage_operation:)
            validation = SelectionValidator.validate_entity(entity)
            return validation unless validation[:success]

            validation = SelectionValidator.validate_role(role, entity: entity)
            return validation unless validation[:success]

            if drawer_system_id
              validation = SelectionValidator.validate_system_id(
                drawer_system_id,
                entity: entity,
                role: role
              )
              return validation unless validation[:success]
            end

            current = Metadata.read(entity)
            decision = assignment_decision(mode, current, role.to_s, drawer_system_id)
            return decision unless decision[:success]

            target_system_id = decision[:drawer_system_id]
            normalized_specification = specification.nil? ? nil : Persistence.normalize_specification(specification)
            search_scope = resolve_scope(entity, scope, model)
            conflict = role_conflict(search_scope, entity, target_system_id, role)
            return conflict if conflict

            if decision[:details][:status] == :unchanged && normalized_specification.nil?
              return success_result(entity, role, target_system_id, :unchanged)
            end

            identity = build_identity(current, role, target_system_id, source)
            operation_name = move_mode?(mode) ? OPERATION_MOVE : OPERATION_ASSIGN
            transaction_model = resolve_model(entity, model)
            with_operation(transaction_model, manage_operation, operation_name) do
              Metadata.write(entity, identity) unless decision[:details][:status] == :unchanged
              Persistence.write(entity, normalized_specification) if normalized_specification
            end

            status = if decision[:details][:status] == :unchanged
                       :specification_updated
                     else
                       decision[:details][:status]
                     end
            success_result(entity, role, target_system_id, status, identity: identity)
          rescue Identity::IdentityError, Metadata::MetadataError, Persistence::PersistenceError => e
            failure_from_error(
              e,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id
            )
          end

          def assignment_decision(mode, current, requested_role, requested_system_id)
            current_role = current[:drawer_object_type]
            current_system_id = current[:drawer_system_id]

            case mode
            when :assign
              conservative_assignment(current_role, current_system_id, requested_role, requested_system_id)
            when :reassign
              explicit_reassignment(current_role, current_system_id, requested_role, requested_system_id)
            when :move
              explicit_move(current_role, current_system_id, requested_role, requested_system_id)
            when :move_and_reassign
              explicit_move_and_reassign(current_role, current_system_id, requested_role, requested_system_id)
            else
              SelectionValidator.failure_result(:invalid_assignment_mode, role: requested_role)
            end
          end

          def conservative_assignment(current_role, current_system_id, requested_role, requested_system_id)
            unless current_role
              target = requested_system_id || Identity.generate_system_id
              return decision_success(requested_role, target, :assigned)
            end

            target = requested_system_id || current_system_id
            same_role = current_role == requested_role
            same_system = current_system_id == target
            return decision_success(current_role, current_system_id, :unchanged) if same_role && same_system

            assignment_conflict(current_role, current_system_id, requested_role, target)
          end

          def explicit_reassignment(current_role, current_system_id, requested_role, requested_system_id)
            return not_assigned_result(requested_role, requested_system_id) unless current_role

            target = requested_system_id || current_system_id
            if target != current_system_id
              return SelectionValidator.failure_result(
                :move_required,
                role: requested_role,
                drawer_system_id: target,
                details: { assigned_system_id: current_system_id }
              )
            end
            status = current_role == requested_role ? :unchanged : :reassigned
            decision_success(requested_role, target, status)
          end

          def explicit_move(current_role, current_system_id, requested_role, requested_system_id)
            return not_assigned_result(requested_role, requested_system_id) unless current_role
            if requested_role.to_s != current_role
              return SelectionValidator.failure_result(
                :reassignment_required,
                role: requested_role,
                drawer_system_id: requested_system_id,
                details: { assigned_role: current_role.to_sym }
              )
            end

            status = current_system_id == requested_system_id.to_s ? :unchanged : :moved
            decision_success(current_role, requested_system_id.to_s, status)
          end

          def explicit_move_and_reassign(current_role, current_system_id, requested_role, requested_system_id)
            return not_assigned_result(requested_role, requested_system_id) unless current_role

            status = if current_role == requested_role && current_system_id == requested_system_id.to_s
                       :unchanged
                     else
                       :moved_and_reassigned
                     end
            decision_success(requested_role, requested_system_id.to_s, status)
          end

          def assignment_conflict(current_role, current_system_id, requested_role, requested_system_id)
            details = {
              assigned_role: current_role.to_sym,
              assigned_system_id: current_system_id
            }
            code = if current_role != requested_role && current_system_id == requested_system_id
                     :entity_assigned_to_different_role
                   elsif current_role == requested_role
                     :entity_assigned_to_different_system
                   else
                     :entity_assignment_conflict
                   end
            SelectionValidator.failure_result(
              code,
              role: requested_role,
              drawer_system_id: requested_system_id,
              details: details
            )
          end

          def role_conflict(scope, entity, drawer_system_id, role)
            return nil unless scope

            occupied = SystemRegistry.entity_for_role(scope, drawer_system_id, role)
            return nil unless occupied
            return nil if occupied.equal?(entity) || occupied == entity

            SelectionValidator.failure_result(
              :role_already_assigned,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              details: { existing_entity: occupied }
            )
          end

          def build_identity(current, role, drawer_system_id, source)
            Identity.create(
              object_type: role.to_s,
              system_id: drawer_system_id,
              source: source.to_s,
              drawer_index: current[:drawer_index],
              object_id: current[:drawer_object_id]
            )
          end

          def decision_success(role, drawer_system_id, status)
            SelectionValidator.success_result(
              role: role,
              drawer_system_id: drawer_system_id,
              details: { status: status }
            )
          end

          def not_assigned_result(role, drawer_system_id)
            SelectionValidator.failure_result(
              :entity_not_assigned,
              role: role,
              drawer_system_id: drawer_system_id
            )
          end

          def success_result(entity, role, drawer_system_id, status, identity: nil)
            details = { status: status }
            details[:identity] = identity.to_h if identity
            SelectionValidator.success_result(
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              details: details
            )
          end

          def failure_from_error(error, entity:, role: nil, drawer_system_id: nil)
            field = error.respond_to?(:field) ? error.field : nil
            SelectionValidator.failure_result(
              error.code,
              entity: entity,
              role: role,
              drawer_system_id: drawer_system_id,
              details: { field: field }
            )
          end

          def move_mode?(mode)
            %i[move move_and_reassign].include?(mode)
          end

          def resolve_scope(entity, scope, model)
            return scope if scope

            parent = entity.parent if entity.respond_to?(:parent)
            return parent.entities if parent && parent.respond_to?(:entities)

            resolve_model(entity, model)
          rescue StandardError
            resolve_model(entity, model)
          end

          def resolve_model(entity, explicit_model)
            return explicit_model if explicit_model
            return entity.model if entity.respond_to?(:model) && entity.model
            return ::Sketchup.active_model if defined?(::Sketchup) && ::Sketchup.respond_to?(:active_model)

            nil
          rescue StandardError
            explicit_model
          end

          def with_operation(model, manage_operation, name)
            owns_operation = manage_operation && transaction_model?(model)
            model.start_operation(name, true) if owns_operation
            result = yield
            model.commit_operation if owns_operation
            result
          rescue StandardError
            model.abort_operation if owns_operation
            raise
          end

          def transaction_model?(model)
            model && model.respond_to?(:start_operation) &&
              model.respond_to?(:commit_operation) && model.respond_to?(:abort_operation)
          end
        end
      end
    end
  end
end
