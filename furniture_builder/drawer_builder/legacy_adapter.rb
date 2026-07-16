# frozen_string_literal: true

require_relative 'metadata'

# Read-only recognition and explicit opt-in adaptation for drawer metadata
# emitted by the existing Furniture Builder implementation.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module LegacyAdapter
          BOX_ROLES = %w[
            drawer_side_left drawer_side_right drawer_inner_front drawer_back drawer_bottom
          ].freeze
          SLIDE_TYPES = %w[drawer_slide_left drawer_slide_right].freeze

          class LegacyError < ArgumentError
            attr_reader :code

            def initialize(code, message)
              @code = code
              super(message)
            end
          end

          module_function

          def detect(entity)
            Metadata.ensure_supported!(entity)
            kind = Metadata.attribute(entity, 'part_kind', '').to_s
            role = Metadata.attribute(entity, 'part_role', '').to_s
            hardware_type = Metadata.attribute(entity, 'hardware_type', '').to_s
            drawer_index = positive_integer(Metadata.attribute(entity, 'drawer_index'))
            detected_type = inferred_object_type(kind, role, hardware_type)
            recognized = !detected_type.nil? && !drawer_index.nil?
            {
              recognized: recognized,
              inferred_object_type: recognized ? detected_type : nil,
              legacy_kind: kind,
              legacy_role: role,
              legacy_hardware_type: hardware_type,
              drawer_index: drawer_index,
              confidence: recognized ? inference_confidence(role) : 'none'
            }
          end

          def to_drawer_identity(entity, system_id: nil)
            detection = detect(entity)
            unless detection[:recognized]
              raise LegacyError.new(
                :unsupported_legacy_entity,
                'Entity does not contain a supported legacy drawer metadata pattern.'
              )
            end
            Identity.create(
              object_type: detection[:inferred_object_type],
              system_id: system_id,
              source: 'legacy_adapter',
              drawer_index: detection[:drawer_index]
            )
          end

          def apply(entity, system_id: nil)
            identity = to_drawer_identity(entity, system_id: system_id)
            Metadata.write(entity, identity)
          end

          def inferred_object_type(kind, role, hardware_type)
            return 'drawer_box' if kind == 'drawer_box' && BOX_ROLES.include?(role)
            return role if kind == 'hardware' && SLIDE_TYPES.include?(role)
            return hardware_type if kind == 'hardware' && SLIDE_TYPES.include?(hardware_type)
            return 'drawer_system' if kind == 'front' && role == 'drawer_front'

            nil
          end

          def inference_confidence(role)
            role == 'drawer_front' ? 'medium' : 'high'
          end

          def positive_integer(value)
            return nil if value.nil? || value.to_s.empty?

            number = Integer(value)
            number.positive? ? number : nil
          rescue ArgumentError, TypeError
            nil
          end
        end
      end
    end
  end
end
