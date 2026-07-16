# frozen_string_literal: true

require_relative 'system_registry'
require_relative 'persistence'

# Deterministic authoritative storage for one drawer-system specification.
# Identity stays on every member, while specification JSON exists only on the
# highest-priority member currently present in the supplied scope.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SpecificationOwner
          ROLE_PRIORITY = %w[
            drawer_system drawer_opening drawer_box drawer_slide_left drawer_slide_right
          ].freeze

          class OwnerError < ArgumentError
            attr_reader :code, :role

            def initialize(code, message, role: nil)
              @code = code
              @role = role
              super(message)
            end
          end

          module_function

          def find(scope:, drawer_system_id:)
            members = SystemRegistry.entities_for_system(scope, drawer_system_id)
            return nil if members.empty?

            by_role = members.each_with_object({}) do |entity, result|
              role = Metadata.drawer_object_type(entity)
              next unless role

              result[role] ||= []
              result[role] << entity
            end
            duplicate = ROLE_PRIORITY.find { |role| by_role.fetch(role, []).length > 1 }
            if duplicate
              raise OwnerError.new(
                :duplicate_role,
                "Drawer system has multiple entities for role #{duplicate}.",
                role: duplicate
              )
            end

            role = ROLE_PRIORITY.find { |candidate| by_role.fetch(candidate, []).length == 1 }
            role ? by_role[role].first : nil
          end

          def read(scope:, drawer_system_id:)
            owner = find(scope: scope, drawer_system_id: drawer_system_id)
            return nil unless owner

            ordered_members(scope, drawer_system_id, owner).each do |entity|
              specification = Persistence.read(entity)
              return specification if specification
            end
            nil
          end

          def write(scope:, drawer_system_id:, specification:)
            owner = find(scope: scope, drawer_system_id: drawer_system_id)
            unless owner
              raise OwnerError.new(
                :missing_system,
                'Drawer system does not have an available specification owner.'
              )
            end

            persisted = Persistence.write(owner, specification)
            ordered_members(scope, drawer_system_id, owner).each do |entity|
              next if entity.equal?(owner)
              next unless Persistence.read(entity)

              Persistence.clear(entity)
            end
            persisted
          end

          def ordered_members(scope, drawer_system_id, owner)
            members = SystemRegistry.entities_for_system(scope, drawer_system_id)
            members.sort_by do |entity|
              role = Metadata.drawer_object_type(entity)
              [entity.equal?(owner) ? -1 : ROLE_PRIORITY.index(role) || ROLE_PRIORITY.length]
            end
          end
        end
      end
    end
  end
end
