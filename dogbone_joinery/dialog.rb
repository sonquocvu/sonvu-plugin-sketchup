# frozen_string_literal: true

require 'json'

# Dialog behavior for Dogbone Joinery. It collects user parameters in
# millimeters, validates them, and returns SketchUp internal length values.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Dialog
        SUCCESS_MESSAGE = 'SonVu CNC Plugins - Mộng xương chó đã sẵn sàng.'
        INPUT_TITLE = 'Tạo mộng xương chó'
        MORTISE_TITLE = 'Tạo mộng âm'
        TENON_TITLE = 'Tạo mộng dương'
        YES = 'Có'
        NO = 'Không'
        PROMPTS = [
          'Cấu hình mẫu',
          'Rộng mộng âm (mm)',
          'Cao mộng âm (mm)',
          'Sâu mộng âm (mm)',
          'Đường kính dao CNC (mm)',
          'Độ hở lắp ráp (mm)',
          'Khoét góc mộng âm?',
          'Tạo mộng âm?',
          'Cắt mộng âm vào khối đã chọn?',
          'Rộng mộng dương (mm)',
          'Dày mộng dương (mm)',
          'Tạo mộng dương?',
          'Khoét bán nguyệt hai đầu mộng dương?',
          'Thêm nhãn?'
        ].freeze
        DOGBONE_STYLES = ['Ngang (T-bone)', 'Dọc (T-bone)', 'Chéo'].freeze
        PRESET_NAMES = CNCPlugins::DOGBONE_PRESETS.keys.freeze
        NUMERIC_DEFAULTS_MM = {
          mortise_width_mm: 80,
          mortise_height_mm: 20,
          mortise_depth_mm: 18,
          cutter_diameter_mm: 6,
          clearance_mm: 0.2,
          tenon_width_mm: 80,
          tenon_thickness_mm: 18
        }.freeze
        DEFAULTS = [
          PRESET_NAMES.first,
          NUMERIC_DEFAULTS_MM[:mortise_width_mm],
          NUMERIC_DEFAULTS_MM[:mortise_height_mm],
          NUMERIC_DEFAULTS_MM[:mortise_depth_mm],
          NUMERIC_DEFAULTS_MM[:cutter_diameter_mm],
          NUMERIC_DEFAULTS_MM[:clearance_mm],
          DOGBONE_STYLES.first,
          YES,
          NO,
          NUMERIC_DEFAULTS_MM[:tenon_width_mm],
          NUMERIC_DEFAULTS_MM[:tenon_thickness_mm],
          NO,
          YES,
          NO
        ].freeze
        LISTS = [
          PRESET_NAMES.join('|'),
          '',
          '',
          '',
          '',
          '',
          DOGBONE_STYLES.join('|'),
          "#{YES}|#{NO}",
          "#{YES}|#{NO}",
          '',
          '',
          "#{YES}|#{NO}",
          "#{YES}|#{NO}",
          "#{YES}|#{NO}"
        ].freeze

        module_function

        def open
          show do |settings|
            CNCPlugins::UIHelpers.message(selected_values_message(settings))
          end
        end

        def show(selected_face: nil, mode: :joint, &block)
          mode = normalized_mode(mode)
          return show_inputbox(mode: mode, &block) unless html_dialog_supported?

          face_context = selected_face_context(selected_face)
          dialog = create_html_dialog(mode)
          @dialog = dialog
          dialog.add_action_callback('submitForm') do |_action_context, payload|
            handle_html_submission(dialog, payload, face_context, &block)
          end
          dialog.add_action_callback('cancelForm') do
            @dialog = nil
            dialog.close
          end
          dialog.set_html(DogboneJoinery::DialogHTML.html(face_context, mode))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        end

        def show_inputbox(mode: :joint)
          input = UI.inputbox(PROMPTS, defaults_for_mode(mode), LISTS, dialog_title(mode))
          return nil unless input

          values = parse_input(input, selected_face_context(nil))
          validation_error = validate(values)
          if validation_error
            CNCPlugins::UIHelpers.message(validation_error)
            return nil
          end

          settings = to_settings_hash(values)
          yield settings if block_given?
          settings
        end

        def html_dialog_supported?
          defined?(::UI::HtmlDialog)
        end

        def create_html_dialog(mode)
          options = {
            dialog_title: dialog_title(mode),
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.dogbone_joinery",
            scrollable: true,
            resizable: true,
            width: 540,
            height: 720
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          ::UI::HtmlDialog.new(options)
        end

        def normalized_mode(mode)
          %i[mortise tenon].include?(mode) ? mode : :joint
        end

        def dialog_title(mode)
          case mode
          when :mortise
            MORTISE_TITLE
          when :tenon
            TENON_TITLE
          else
            INPUT_TITLE
          end
        end

        def defaults_for_mode(mode)
          values = DEFAULTS.dup
          case mode
          when :mortise
            values[7] = YES
            values[11] = NO
          when :tenon
            values[7] = NO
            values[11] = YES
          end
          values
        end

        def handle_html_submission(dialog, payload, face_context)
          values = parse_html_payload(payload, face_context)
          validation_error = validate(values)
          if validation_error
            show_html_error(dialog, validation_error)
            return nil
          end

          settings = to_settings_hash(values)
          @dialog = nil
          dialog.close
          yield settings if block_given?
          settings
        rescue JSON::ParserError, TypeError
          show_html_error(dialog, 'Không đọc được dữ liệu từ hộp thoại. Vui lòng thử lại.')
          nil
        end

        def parse_html_payload(payload, face_context)
          input = JSON.parse(payload.to_s)
          parse_hash(input, face_context)
        end

        def show_html_error(dialog, message)
          dialog.execute_script("showError(#{JSON.generate(message)});")
        end

        def selected_face_context(face)
          return { selected: false, side_face: false, height_mm: nil, height_label: 'Chưa chọn mặt cạnh' } unless face

          height = side_face_height(face)
          height_mm = height ? CNCPlugins::Units.model_units_to_millimeters(height) : nil
          {
            selected: true,
            side_face: side_face?(face) && height_mm&.positive?,
            height_mm: height_mm,
            height_label: height_mm&.positive? ? "#{format('%.3f', height_mm).sub(/\.?0+$/, '')} mm" : 'Không đọc được'
          }
        end

        def side_face?(face)
          return false unless defined?(::Sketchup::Face) && face.is_a?(::Sketchup::Face)

          face.normal.z.abs < 0.15
        end

        def side_face_height(face)
          return nil unless face.respond_to?(:bounds)

          height = face.bounds.depth
          height.positive? ? height : nil
        end

        def parse_input(input, face_context = selected_face_context(nil))
          parse_hash(
            {
              'preset' => input[0],
              'mortise_width_mm' => input[1],
              'mortise_height_mm' => input[2],
              'mortise_depth_mm' => input[3],
              'cutter_diameter_mm' => input[4],
              'clearance_mm' => input[5],
              'dogbone_style' => input[6],
              'create_mortise' => input[7],
              'cut_mortise_into_selected_solid' => input[8],
              'tenon_width_mm' => input[9],
              'tenon_thickness_mm' => input[10],
              'create_tenon' => input[11],
              'tenon_relief_enabled' => input[12],
              'add_labels' => input[13]
            },
            face_context
          )
        end

        def parse_hash(input, face_context)
          selected_preset = input[0].to_s.strip
          selected_preset = input['preset'].to_s.strip if input.respond_to?(:[])
          {
            preset: selected_preset,
            mortise_width_mm: preset_or_manual_value(selected_preset, :mortise_width_mm, input['mortise_width_mm']),
            mortise_height_mm: preset_or_manual_value(selected_preset, :mortise_height_mm, input['mortise_height_mm']),
            mortise_depth_mm: preset_or_manual_value(selected_preset, :mortise_depth_mm, input['mortise_depth_mm']),
            cutter_diameter_mm: preset_or_manual_value(selected_preset, :cutter_diameter_mm, input['cutter_diameter_mm']),
            clearance_mm: preset_or_manual_value(selected_preset, :clearance_mm, input['clearance_mm']),
            dogbone_style: input['dogbone_style'].to_s.strip,
            create_mortise: boolean_value(input['create_mortise']),
            cut_mortise_into_selected_solid: boolean_value(input['cut_mortise_into_selected_solid']),
            tenon_width_mm: numeric_value(input['tenon_width_mm']),
            tenon_height_mm: face_context[:height_mm],
            tenon_thickness_mm: preset_or_manual_value(selected_preset, :tenon_length_mm, input['tenon_thickness_mm']),
            create_tenon: boolean_value(input['create_tenon']),
            tenon_relief_enabled: boolean_value(input['tenon_relief_enabled']),
            add_labels: boolean_value(input['add_labels']),
            selected_face: face_context[:selected],
            selected_side_face: face_context[:side_face]
          }
        end

        def validate(values)
          return unsupported_preset_message(values[:preset]) unless supported_preset?(values[:preset])
          return 'Vui lòng bật ít nhất một phần: tạo mộng âm hoặc tạo mộng dương.' unless values[:create_mortise] || values[:create_tenon] || values[:cut_mortise_into_selected_solid]
          return 'Vui lòng nhập số hợp lệ cho tất cả kích thước mộng âm.' if mortise_values_invalid?(values)
          return 'Chiều rộng mộng âm phải lớn hơn 0.' unless values[:mortise_width_mm].positive?
          return 'Chiều cao mộng âm phải lớn hơn 0.' unless values[:mortise_height_mm].positive?
          return 'Chiều sâu mộng âm phải lớn hơn 0.' unless values[:mortise_depth_mm].positive?
          return 'Đường kính dao CNC phải lớn hơn 0.' unless values[:cutter_diameter_mm].positive?
          return 'Độ hở lắp ráp không được nhỏ hơn 0.' if values[:clearance_mm].negative?
          return unsupported_style_message(values[:dogbone_style]) unless supported_style?(values[:dogbone_style])

          return validate_tenon(values) if values[:create_tenon]

          nil
        end

        def mortise_values_invalid?(values)
          %i[
            mortise_width_mm
            mortise_height_mm
            mortise_depth_mm
            cutter_diameter_mm
            clearance_mm
          ].any? { |key| values[key].nil? }
        end

        def validate_tenon(values)
          return 'Vui lòng chọn đúng một mặt cạnh của model trước khi tạo mộng dương.' unless values[:selected_face]
          return 'Mộng dương chỉ được tạo trên mặt cạnh thẳng đứng của model, không tạo trên mặt trên hoặc mặt đáy.' unless values[:selected_side_face]
          return 'Không đọc được chiều cao từ mặt cạnh đã chọn.' unless values[:tenon_height_mm]&.positive?
          return 'Vui lòng nhập số hợp lệ cho rộng và dày mộng dương.' if values[:tenon_width_mm].nil? || values[:tenon_thickness_mm].nil?
          return 'Rộng mộng dương phải lớn hơn 0.' unless values[:tenon_width_mm].positive?
          return 'Dày mộng dương phải lớn hơn 0.' unless values[:tenon_thickness_mm].positive?

          nil
        end

        def to_settings_hash(values)
          {
            mortise_width: mm_to_length(values[:mortise_width_mm]),
            mortise_height: mm_to_length(values[:mortise_height_mm]),
            mortise_depth: mm_to_length(values[:mortise_depth_mm]),
            cutter_diameter: mm_to_length(values[:cutter_diameter_mm]),
            clearance: mm_to_length(values[:clearance_mm]),
            tenon_width: mm_to_length(values[:tenon_width_mm] || values[:mortise_width_mm]),
            tenon_height: mm_to_length(values[:tenon_height_mm] || values[:mortise_height_mm]),
            tenon_thickness: mm_to_length(values[:tenon_thickness_mm] || values[:mortise_depth_mm]),
            tenon_length: mm_to_length(values[:tenon_thickness_mm] || values[:mortise_depth_mm]),
            preset: values[:preset],
            dogbone_style: values[:dogbone_style],
            create_mortise: values[:create_mortise],
            create_tenon: values[:create_tenon],
            tenon_relief_enabled: values[:tenon_relief_enabled],
            add_labels: values[:add_labels],
            cut_mortise_into_selected_solid: values[:cut_mortise_into_selected_solid]
          }
        end

        def selected_values_message(settings)
          lines = [
            SUCCESS_MESSAGE,
            '',
            "Rộng mộng âm: #{format_length(settings[:mortise_width])} mm",
            "Cao mộng âm: #{format_length(settings[:mortise_height])} mm",
            "Sâu mộng âm: #{format_length(settings[:mortise_depth])} mm",
            "Đường kính dao CNC: #{format_length(settings[:cutter_diameter])} mm",
            "Độ hở lắp ráp: #{format_length(settings[:clearance])} mm",
            "Cấu hình mẫu: #{settings[:preset]}",
            "Khoét góc mộng âm: #{settings[:dogbone_style]}",
            "Tạo mộng âm: #{format_boolean(settings[:create_mortise])}",
            "Cắt mộng âm vào khối đã chọn: #{format_boolean(settings[:cut_mortise_into_selected_solid])}",
            "Tạo mộng dương: #{format_boolean(settings[:create_tenon])}",
            "Rộng mộng dương: #{format_length(settings[:tenon_width])} mm",
            "Cao mộng dương theo mặt chọn: #{format_length(settings[:tenon_height])} mm",
            "Dày mộng dương: #{format_length(settings[:tenon_thickness])} mm",
            "Khoét bán nguyệt hai đầu mộng dương: #{format_boolean(settings[:tenon_relief_enabled])}",
            "Thêm nhãn: #{format_boolean(settings[:add_labels])}"
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
          normalized_value.casecmp(YES).zero? ||
            normalized_value.casecmp('yes').zero? ||
            normalized_value.casecmp('true').zero?
        end

        def preset_or_manual_value(preset_name, key, input_value)
          manual_value = numeric_value(input_value)
          return manual_value unless preset_applies_to_value?(preset_name, key, manual_value)

          CNCPlugins::DOGBONE_PRESETS.fetch(preset_name).fetch(key)
        end

        def preset_applies_to_value?(preset_name, key, manual_value)
          preset = CNCPlugins::DOGBONE_PRESETS[preset_name]
          return false unless preset && preset.key?(key)

          manual_value == default_numeric_value(key)
        end

        def default_numeric_value(key)
          return NUMERIC_DEFAULTS_MM.fetch(:tenon_thickness_mm) if key == :tenon_length_mm

          NUMERIC_DEFAULTS_MM.fetch(key)
        end

        def supported_style?(style)
          DOGBONE_STYLES.include?(style)
        end

        def supported_preset?(preset)
          PRESET_NAMES.include?(preset)
        end

        def unsupported_style_message(style)
          "Kiểu khoét góc mộng âm không hỗ trợ: #{style}. Các kiểu hợp lệ: #{DOGBONE_STYLES.join(', ')}."
        end

        def unsupported_preset_message(preset)
          "Cấu hình mẫu không hỗ trợ: #{preset}. Các cấu hình hợp lệ: #{PRESET_NAMES.join(', ')}."
        end

        def mm_to_length(value)
          CNCPlugins::Units.millimeters_to_model_units(value)
        end

        def format_length(length)
          millimeters = CNCPlugins::Units.model_units_to_millimeters(length)
          format('%.3f', millimeters).sub(/\.?0+$/, '')
        end

        def format_boolean(value)
          value ? YES : NO
        end
      end
    end
  end
end
