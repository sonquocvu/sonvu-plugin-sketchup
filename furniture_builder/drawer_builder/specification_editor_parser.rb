# frozen_string_literal: true

require 'json'
require_relative '../../shared/units'
require_relative 'slide_configurations'
require_relative 'calculator'

# Pure payload parser for the drawer editor. It accepts Vietnamese comma
# decimals, resolves slide data in Ruby, converts millimetres through the shared
# unit helper, and produces the authoritative Specification value object.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        module SpecificationEditorParser
          DIMENSION_FIELDS = %i[
            left_clearance right_clearance top_clearance bottom_clearance
            front_setback rear_clearance slide_thickness slide_height slide_length
            minimum_drawer_depth maximum_drawer_depth
          ].freeze
          REQUIRED_SLIDE_FIELDS = %i[
            left_clearance right_clearance top_clearance bottom_clearance
            front_setback rear_clearance slide_thickness
          ].freeze
          OPTIONAL_SLIDE_FIELDS = %i[
            slide_height slide_length minimum_drawer_depth maximum_drawer_depth
          ].freeze
          BOX_THICKNESS_FIELDS = %i[
            board_thickness bottom_thickness front_thickness back_thickness
          ].freeze
          BOX_DIMENSION_FIELDS = %i[box_width box_height box_depth].freeze

          FIELD_MESSAGES = {
            opening_width: 'Chiều rộng khoang phải lớn hơn 0.',
            opening_height: 'Chiều cao khoang phải lớn hơn 0.',
            opening_depth: 'Chiều sâu khoang phải lớn hơn 0.',
            left_clearance: 'Khoảng hở bên trái không hợp lệ.',
            right_clearance: 'Khoảng hở bên phải không hợp lệ.',
            top_clearance: 'Khoảng hở phía trên không hợp lệ.',
            bottom_clearance: 'Khoảng hở phía dưới không hợp lệ.',
            front_setback: 'Độ lùi phía trước không hợp lệ.',
            rear_clearance: 'Khoảng hở phía sau không hợp lệ.',
            slide_thickness: 'Độ dày ray phải lớn hơn 0.',
            box_width: 'Kích thước thùng ngăn kéo phải lớn hơn 0.',
            box_height: 'Kích thước thùng ngăn kéo phải lớn hơn 0.',
            box_depth: 'Kích thước thùng ngăn kéo phải lớn hơn 0.',
            board_thickness: 'Độ dày ván phải lớn hơn 0.',
            bottom_thickness: 'Độ dày đáy phải lớn hơn 0.',
            front_thickness: 'Độ dày mặt trước phải lớn hơn 0.',
            back_thickness: 'Độ dày mặt sau phải lớn hơn 0.'
          }.freeze

          CALCULATION_MESSAGES = {
            invalid_box_width: 'Không thể tính được chiều rộng thùng ngăn kéo.',
            invalid_box_height: 'Không thể tính được chiều cao thùng ngăn kéo.',
            invalid_box_depth: 'Không thể tính được chiều sâu thùng ngăn kéo.',
            unsupported_strategy: 'Loại ray đã chọn chưa hỗ trợ tính tự động.',
            missing_opening: 'Vui lòng nhập đầy đủ kích thước khoang ngăn kéo.',
            missing_slides: 'Vui lòng nhập đầy đủ thông số thanh ray.'
          }.freeze

          class ParserError < ArgumentError
            attr_reader :code, :field

            def initialize(code, field, message)
              @code = code
              @field = field
              super(message)
            end
          end

          ParseResult = Struct.new(:specification, :warnings)

          module_function

          def parse(payload, drawer_system_id:, base_specification: nil)
            values = payload_hash(payload)
            base = base_specification ? base_specification.to_h : {}
            opening = section_enabled?(values, :opening) ? parse_opening(values, base[:opening]) : nil
            slides = section_enabled?(values, :slides) ? parse_slides(values, base[:slides]) : nil
            box = if section_enabled?(values, :box)
                    parse_box(values, base[:box], opening: opening, slides: slides)
                  end
            if opening.nil? && slides.nil? && box.nil?
              raise ParserError.new(:missing_sections, :root, 'Vui lòng nhập ít nhất một nhóm thông số ngăn kéo.')
            end

            specification = Specification.new(
              schema_version: Specification::SCHEMA_VERSION,
              unit_system: 'sketchup_internal',
              drawer_system_id: drawer_system_id,
              cabinet_id: base[:cabinet_id],
              legacy_drawer_index: base[:legacy_drawer_index],
              source: 'assigned',
              opening: opening,
              slides: slides,
              box: box
            )
            specification.validate!
            ParseResult.new(specification, manual_size_warnings(opening, box))
          rescue Specification::ValidationError => e
            error = e.errors.first || {}
            raise ParserError.new(
              error[:code] || :invalid_specification,
              error[:field],
              FIELD_MESSAGES.fetch(error[:field], 'Dữ liệu ngăn kéo không hợp lệ.')
            )
          rescue JSON::ParserError, TypeError
            raise ParserError.new(:invalid_payload, :root, 'Dữ liệu ngăn kéo không hợp lệ.')
          end

          def calculate_preview(payload)
            values = payload_hash(payload)
            opening = parse_opening(values, nil)
            slides = parse_slides(values, nil)
            result = Calculator.calculate(opening: opening, slides: slides)
            {
              box_width: to_millimeters(result[:box_width]),
              box_height: to_millimeters(result[:box_height]),
              box_depth: to_millimeters(result[:box_depth]),
              warning: nil
            }
          rescue Calculator::CalculationError => e
            message = CALCULATION_MESSAGES.fetch(e.code, FIELD_MESSAGES.fetch(e.field, 'Không thể tính kích thước thùng ngăn kéo.'))
            raise ParserError.new(e.code, e.field, message)
          end

          def resolve_slide_for_ui(payload)
            values = payload_hash(payload)
            slides = section(values, :slides)
            type = value(slides, :slide_type).to_s
            preset_name = optional_text(value(slides, :preset_name))
            configuration = SlideConfigurations.resolve(type: type, preset_name: preset_name)
            result = configuration.each_with_object({}) do |(key, item), output|
              output[key] = item
            end
            result[:automatic_supported] = Calculator::SUPPORTED_STRATEGIES.include?(
              configuration[:calculation_strategy].to_s
            )
            result[:unsupported_message] = result[:automatic_supported] ? nil :
              'Chưa có công thức tính tự động cho loại ray này.'
            result
          rescue ArgumentError, JSON::ParserError, TypeError
            raise ParserError.new(:invalid_slide_type, :slide_type, 'Loại ray không hợp lệ.')
          end

          def parse_opening(values, base_section)
            submitted = section(values, :opening)
            merge_base(base_section).merge(
              object_type: 'drawer_opening',
              source: 'assigned',
              opening_width: positive_length(submitted, :opening_width),
              opening_height: positive_length(submitted, :opening_height),
              opening_depth: positive_length(submitted, :opening_depth)
            )
          end

          def parse_slides(values, base_section)
            submitted = section(values, :slides)
            type = value(submitted, :slide_type).to_s
            preset_name = optional_text(value(submitted, :preset_name))
            defaults = resolve_configuration(type: type, preset_name: preset_name)
            overrides_mm = {}
            REQUIRED_SLIDE_FIELDS.each do |field|
              raw = value(submitted, field)
              if raw.nil? || raw.to_s.strip.empty?
                raw = defaults[field]
              end
              overrides_mm[field] = field == :slide_thickness ?
                positive_number({ field => raw }, field) : nonnegative_number({ field => raw }, field)
            end
            OPTIONAL_SLIDE_FIELDS.each do |field|
              number = optional_number(submitted, field)
              number = defaults[field] if number.nil?
              overrides_mm[field] = number unless number.nil?
            end
            configuration = resolve_configuration(
              type: type,
              preset_name: preset_name,
              overrides: overrides_mm
            )
            converted = configuration.each_with_object({}) do |(key, item), output|
              output[key] = DIMENSION_FIELDS.include?(key) && !item.nil? ? to_internal(item) : item
            end
            merge_base(base_section).merge(converted).merge(
              object_type: 'drawer_slides',
              source: 'assigned',
              manufacturer: optional_text(value(submitted, :manufacturer))
            )
          end

          def resolve_configuration(type:, preset_name: nil, overrides: {})
            SlideConfigurations.resolve(
              type: type,
              preset_name: preset_name,
              overrides: overrides
            )
          rescue ArgumentError
            raise ParserError.new(:invalid_slide_type, :slide_type, 'Loại ray không hợp lệ.')
          end

          def parse_box(values, base_section, opening:, slides:)
            submitted = section(values, :box)
            mode = value(submitted, :dimension_mode).to_s
            unless %w[calculated manual].include?(mode)
              raise ParserError.new(:invalid_dimension_mode, :dimension_mode, 'Chế độ kích thước thùng không hợp lệ.')
            end
            thicknesses = BOX_THICKNESS_FIELDS.each_with_object({}) do |field, result|
              result[field] = positive_length(submitted, field)
            end
            dimensions = if mode == 'calculated'
                           calculated_box_dimensions(opening, slides)
                         else
                           BOX_DIMENSION_FIELDS.each_with_object({}) do |field, result|
                             result[field] = positive_length(submitted, field)
                           end
                         end
            merge_base(base_section).merge(thicknesses).merge(dimensions).merge(
              object_type: 'drawer_box',
              source: 'assigned',
              dimension_mode: mode
            )
          end

          def calculated_box_dimensions(opening, slides)
            result = Calculator.calculate(opening: opening, slides: slides)
            {
              box_width: result[:box_width],
              box_height: result[:box_height],
              box_depth: result[:box_depth]
            }
          rescue Calculator::CalculationError => e
            message = CALCULATION_MESSAGES.fetch(e.code, FIELD_MESSAGES.fetch(e.field, 'Không thể tính kích thước thùng ngăn kéo.'))
            raise ParserError.new(e.code, e.field, message)
          end

          def positive_length(values, field)
            to_internal(positive_number(values, field))
          end

          def positive_number(values, field)
            number = required_number(values, field)
            return number if number.positive?

            raise ParserError.new(:nonpositive_dimension, field, field_message(field))
          end

          def nonnegative_number(values, field)
            number = required_number(values, field)
            return number unless number.negative?

            raise ParserError.new(:negative_dimension, field, field_message(field))
          end

          def optional_number(values, field)
            raw = value(values, field)
            return nil if raw.nil? || raw.to_s.strip.empty?

            parse_number(raw, field)
          end

          def required_number(values, field)
            raw = value(values, field)
            if raw.nil? || raw.to_s.strip.empty?
              raise ParserError.new(:missing_field, field, field_message(field))
            end

            parse_number(raw, field)
          end

          def parse_number(raw, field)
            text = raw.to_s.strip.tr(',', '.')
            number = Float(text)
            return number if number.finite?

            raise ParserError.new(:invalid_number, field, field_message(field))
          rescue ArgumentError, TypeError
            raise ParserError.new(:invalid_number, field, field_message(field))
          end

          def to_internal(millimeters)
            CNCPlugins::Units.millimeters_to_model_units(millimeters)
          end

          def to_millimeters(value)
            rounded(CNCPlugins::Units.model_units_to_millimeters(value))
          end

          def rounded(value)
            value.to_f.round(4)
          end

          def manual_size_warnings(opening, box)
            return [] unless opening && box && box[:dimension_mode] == 'manual'
            oversized = box[:box_width] > opening[:opening_width] ||
                        box[:box_height] > opening[:opening_height] ||
                        box[:box_depth] > opening[:opening_depth]
            oversized ? ['Kích thước thùng ngăn kéo đang lớn hơn khoang lắp đặt.'] : []
          end

          def payload_hash(payload)
            values = payload.is_a?(String) ? JSON.parse(payload) : payload
            raise TypeError unless values.respond_to?(:[])

            values
          end

          def section_enabled?(values, name)
            submitted = section(values, name)
            flag = value(submitted, :enabled)
            flag == true || flag.to_s == 'true' || flag.to_s == '1'
          end

          def section(values, name)
            value(values, name) || {}
          end

          def value(values, key)
            return nil unless values.respond_to?(:[])
            return values[key] if values.respond_to?(:key?) && values.key?(key)
            return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

            nil
          end

          def optional_text(raw)
            text = raw.to_s.strip
            text.empty? ? nil : text
          end

          def merge_base(base_section)
            base_section ? base_section.dup : {}
          end

          def field_message(field)
            FIELD_MESSAGES.fetch(field, 'Giá trị đã nhập không hợp lệ.')
          end
        end
      end
    end
  end
end
