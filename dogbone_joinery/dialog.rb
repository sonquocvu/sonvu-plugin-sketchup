# frozen_string_literal: true

# Dialog behavior for Dogbone Joinery. It collects user parameters in
# millimeters, validates them, and returns SketchUp internal length values.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Dialog
        SUCCESS_MESSAGE = 'SonVu CNC Plugins - Dogbone Joinery loaded successfully.'
        INPUT_TITLE = 'Dogbone Joinery'
        PROMPTS = [
          'Preset',
          'Mortise width mm',
          'Mortise height mm',
          'Mortise depth mm',
          'Tenon length mm',
          'Cutter diameter mm',
          'Clearance mm',
          'Dogbone style',
          'Create mortise',
          'Create tenon',
          'Add labels'
        ].freeze
        DOGBONE_STYLES = ['Horizontal T-bone', 'Vertical T-bone', 'Diagonal'].freeze
        PRESET_NAMES = CNCPlugins::DOGBONE_PRESETS.keys.freeze
        NUMERIC_DEFAULTS_MM = {
          mortise_width_mm: 80,
          mortise_height_mm: 20,
          mortise_depth_mm: 18,
          tenon_length_mm: 18,
          cutter_diameter_mm: 6,
          clearance_mm: 0.2
        }.freeze
        DEFAULTS = [
          PRESET_NAMES.first,
          NUMERIC_DEFAULTS_MM[:mortise_width_mm],
          NUMERIC_DEFAULTS_MM[:mortise_height_mm],
          NUMERIC_DEFAULTS_MM[:mortise_depth_mm],
          NUMERIC_DEFAULTS_MM[:tenon_length_mm],
          NUMERIC_DEFAULTS_MM[:cutter_diameter_mm],
          NUMERIC_DEFAULTS_MM[:clearance_mm],
          DOGBONE_STYLES.first,
          'Yes',
          'No',
          'No'
        ].freeze
        LISTS = [
          PRESET_NAMES.join('|'),
          '',
          '',
          '',
          '',
          '',
          '',
          DOGBONE_STYLES.join('|'),
          'Yes|No',
          'Yes|No',
          'Yes|No'
        ].freeze

        module_function

        def open
          settings = show
          return unless settings

          CNCPlugins::UIHelpers.message(selected_values_message(settings))
        end

        def show
          input = UI.inputbox(PROMPTS, DEFAULTS, LISTS, INPUT_TITLE)
          return nil unless input

          values = parse_input(input)
          validation_error = validate(values)
          if validation_error
            CNCPlugins::UIHelpers.message(validation_error)
            return nil
          end

          to_settings_hash(values)
        end

        def parse_input(input)
          selected_preset = input[0].to_s.strip
          {
            preset: selected_preset,
            mortise_width_mm: preset_or_manual_value(selected_preset, :mortise_width_mm, input[1]),
            mortise_height_mm: preset_or_manual_value(selected_preset, :mortise_height_mm, input[2]),
            mortise_depth_mm: preset_or_manual_value(selected_preset, :mortise_depth_mm, input[3]),
            tenon_length_mm: preset_or_manual_value(selected_preset, :tenon_length_mm, input[4]),
            cutter_diameter_mm: preset_or_manual_value(selected_preset, :cutter_diameter_mm, input[5]),
            clearance_mm: preset_or_manual_value(selected_preset, :clearance_mm, input[6]),
            dogbone_style: input[7].to_s.strip,
            create_mortise: boolean_value(input[8]),
            create_tenon: boolean_value(input[9]),
            add_labels: boolean_value(input[10])
          }
        end

        def validate(values)
          return 'Please enter numeric values for all dimensions.' if numeric_values_invalid?(values)
          return unsupported_preset_message(values[:preset]) unless supported_preset?(values[:preset])
          return 'Mortise width must be greater than 0 mm.' unless values[:mortise_width_mm].positive?
          return 'Mortise height must be greater than 0 mm.' unless values[:mortise_height_mm].positive?
          return 'Mortise depth must be greater than 0 mm.' unless values[:mortise_depth_mm].positive?
          return 'Tenon length must be greater than 0 mm.' unless values[:tenon_length_mm].positive?
          return 'Cutter diameter must be greater than 0 mm.' unless values[:cutter_diameter_mm].positive?
          return 'Clearance must be 0 mm or greater.' if values[:clearance_mm].negative?
          return unsupported_style_message(values[:dogbone_style]) unless supported_style?(values[:dogbone_style])

          tenon_width_mm = values[:mortise_width_mm] - values[:clearance_mm]
          tenon_height_mm = values[:mortise_height_mm] - values[:clearance_mm]
          return 'Tenon width must remain greater than 0 mm after clearance.' unless tenon_width_mm.positive?
          return 'Tenon height must remain greater than 0 mm after clearance.' unless tenon_height_mm.positive?

          nil
        end

        def numeric_values_invalid?(values)
          %i[
            mortise_width_mm
            mortise_height_mm
            mortise_depth_mm
            tenon_length_mm
            cutter_diameter_mm
            clearance_mm
          ].any? { |key| values[key].nil? }
        end

        def to_settings_hash(values)
          {
            mortise_width: mm_to_length(values[:mortise_width_mm]),
            mortise_height: mm_to_length(values[:mortise_height_mm]),
            mortise_depth: mm_to_length(values[:mortise_depth_mm]),
            tenon_length: mm_to_length(values[:tenon_length_mm]),
            cutter_diameter: mm_to_length(values[:cutter_diameter_mm]),
            clearance: mm_to_length(values[:clearance_mm]),
            preset: values[:preset],
            dogbone_style: values[:dogbone_style],
            create_mortise: values[:create_mortise],
            create_tenon: values[:create_tenon],
            add_labels: values[:add_labels]
          }
        end

        def selected_values_message(settings)
          lines = [
            SUCCESS_MESSAGE,
            '',
            "Mortise width: #{format_length(settings[:mortise_width])} mm",
            "Mortise height: #{format_length(settings[:mortise_height])} mm",
            "Mortise depth: #{format_length(settings[:mortise_depth])} mm",
            "Tenon length: #{format_length(settings[:tenon_length])} mm",
            "Cutter diameter: #{format_length(settings[:cutter_diameter])} mm",
            "Clearance: #{format_length(settings[:clearance])} mm",
            "Preset: #{settings[:preset]}",
            "Dogbone style: #{settings[:dogbone_style]}",
            "Create mortise: #{settings[:create_mortise]}",
            "Create tenon: #{settings[:create_tenon]}",
            "Add labels: #{settings[:add_labels]}"
          ]
          lines.join("\n")
        end

        def numeric_value(value)
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def boolean_value(value)
          return value if value == true || value == false

          normalized_value = value.to_s.strip
          normalized_value.casecmp('yes').zero? || normalized_value.casecmp('true').zero?
        end

        def preset_or_manual_value(preset_name, key, input_value)
          manual_value = numeric_value(input_value)
          return manual_value unless preset_applies_to_value?(preset_name, key, manual_value)

          CNCPlugins::DOGBONE_PRESETS.fetch(preset_name).fetch(key)
        end

        def preset_applies_to_value?(preset_name, key, manual_value)
          preset = CNCPlugins::DOGBONE_PRESETS[preset_name]
          return false unless preset && preset.key?(key)

          manual_value == NUMERIC_DEFAULTS_MM.fetch(key)
        end

        def supported_style?(style)
          DOGBONE_STYLES.include?(style)
        end

        def supported_preset?(preset)
          PRESET_NAMES.include?(preset)
        end

        def unsupported_style_message(style)
          "Unsupported dogbone style: #{style}. Supported styles: #{DOGBONE_STYLES.join(', ')}."
        end

        def unsupported_preset_message(preset)
          "Unsupported preset: #{preset}. Supported presets: #{PRESET_NAMES.join(', ')}."
        end

        def mm_to_length(value)
          CNCPlugins::Units.millimeters_to_model_units(value)
        end

        def format_length(length)
          millimeters = CNCPlugins::Units.model_units_to_millimeters(length)
          format('%.3f', millimeters).sub(/\.?0+$/, '')
        end
      end
    end
  end
end
