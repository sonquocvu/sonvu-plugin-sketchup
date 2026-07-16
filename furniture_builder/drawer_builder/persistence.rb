# frozen_string_literal: true

require 'json'
require_relative 'metadata'
require_relative 'specification'

# JSON persistence for the pure drawer specification. Numeric dimensions are
# stored as numbers in the unit supplied by the caller, never as display text.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module Persistence
          SPECIFICATION_KEY = 'drawer_specification_json'

          class PersistenceError < ArgumentError
            attr_reader :code, :field

            def initialize(code, field, message)
              @code = code
              @field = field
              super(message)
            end
          end

          module_function

          def write(entity, specification)
            Metadata.ensure_supported!(entity)
            value = normalize_specification(specification)
            entity.set_attribute(
              Metadata::DICTIONARY,
              SPECIFICATION_KEY,
              JSON.generate(value.to_h)
            )
            value
          end

          def read(entity)
            Metadata.ensure_supported!(entity)
            payload = entity.get_attribute(Metadata::DICTIONARY, SPECIFICATION_KEY, nil)
            return nil if payload.nil? || payload.to_s.empty?

            load_json(payload)
          end

          def read_hash(entity)
            specification = read(entity)
            specification&.to_h
          end

          def dump(specification)
            JSON.generate(normalize_specification(specification).to_h)
          end

          def load_json(payload)
            values = JSON.parse(payload.to_s)
            normalize_specification(values)
          rescue JSON::ParserError => e
            raise PersistenceError.new(:invalid_specification, :specification, e.message)
          end

          def clear(entity)
            Metadata.ensure_supported!(entity)
            entity.delete_attribute(Metadata::DICTIONARY, SPECIFICATION_KEY)
            true
          rescue Metadata::MetadataError => e
            raise PersistenceError.new(e.code, e.field, e.message)
          end

          def normalize_specification(value)
            validate_schema_version!(value) unless value.is_a?(DrawerBuilder::Specification)
            specification = value.is_a?(DrawerBuilder::Specification) ? value : DrawerBuilder::Specification.from_h(value)
            specification.validate!
            specification
          rescue DrawerBuilder::Specification::ValidationError => e
            code = e.errors.any? { |error| error[:code] == :unsupported_schema } ?
              :future_metadata_version : :invalid_specification
            raise PersistenceError.new(code, :specification, e.message)
          end

          def validate_schema_version!(values)
            return unless values.respond_to?(:key?)

            present = values.key?(:schema_version) || values.key?('schema_version')
            return unless present

            raw = values.key?(:schema_version) ? values[:schema_version] : values['schema_version']
            version = parse_schema_version(raw)
            return if version == DrawerBuilder::Specification::SCHEMA_VERSION

            code = version > DrawerBuilder::Specification::SCHEMA_VERSION ?
              :future_metadata_version : :invalid_specification
            raise PersistenceError.new(code, :schema_version, "Unsupported drawer specification schema version: #{version}")
          end

          def parse_schema_version(value)
            Integer(value)
          rescue ArgumentError, TypeError
            raise PersistenceError.new(
              :invalid_specification,
              :schema_version,
              'Drawer specification schema version must be an integer.'
            )
          end
        end
      end
    end
  end
end
