# frozen_string_literal: true

if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/constants'
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/drawer_builder/identity'
else
  require_relative '../../constants'
  require_relative 'identity'
end

# Thin instance-level AttributeDictionary adapter. It reuses the existing
# SonVu dictionary and writes only additive drawer identity keys.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module Metadata
          DICTIONARY = CNCPlugins::ATTRIBUTE_DICTIONARY
          ATTRIBUTE_KEYS = {
            drawer_object_type: 'drawer_object_type',
            drawer_system_id: 'drawer_system_id',
            drawer_version: 'drawer_version',
            drawer_source: 'drawer_source',
            drawer_index: 'drawer_object_index',
            drawer_object_id: 'drawer_object_id'
          }.freeze
          LEGACY_DRAWER_INDEX_KEY = 'drawer_index'

          class MetadataError < ArgumentError
            attr_reader :code, :field

            def initialize(code, field, message)
              @code = code
              @field = field
              super(message)
            end
          end

          module_function

          def read(entity)
            ensure_supported!(entity)
            values = raw_identity(entity)
            return {} if values.empty?

            validate_partial_identity!(values)
            if values[:drawer_index].nil?
              legacy_index = positive_legacy_index(attribute(entity, LEGACY_DRAWER_INDEX_KEY))
              values[:drawer_index] = legacy_index unless legacy_index.nil?
            end
            values
          end

          def write(entity, attributes)
            ensure_supported!(entity)
            identity = attributes.is_a?(Identity) ? attributes : Identity.from_h(attributes)
            identity.to_h.each do |key, value|
              attribute_key = ATTRIBUTE_KEYS.fetch(key)
              if value.nil?
                delete_attribute(entity, attribute_key)
              else
                entity.set_attribute(DICTIONARY, attribute_key, value)
              end
            end
            identity
          end

          def drawer_object_type(entity)
            value = raw_attribute(entity, ATTRIBUTE_KEYS[:drawer_object_type])
            Identity.valid_object_type?(value) ? value.to_s : nil
          end

          def drawer_entity?(entity)
            !drawer_object_type(entity).nil?
          end

          def clear_drawer_identity(entity)
            ensure_supported!(entity)
            ATTRIBUTE_KEYS.each_value { |key| delete_attribute(entity, key) }
            true
          end

          def supported_entity?(entity)
            return false if entity.nil?

            if defined?(::Sketchup::Group) && defined?(::Sketchup::ComponentInstance)
              return entity.is_a?(::Sketchup::Group) || entity.is_a?(::Sketchup::ComponentInstance)
            end

            entity.respond_to?(:get_attribute) &&
              entity.respond_to?(:set_attribute) &&
              entity.respond_to?(:delete_attribute)
          end

          def attribute(entity, key, default = nil)
            ensure_supported!(entity)
            value = entity.get_attribute(DICTIONARY, key, nil)
            value.nil? ? default : value
          end

          def ensure_supported!(entity)
            return true if supported_entity?(entity)

            raise MetadataError.new(
              :unsupported_entity,
              :entity,
              'Drawer metadata target must be a group or component instance.'
            )
          end

          def raw_identity(entity)
            values = ATTRIBUTE_KEYS.each_with_object({}) do |(field, key), result|
              value = raw_attribute(entity, key)
              result[field] = value unless value.nil?
            end
            values
          end

          def raw_attribute(entity, key)
            return nil unless supported_entity?(entity)

            entity.get_attribute(DICTIONARY, key, nil)
          end

          def validate_read_version!(value)
            return if value.nil? || value.to_s.empty?

            version = parse_version(value)
            if version > Identity::CURRENT_VERSION
              raise MetadataError.new(
                :future_metadata_version,
                :drawer_version,
                "Drawer metadata version #{version} is newer than supported version #{Identity::CURRENT_VERSION}."
              )
            end
            if version <= 0
              raise MetadataError.new(
                :invalid_metadata_version,
                :drawer_version,
                'Drawer metadata version must be greater than zero.'
              )
            end
          end

          def validate_partial_identity!(values)
            validate_read_version!(values[:drawer_version])
            object_type = values[:drawer_object_type]
            if object_type && !Identity.valid_object_type?(object_type)
              raise MetadataError.new(
                :unsupported_object_type,
                :drawer_object_type,
                "Unsupported drawer object type: #{object_type}"
              )
            end
            system_id = values[:drawer_system_id]
            if system_id && !Identity.valid_system_id?(system_id)
              raise MetadataError.new(
                :invalid_system_id,
                :drawer_system_id,
                'Drawer system ID must be a UUID.'
              )
            end
            source = values[:drawer_source]
            if source && !Identity::SOURCES.include?(source.to_s)
              raise MetadataError.new(
                :invalid_source,
                :drawer_source,
                "Unsupported drawer source: #{source}"
              )
            end
            normalize_new_index!(values) unless values[:drawer_index].nil?
          end

          def normalize_new_index!(values)
            index = Integer(values[:drawer_index])
            raise ArgumentError unless index.positive?

            values[:drawer_index] = index
          rescue ArgumentError, TypeError
            raise MetadataError.new(
              :invalid_drawer_index,
              :drawer_index,
              'Drawer index must be a positive integer.'
            )
          end

          def positive_legacy_index(value)
            return nil if value.nil? || value.to_s.empty?

            index = Integer(value)
            index.positive? ? index : nil
          rescue ArgumentError, TypeError
            nil
          end

          def parse_version(value)
            Integer(value)
          rescue ArgumentError, TypeError
            raise MetadataError.new(
              :invalid_metadata_version,
              :drawer_version,
              'Drawer metadata version must be an integer.'
            )
          end

          def delete_attribute(entity, key)
            entity.delete_attribute(DICTIONARY, key)
          rescue StandardError
            # A missing key is already the desired state.
            nil
          end
        end
      end
    end
  end
end
