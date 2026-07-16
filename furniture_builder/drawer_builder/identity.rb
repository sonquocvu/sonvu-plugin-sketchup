# frozen_string_literal: true

require 'securerandom'

# Pure, immutable identity value for independent drawer objects. UUIDs are
# persisted as attributes and therefore remain stable across save and reopen.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class Identity
          CURRENT_VERSION = 1
          OBJECT_TYPES = %w[
            drawer_opening
            drawer_slide_left
            drawer_slide_right
            drawer_box
            drawer_system
          ].freeze
          SOURCES = %w[plugin_generated user_assigned legacy_adapter].freeze
          UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i.freeze

          class IdentityError < ArgumentError
            attr_reader :code, :field

            def initialize(code, field, message)
              @code = code
              @field = field
              super(message)
            end
          end

          attr_reader :drawer_object_type, :drawer_system_id, :drawer_version,
                      :drawer_source, :drawer_index, :drawer_object_id

          def self.create(object_type:, system_id: nil, source: 'plugin_generated',
                          drawer_index: nil, object_id: nil)
            new(
              drawer_object_type: object_type,
              drawer_system_id: system_id || generate_system_id,
              drawer_version: CURRENT_VERSION,
              drawer_source: source,
              drawer_index: drawer_index,
              drawer_object_id: object_id || generate_object_id
            )
          end

          def self.from_h(values)
            new(values || {})
          end

          def self.generate_system_id
            SecureRandom.uuid
          end

          def self.generate_object_id
            SecureRandom.uuid
          end

          def self.valid_object_type?(value)
            OBJECT_TYPES.include?(value.to_s)
          end

          def self.valid_system_id?(value)
            value.to_s.match?(UUID_PATTERN)
          end

          def initialize(values)
            @drawer_object_type = value_for(values, :drawer_object_type).to_s
            @drawer_system_id = value_for(values, :drawer_system_id).to_s
            @drawer_version = normalized_version(value_for(values, :drawer_version))
            @drawer_source = normalized_source(value_for(values, :drawer_source))
            @drawer_index = normalized_index(value_for(values, :drawer_index))
            object_id = value_for(values, :drawer_object_id).to_s.strip
            @drawer_object_id = object_id.empty? ? self.class.generate_object_id : object_id
            validate!
            freeze
          end

          def to_h
            {
              drawer_object_type: drawer_object_type,
              drawer_system_id: drawer_system_id,
              drawer_version: drawer_version,
              drawer_source: drawer_source,
              drawer_index: drawer_index,
              drawer_object_id: drawer_object_id
            }
          end

          private

          def validate!
            unless self.class.valid_object_type?(drawer_object_type)
              raise IdentityError.new(
                :unsupported_object_type,
                :drawer_object_type,
                "Unsupported drawer object type: #{drawer_object_type}"
              )
            end
            unless self.class.valid_system_id?(drawer_system_id)
              raise IdentityError.new(
                :invalid_system_id,
                :drawer_system_id,
                'Drawer system ID must be a UUID.'
              )
            end
            unless SOURCES.include?(drawer_source)
              raise IdentityError.new(
                :invalid_source,
                :drawer_source,
                "Unsupported drawer source: #{drawer_source}"
              )
            end
          end

          def normalized_version(value)
            version = parse_version(value)
            if version > CURRENT_VERSION
              raise IdentityError.new(
                :future_metadata_version,
                :drawer_version,
                "Drawer metadata version #{version} is newer than supported version #{CURRENT_VERSION}."
              )
            end
            if version <= 0
              raise IdentityError.new(
                :invalid_metadata_version,
                :drawer_version,
                'Drawer metadata version must be greater than zero.'
              )
            end
            version
          end

          def parse_version(value)
            return CURRENT_VERSION if value.nil? || value.to_s.empty?

            Integer(value)
          rescue ArgumentError, TypeError
            raise IdentityError.new(
              :invalid_metadata_version,
              :drawer_version,
              'Drawer metadata version must be an integer.'
            )
          end

          def normalized_source(value)
            text = value.to_s.strip
            text.empty? ? 'plugin_generated' : text
          end

          def normalized_index(value)
            return nil if value.nil? || value.to_s.strip.empty?

            index = Integer(value)
            if index <= 0
              raise IdentityError.new(
                :invalid_drawer_index,
                :drawer_index,
                'Drawer index must be greater than zero.'
              )
            end
            index
          rescue ArgumentError, TypeError
            raise IdentityError.new(
              :invalid_drawer_index,
              :drawer_index,
              'Drawer index must be an integer.'
            )
          end

          def value_for(values, key)
            return nil unless values.respond_to?(:[])
            return values[key] if values.respond_to?(:key?) && values.key?(key)
            return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

            nil
          end
        end
      end
    end
  end
end
