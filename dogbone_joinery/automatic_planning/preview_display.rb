# frozen_string_literal: true

# Display-only preferences and drawing styles for the automatic-joint preview.
# These values never participate in planning or model generation.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        class PreviewDisplaySettings
          BOOLEAN_FIELDS = %i[
            show_tenons show_mortises show_contact_region show_legend
          ].freeze
          ATTRIBUTES = BOOLEAN_FIELDS

          attr_reader(*ATTRIBUTES)

          def self.defaults
            new(
              show_tenons: true,
              show_mortises: true,
              show_contact_region: true,
              show_legend: true
            )
          end

          def self.from_payload(payload, current: defaults)
            raise ArgumentError, 'Thiết lập hiển thị xem trước không hợp lệ.' unless payload.is_a?(Hash)

            attributes = current.to_h
            ATTRIBUTES.each do |name|
              string_key = name.to_s
              next unless payload.key?(string_key) || payload.key?(name)

              value = payload.key?(string_key) ? payload[string_key] : payload[name]
              attributes[name] = value
            end
            new(attributes)
          end

          def initialize(attributes)
            BOOLEAN_FIELDS.each do |name|
              value = attributes.fetch(name)
              unless value == true || value == false
                raise ArgumentError, "Thiết lập #{name} phải là trạng thái bật hoặc tắt."
              end

              instance_variable_set("@#{name}", value)
            end
            freeze
          end

          def to_h
            ATTRIBUTES.each_with_object({}) do |name, result|
              result[name] = public_send(name)
            end
          end
        end

        module PreviewDisplayStyles
          STYLES = ValueSupport.freeze_hash(
            tenon: {
              color: [0, 139, 210],
              line_width: 5,
              line_stipple: '',
              point_size: 13
            },
            mortise: {
              color: [238, 126, 34],
              line_width: 3,
              line_stipple: '-',
              point_size: 11
            },
            invalid: {
              color: [210, 42, 42],
              line_width: 5,
              line_stipple: '-.',
              point_size: 15
            },
            disabled: {
              color: [125, 132, 128],
              line_width: 2,
              line_stipple: '.',
              point_size: 9
            },
            contact: {
              color: [82, 96, 88],
              line_width: 1,
              line_stipple: '',
              point_size: 7
            },
            male_board: {
              color: [65, 159, 216],
              line_width: 2,
              line_stipple: '',
              point_size: 7
            },
            female_board: {
              color: [234, 154, 82],
              line_width: 2,
              line_stipple: '-',
              point_size: 7
            },
            simplified: {
              color: [82, 124, 105],
              line_width: 2,
              line_stipple: '',
              point_size: 9
            },
            connector: {
              color: [112, 92, 151],
              line_width: 1,
              line_stipple: '.',
              point_size: 7
            },
            label: {
              color: [30, 39, 34],
              line_width: 1,
              line_stipple: '',
              point_size: 7
            }
          )

          module_function

          def fetch(name)
            STYLES.fetch(name.to_sym)
          end
        end
      end
    end
  end
end
