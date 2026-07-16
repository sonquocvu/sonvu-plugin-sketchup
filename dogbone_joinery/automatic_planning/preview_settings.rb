# frozen_string_literal: true

# Vietnamese input parsing and the single millimetre/model-unit conversion
# boundary for the automatic preview workflow.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PreviewSettingsError < ArgumentError
          attr_reader :code, :field

          def initialize(code, message, field: nil)
            @code = code.to_s.freeze
            @field = field && field.to_s.freeze
            super(message)
          end
        end

        class PreviewSettings
          DIMENSION_KEYS = [
            :joint_length_mm,
            :mortise_depth_mm,
            :tenon_height_mm,
            :cutter_radius_mm,
            :clearance_mm,
            :start_offset_mm,
            :end_offset_mm,
            :minimum_gap_mm,
            :geometric_tolerance_mm
          ].freeze
          KEYS = (DIMENSION_KEYS + [:requested_count]).freeze

          DEFAULTS = {
            joint_length_mm: 40.0,
            mortise_depth_mm: 10.0,
            tenon_height_mm: 10.0,
            cutter_radius_mm: 3.0,
            clearance_mm: 0.2,
            requested_count: 2,
            start_offset_mm: 20.0,
            end_offset_mm: 20.0,
            minimum_gap_mm: 10.0,
            geometric_tolerance_mm: 0.1
          }.freeze

          attr_reader :values_mm, :specification, :cutter_radius

          def initialize(values_mm:, specification:, cutter_radius: nil)
            source = values_mm.each_with_object({}) do |(key, value), result|
              result[key.to_sym] = value
            end
            source[:joint_length_mm] ||= source[:joint_width_mm]
            source[:tenon_height_mm] ||= source[:tenon_projection_mm]
            normalized = KEYS.each_with_object({}) do |key, result|
              result[key] = source[key] if source.key?(key)
            end
            @values_mm = ValueSupport.freeze_hash(normalized)
            @specification = specification
            resolved_cutter = cutter_radius
            if resolved_cutter.nil? && specification.respond_to?(:cutter_radius)
              resolved_cutter = specification.cutter_radius
            end
            @cutter_radius = resolved_cutter && resolved_cutter.to_f
            freeze
          end

          def to_h
            values_mm.dup
          end
        end

        class PreviewSettingsParser
          POSITIVE_FIELDS = {
            joint_length_mm: 'Chiều dài mộng phải lớn hơn 0.',
            mortise_depth_mm: 'Chiều sâu mộng âm phải lớn hơn 0.',
            tenon_height_mm: 'Chiều cao mộng dương phải lớn hơn 0.',
            cutter_radius_mm: 'Bán kính dao phải lớn hơn 0.'
          }.freeze
          NONNEGATIVE_FIELDS = {
            start_offset_mm: 'Khoảng cách đầu cạnh không được nhỏ hơn 0.',
            end_offset_mm: 'Khoảng cách cuối cạnh không được nhỏ hơn 0.',
            minimum_gap_mm: 'Khoảng cách tối thiểu giữa các mộng không được nhỏ hơn 0.',
            clearance_mm: 'Độ hở lắp ráp không được nhỏ hơn 0.'
          }.freeze

          def initialize(unit_converter: CNCPlugins::Units)
            @unit_converter = unit_converter
          end

          def defaults
            build(PreviewSettings::DEFAULTS)
          end

          def parse(payload)
            raise PreviewSettingsError.new('invalid_payload', 'Dữ liệu thông số không hợp lệ.') unless payload.is_a?(Hash)

            source = stringify_keys(payload)
            defaults_hash = PreviewSettings::DEFAULTS
            shared_edge_offset = if source.key?('edge_offset_mm')
                                   strict_number(source, 'edge_offset_mm')
                                 end
            values = {
              joint_length_mm: migrated_required_number(
                source,
                'joint_length_mm',
                ['joint_width_mm']
              ),
              mortise_depth_mm: optional_number(source, 'mortise_depth_mm', defaults_hash),
              tenon_height_mm: migrated_optional_number(
                source,
                'tenon_height_mm',
                'tenon_projection_mm',
                defaults_hash
              ),
              cutter_radius_mm: optional_number(source, 'cutter_radius_mm', defaults_hash),
              clearance_mm: optional_number(source, 'clearance_mm', defaults_hash),
              requested_count: strict_count(source['requested_count']),
              start_offset_mm: shared_edge_offset || strict_number(source, 'start_offset_mm'),
              end_offset_mm: shared_edge_offset || strict_number(source, 'end_offset_mm'),
              minimum_gap_mm: strict_number(source, 'minimum_gap_mm'),
              geometric_tolerance_mm: source.key?('geometric_tolerance_mm') ?
                strict_number(source, 'geometric_tolerance_mm') : defaults_hash[:geometric_tolerance_mm]
            }
            if shared_edge_offset && shared_edge_offset.negative?
              raise PreviewSettingsError.new(
                'invalid_dimension',
                'Khoảng cách hai đầu không được nhỏ hơn 0.',
                field: :edge_offset_mm
              )
            end
            validate_dimensions!(values)
            build(values)
          end

          private

          def build(values)
            specification = JointLayoutSpecification.new(
              joint_length: model_length(values[:joint_length_mm]),
              fit_clearance: model_length(values[:clearance_mm]),
              tenon_height: model_length(values[:tenon_height_mm]),
              mortise_depth: model_length(values[:mortise_depth_mm]),
              cutter_radius: model_length(values[:cutter_radius_mm]),
              requested_count: values[:requested_count],
              start_offset: model_length(values[:start_offset_mm]),
              end_offset: model_length(values[:end_offset_mm]),
              minimum_gap: model_length(values[:minimum_gap_mm]),
              geometric_tolerance: model_length(values[:geometric_tolerance_mm])
            )
            PreviewSettings.new(
              values_mm: values,
              specification: specification,
              cutter_radius: model_length(values[:cutter_radius_mm])
            )
          end

          def validate_dimensions!(values)
            POSITIVE_FIELDS.each do |field, message|
              next if values[field].positive?

              raise PreviewSettingsError.new('invalid_dimension', message, field: field)
            end
            NONNEGATIVE_FIELDS.each do |field, message|
              next if values[field] >= 0.0

              raise PreviewSettingsError.new('invalid_dimension', message, field: field)
            end
            return if values[:geometric_tolerance_mm].positive?

            raise PreviewSettingsError.new(
              'invalid_dimension',
              'Dung sai hình học phải lớn hơn 0.',
              field: :geometric_tolerance_mm
            )
          end

          def strict_number(source, key)
            value = source[key]
            raise PreviewSettingsError.new('missing_value', 'Vui lòng nhập đầy đủ các thông số.', field: key) if value.nil? || value.to_s.strip.empty?

            begin
              number = Float(value)
              raise ArgumentError unless number.finite?
            rescue ArgumentError, TypeError
              raise PreviewSettingsError.new('invalid_number', 'Giá trị phải là một số hợp lệ.', field: key)
            end

            number
          end

          def optional_number(source, key, defaults)
            return defaults[key.to_sym] unless source.key?(key)

            strict_number(source, key)
          end

          def migrated_required_number(source, current_key, legacy_keys)
            return strict_number(source, current_key) if source.key?(current_key)
            Array(legacy_keys).each do |legacy_key|
              return strict_number(source, legacy_key) if source.key?(legacy_key)
            end

            strict_number(source, current_key)
          end

          def migrated_optional_number(source, current_key, legacy_key, defaults)
            return strict_number(source, current_key) if source.key?(current_key)
            return strict_number(source, legacy_key) if source.key?(legacy_key)

            defaults[current_key.to_sym]
          end

          def strict_count(value)
            raise PreviewSettingsError.new('missing_value', 'Vui lòng nhập số lượng mộng.', field: :requested_count) if value.nil? || value.to_s.strip.empty?

            begin
              number = Float(value)
            rescue ArgumentError, TypeError
              raise PreviewSettingsError.new(
                'invalid_count',
                'Số lượng mộng phải là số nguyên lớn hơn 0.',
                field: :requested_count
              )
            end
            integer = number.to_i
            unless number.finite? && number == integer.to_f && integer.positive?
              raise PreviewSettingsError.new(
                'invalid_count',
                'Số lượng mộng phải là số nguyên lớn hơn 0.',
                field: :requested_count
              )
            end
            integer
          end

          def model_length(value_mm)
            @unit_converter.millimeters_to_model_units(value_mm)
          end

          def stringify_keys(hash)
            hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
          end
        end
      end
    end
  end
end
