# frozen_string_literal: true

# Immutable, SketchUp-independent data contract for a drawer opening, slides,
# and drawer box. Each section is optional so the three logical objects remain
# independent. Newly persisted production values use SketchUp internal units;
# the object itself only validates the numeric values it receives.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class Specification
          SCHEMA_VERSION = 1
          DEFAULT_UNIT_SYSTEM = 'sketchup_internal'
          SOURCES = %w[generated assigned mixed].freeze

          OPENING_FIELDS = %i[
            object_id object_type source opening_width opening_height opening_depth
            front_direction depth_direction local_transformation source_entity_id
          ].freeze
          OPENING_DIMENSIONS = %i[opening_width opening_height opening_depth].freeze

          SLIDE_FIELDS = %i[
            object_id object_type source slide_type calculation_strategy label_vi
            left_clearance right_clearance top_clearance bottom_clearance
            front_setback rear_clearance slide_thickness slide_height slide_length
            minimum_drawer_depth maximum_drawer_depth preset_name manufacturer
            left_source_entity_id right_source_entity_id
          ].freeze
          REQUIRED_SLIDE_CLEARANCES = %i[
            left_clearance right_clearance top_clearance bottom_clearance
            front_setback rear_clearance
          ].freeze
          REQUIRED_SLIDE_POSITIVE = %i[slide_thickness].freeze
          OPTIONAL_SLIDE_POSITIVE = %i[
            slide_height minimum_drawer_depth maximum_drawer_depth
          ].freeze
          OPTIONAL_SLIDE_NONNEGATIVE = %i[slide_length].freeze

          BOX_FIELDS = %i[
            object_id object_type source dimension_mode box_width box_height box_depth
            board_thickness bottom_thickness front_thickness back_thickness
            material_name bottom_material_name source_entity_id
          ].freeze
          BOX_DIMENSIONS = %i[box_width box_height box_depth].freeze
          BOX_THICKNESSES = %i[
            board_thickness bottom_thickness front_thickness back_thickness
          ].freeze

          class ValidationError < ArgumentError
            attr_reader :errors

            def initialize(errors)
              @errors = errors
              super(errors.map { |error| error[:message] }.join('; '))
            end
          end

          attr_reader :schema_version, :unit_system, :drawer_system_id,
                      :cabinet_id, :legacy_drawer_index, :source,
                      :opening, :slides, :box, :errors

          def self.from_h(values)
            new(values)
          end

          def initialize(values = {})
            values ||= {}
            @schema_version = integer_value(value_for(values, :schema_version), SCHEMA_VERSION)
            @unit_system = string_value(value_for(values, :unit_system), DEFAULT_UNIT_SYSTEM)
            @drawer_system_id = optional_string(value_for(values, :drawer_system_id))
            @cabinet_id = optional_string(value_for(values, :cabinet_id))
            @legacy_drawer_index = optional_integer(value_for(values, :legacy_drawer_index))
            @source = string_value(value_for(values, :source), 'generated')
            @opening = normalize_opening(value_for(values, :opening))
            @slides = normalize_slides(value_for(values, :slides))
            @box = normalize_box(value_for(values, :box))
            @errors = validation_errors.freeze
            deep_freeze(@opening)
            deep_freeze(@slides)
            deep_freeze(@box)
            freeze
          end

          def valid?
            errors.empty?
          end

          def validate!
            raise ValidationError, errors unless valid?

            self
          end

          def to_h
            deep_dup(
              schema_version: schema_version,
              unit_system: unit_system,
              drawer_system_id: drawer_system_id,
              cabinet_id: cabinet_id,
              legacy_drawer_index: legacy_drawer_index,
              source: source,
              opening: opening,
              slides: slides,
              box: box
            )
          end

          private

          def normalize_opening(values)
            normalize_section(values, OPENING_FIELDS, OPENING_DIMENSIONS).tap do |section|
              next unless section

              section[:object_type] ||= 'drawer_opening'
              section[:source] ||= 'generated'
            end
          end

          def normalize_slides(values)
            dimensions = REQUIRED_SLIDE_CLEARANCES + REQUIRED_SLIDE_POSITIVE +
                         OPTIONAL_SLIDE_POSITIVE + OPTIONAL_SLIDE_NONNEGATIVE
            normalize_section(values, SLIDE_FIELDS, dimensions).tap do |section|
              next unless section

              section[:object_type] ||= 'drawer_slides'
              section[:source] ||= 'generated'
              section[:slide_type] = section[:slide_type].to_s unless section[:slide_type].nil?
              if section[:calculation_strategy]
                section[:calculation_strategy] = section[:calculation_strategy].to_s
              end
            end
          end

          def normalize_box(values)
            normalize_section(values, BOX_FIELDS, BOX_DIMENSIONS + BOX_THICKNESSES).tap do |section|
              next unless section

              section[:object_type] ||= 'drawer_box'
              section[:source] ||= 'generated'
              section[:dimension_mode] ||= 'calculated'
            end
          end

          def normalize_section(values, fields, numeric_fields)
            return nil if values.nil?

            fields.each_with_object({}) do |field, section|
              value = value_for(values, field)
              section[field] = numeric_fields.include?(field) ? numeric_value(value) : deep_dup(value)
            end
          end

          def validation_errors
            result = []
            unless schema_version == SCHEMA_VERSION
              result << error(:unsupported_schema, :root, :schema_version, 'Unsupported drawer specification schema version.')
            end
            unless SOURCES.include?(source)
              result << error(:invalid_source, :root, :source, 'Drawer specification source is invalid.')
            end
            if opening.nil? && slides.nil? && box.nil?
              result << error(:missing_sections, :root, nil, 'At least one drawer specification section is required.')
            end
            validate_opening(result) if opening
            validate_slides(result) if slides
            validate_box(result) if box
            result
          end

          def validate_opening(result)
            OPENING_DIMENSIONS.each do |field|
              validate_required_positive(result, :opening, opening, field)
            end
          end

          def validate_slides(result)
            if slides[:slide_type].to_s.empty?
              result << error(:missing_field, :slides, :slide_type, 'Drawer slide type is required.')
            end
            REQUIRED_SLIDE_CLEARANCES.each do |field|
              validate_required_nonnegative(result, :slides, slides, field)
            end
            REQUIRED_SLIDE_POSITIVE.each do |field|
              validate_required_positive(result, :slides, slides, field)
            end
            OPTIONAL_SLIDE_POSITIVE.each do |field|
              next if slides[field].nil?

              validate_positive(result, :slides, slides, field)
            end
            OPTIONAL_SLIDE_NONNEGATIVE.each do |field|
              next if slides[field].nil?

              validate_nonnegative(result, :slides, slides, field)
            end
            minimum = slides[:minimum_drawer_depth]
            maximum = slides[:maximum_drawer_depth]
            if minimum && maximum && minimum > maximum
              result << error(
                :invalid_depth_range, :slides, :maximum_drawer_depth,
                'Maximum drawer depth must not be smaller than minimum drawer depth.'
              )
            end
          end

          def validate_box(result)
            BOX_THICKNESSES.each do |field|
              validate_required_positive(result, :box, box, field)
            end
            BOX_DIMENSIONS.each do |field|
              next if box[field].nil?

              validate_positive(result, :box, box, field)
            end
          end

          def validate_required_positive(result, section_name, values, field)
            if values[field].nil?
              result << error(:missing_field, section_name, field, "#{field} is required.")
            else
              validate_positive(result, section_name, values, field)
            end
          end

          def validate_required_nonnegative(result, section_name, values, field)
            if values[field].nil?
              result << error(:missing_field, section_name, field, "#{field} is required.")
            else
              validate_nonnegative(result, section_name, values, field)
            end
          end

          def validate_nonnegative(result, section_name, values, field)
            value = values[field]
            return if value && !value.negative? && value.finite?

            result << error(:negative_dimension, section_name, field, "#{field} must not be negative.")
          end

          def validate_positive(result, section_name, values, field)
            value = values[field]
            return if value && value.positive? && value.finite?

            code = value && value.negative? ? :negative_dimension : :nonpositive_dimension
            result << error(code, section_name, field, "#{field} must be greater than zero.")
          end

          def error(code, section_name, field, message)
            { code: code, section: section_name, field: field, message: message }.freeze
          end

          def value_for(values, key)
            return nil unless values.respond_to?(:[])
            return values[key] if values.respond_to?(:key?) && values.key?(key)
            return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

            nil
          end

          def numeric_value(value)
            return nil if value.nil? || value.to_s.strip.empty?

            number = Float(value)
            number.finite? ? number : nil
          rescue ArgumentError, TypeError
            nil
          end

          def integer_value(value, fallback)
            Integer(value)
          rescue ArgumentError, TypeError
            fallback
          end

          def optional_integer(value)
            return nil if value.nil? || value.to_s.strip.empty?

            Integer(value)
          rescue ArgumentError, TypeError
            nil
          end

          def string_value(value, fallback)
            text = value.to_s.strip
            text.empty? ? fallback : text
          end

          def optional_string(value)
            text = value.to_s.strip
            text.empty? ? nil : text
          end

          def deep_dup(value)
            case value
            when Hash
              value.each_with_object({}) { |(key, item), copy| copy[key] = deep_dup(item) }
            when Array
              value.map { |item| deep_dup(item) }
            else
              value
            end
          end

          def deep_freeze(value)
            case value
            when Hash
              value.each { |key, item| deep_freeze(key); deep_freeze(item) }
            when Array
              value.each { |item| deep_freeze(item) }
            end
            value.freeze unless value.nil?
          end
        end
      end
    end
  end
end
