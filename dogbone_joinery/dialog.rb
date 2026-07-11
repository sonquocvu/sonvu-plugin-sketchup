# frozen_string_literal: true

require 'json'

# Dialog behavior for Dogbone Joinery. It collects user parameters in
# millimeters, validates them, and returns SketchUp internal length values.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Dialog
        SUCCESS_MESSAGE = 'SonVu CNC Plugins - Mộng xương chó đã sẵn sàng.'
        MORTISE_TITLE = 'Tạo mộng âm'
        TENON_TITLE = 'Tạo mộng dương'
        YES = 'Có'
        NO = 'Không'
        PROMPTS = [
          'Cấu hình mẫu',
          'Rộng mộng âm (mm)',
          'Cao mộng âm (mm)',
          'Sâu mộng âm (mm)',
          'Bán kính dao (mm)',
          'Độ hở lắp ráp (mm)',
          'Khoét góc mộng âm?',
          'Tạo mộng âm?',
          'Cắt mộng âm vào khối đã chọn?',
          'Rộng mộng dương (mm)',
          'Độ vươn mộng dương từ mặt đã chọn (mm)',
          'Bán kính dao (mm)',
          'Số lượng mộng dương',
          'Lề hai đầu cạnh (mm)',
          'Tạo mộng dương?',
          'Khoét bán nguyệt hai đầu mộng dương?',
          'Thêm nhãn?'
        ].freeze
        DOGBONE_STYLES = ['Ngang (T-bone)', 'Dọc (T-bone)', 'Chéo'].freeze
        DEFAULT_DOGBONE_STYLE = 'Ngang (T-bone)'
        PRESET_NAMES = CNCPlugins::DOGBONE_PRESETS.keys.freeze
        NUMERIC_DEFAULTS_MM = {
          mortise_width_mm: 20,
          mortise_height_mm: 20,
          mortise_depth_mm: 10,
          cutter_radius_mm: 3,
          clearance_mm: 0.2,
          tenon_width_mm: 40,
          tenon_thickness_mm: 10,
          tenon_cutter_radius_mm: 3,
          tenon_count: 2,
          tenon_edge_offset_mm: 20
        }.freeze
        DEFAULTS = [
          PRESET_NAMES.first,
          NUMERIC_DEFAULTS_MM[:mortise_width_mm],
          NUMERIC_DEFAULTS_MM[:mortise_height_mm],
          NUMERIC_DEFAULTS_MM[:mortise_depth_mm],
          NUMERIC_DEFAULTS_MM[:cutter_radius_mm],
          NUMERIC_DEFAULTS_MM[:clearance_mm],
          DEFAULT_DOGBONE_STYLE,
          YES,
          NO,
          NUMERIC_DEFAULTS_MM[:tenon_width_mm],
          NUMERIC_DEFAULTS_MM[:tenon_thickness_mm],
          NUMERIC_DEFAULTS_MM[:tenon_cutter_radius_mm],
          NUMERIC_DEFAULTS_MM[:tenon_count],
          NUMERIC_DEFAULTS_MM[:tenon_edge_offset_mm],
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
          '',
          '',
          '',
          "#{YES}|#{NO}",
          "#{YES}|#{NO}",
          "#{YES}|#{NO}"
        ].freeze

        module_function

        def open
          show(mode: :mortise) do |settings|
            CNCPlugins::UIHelpers.message(selected_values_message(settings))
          end
        end

        def show(selected_face: nil, mode: :mortise, &block)
          mode = normalized_mode(mode)
          return show_inputbox(mode: mode, face_context: selected_face_context(selected_face), &block) unless html_dialog_supported?

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

        def show_inputbox(mode: :mortise, face_context: selected_face_context(nil))
          input = UI.inputbox(PROMPTS, defaults_for_mode(mode), LISTS, dialog_title(mode))
          return nil unless input

          values = parse_input(input, face_context)
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
          %i[mortise tenon].include?(mode) ? mode : :mortise
        end

        def dialog_title(mode)
          case mode
          when :mortise
            MORTISE_TITLE
          when :tenon
            TENON_TITLE
          else
            MORTISE_TITLE
          end
        end

        def defaults_for_mode(mode)
          values = DEFAULTS.dup
          case mode
          when :mortise
            values[7] = YES
            values[14] = NO
          when :tenon
            values[7] = NO
            values[14] = YES
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
          return {
            selected: false,
            side_face: false,
            width_mm: nil,
            height_mm: nil,
            depth_mm: nil,
            width_label: 'Chưa chọn mặt',
            height_label: 'Chưa chọn mặt',
            depth_label: 'Chưa chọn mặt'
          } unless face

          dimensions = face_dimensions(face)
          width_mm = dimensions ? CNCPlugins::Units.model_units_to_millimeters(dimensions[:width]) : nil
          height_mm = dimensions ? CNCPlugins::Units.model_units_to_millimeters(dimensions[:height]) : nil
          model_depth = face_model_depth(face)
          depth_mm = model_depth ? CNCPlugins::Units.model_units_to_millimeters(model_depth) : nil
          valid_face = width_mm&.positive? && height_mm&.positive?
          {
            selected: true,
            side_face: valid_face,
            width_mm: width_mm,
            height_mm: height_mm,
            depth_mm: depth_mm,
            width_label: width_mm&.positive? ? format_mm(width_mm) : 'Không đọc được',
            height_label: height_mm&.positive? ? format_mm(height_mm) : 'Không đọc được',
            depth_label: depth_mm&.positive? ? format_mm(depth_mm) : 'Không đọc được'
          }
        end

        def side_face?(face)
          dimensions = face_dimensions(face)
          dimensions && dimensions[:width].positive? && dimensions[:height].positive?
        end

        def side_face_height(face)
          dimensions = face_dimensions(face)
          dimensions && dimensions[:height]
        end

        def face_dimensions(face)
          return nil unless face.respond_to?(:edges) && face.respond_to?(:vertices) && face.respond_to?(:normal)

          edge = face.edges.max_by(&:length)
          vertices = face.vertices.map(&:position)
          return nil unless edge && vertices.length >= 3

          xaxis = edge.end.position - edge.start.position
          return nil if xaxis.length <= 0.001

          xaxis.normalize!
          normal = Geom::Vector3d.new(face.normal.x, face.normal.y, face.normal.z)
          normal.normalize!
          yaxis = normal * xaxis
          return nil if yaxis.length <= 0.001

          yaxis.normalize!
          reference = vertices.first
          x_values = vertices.map { |vertex| vector_projection(vertex - reference, xaxis) }
          y_values = vertices.map { |vertex| vector_projection(vertex - reference, yaxis) }

          {
            width: x_values.max - x_values.min,
            height: y_values.max - y_values.min
          }
        end

        def face_model_depth(face)
          return nil unless face.respond_to?(:all_connected) && face.respond_to?(:normal)

          connected_entities = face.all_connected + [face]
          vertices = connected_entities.flat_map do |entity|
            if entity.respond_to?(:vertices)
              entity.vertices
            elsif entity.respond_to?(:position)
              [entity]
            else
              []
            end
          end.uniq
          return nil if vertices.empty?

          normal = Geom::Vector3d.new(face.normal.x, face.normal.y, face.normal.z)
          return nil if normal.length <= 0.001

          normal.normalize!
          reference = vertices.first.position
          projections = vertices.map { |vertex| vector_projection(vertex.position - reference, normal) }
          depth = projections.max - projections.min
          depth.positive? ? depth : nil
        end

        def vector_projection(vector, axis)
          (vector.x * axis.x) + (vector.y * axis.y) + (vector.z * axis.z)
        end

        def format_mm(value)
          "#{format('%.3f', value).sub(/\.?0+$/, '')} mm"
        end

        def parse_input(input, face_context = selected_face_context(nil))
          parse_hash(
            {
              'preset' => input[0],
              'mortise_width_mm' => input[1],
              'mortise_height_mm' => input[2],
              'mortise_depth_mm' => input[3],
              'cutter_radius_mm' => input[4],
              'clearance_mm' => input[5],
              'dogbone_style' => input[6],
              'create_mortise' => input[7],
              'cut_mortise_into_selected_solid' => input[8],
              'tenon_width_mm' => input[9],
              'tenon_thickness_mm' => input[10],
              'tenon_cutter_radius_mm' => input[11],
              'tenon_count' => input[12],
              'tenon_edge_offset_mm' => input[13],
              'create_tenon' => input[14],
              'tenon_relief_enabled' => input[15],
              'add_labels' => input[16]
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
            cutter_radius_mm: preset_or_manual_value(selected_preset, :cutter_radius_mm, input['cutter_radius_mm']),
            clearance_mm: preset_or_manual_value(selected_preset, :clearance_mm, input['clearance_mm']),
            dogbone_style: input['dogbone_style'].to_s.strip,
            create_mortise: boolean_value(input['create_mortise']),
            cut_mortise_into_selected_solid: boolean_value(input['cut_mortise_into_selected_solid']),
            tenon_width_mm: numeric_value(input['tenon_width_mm']),
            tenon_face_width_mm: face_context[:width_mm],
            tenon_height_mm: face_context[:height_mm],
            tenon_thickness_mm: preset_or_manual_value(selected_preset, :tenon_length_mm, input['tenon_thickness_mm']),
            tenon_cutter_radius_mm: numeric_value(input['tenon_cutter_radius_mm']),
            tenon_count: integer_value(input['tenon_count']),
            tenon_edge_offset_mm: numeric_value(input['tenon_edge_offset_mm']),
            create_tenon: boolean_value(input['create_tenon']),
            tenon_relief_enabled: boolean_value(input['tenon_relief_enabled']),
            add_labels: boolean_value(input['add_labels']),
            selected_face: face_context[:selected],
            selected_side_face: face_context[:side_face],
            selected_face_width_mm: face_context[:width_mm],
            selected_face_height_mm: face_context[:height_mm],
            selected_model_depth_mm: face_context[:depth_mm]
          }
        end

        def validate(values)
          return unsupported_preset_message(values[:preset]) unless supported_preset?(values[:preset])
          return 'Vui lòng bật ít nhất một phần: tạo mộng âm hoặc tạo mộng dương.' unless values[:create_mortise] || values[:create_tenon] || values[:cut_mortise_into_selected_solid]
          return 'Vui lòng nhập số hợp lệ cho tất cả kích thước mộng âm.' if mortise_values_invalid?(values)
          return 'Chiều rộng mộng âm phải lớn hơn 0.' unless values[:mortise_width_mm].positive?
          return 'Chiều cao mộng âm phải lớn hơn 0.' unless values[:mortise_height_mm].positive?
          return 'Chiều sâu mộng âm phải lớn hơn 0.' unless values[:mortise_depth_mm].positive?
          return 'Bán kính dao phải lớn hơn 0.' unless values[:cutter_radius_mm].positive?
          return 'Độ hở lắp ráp không được nhỏ hơn 0.' if values[:clearance_mm].negative?
          return unsupported_style_message(values[:dogbone_style]) unless supported_style?(values[:dogbone_style])

          mortise_error = validate_mortise(values) if values[:create_mortise] || values[:cut_mortise_into_selected_solid]
          return mortise_error if mortise_error

          return validate_tenon(values) if values[:create_tenon]

          nil
        end

        def mortise_values_invalid?(values)
          %i[
            mortise_width_mm
            mortise_height_mm
            mortise_depth_mm
            cutter_radius_mm
            clearance_mm
          ].any? { |key| values[key].nil? }
        end

        def validate_mortise(values)
          return 'Vui lòng chọn đúng một mặt phẳng của model trước khi tạo mộng âm.' unless values[:selected_face]
          unless values[:selected_face_width_mm]&.positive? && values[:selected_face_height_mm]&.positive?
            return 'Không đọc được chiều rộng hoặc chiều cao của mặt đã chọn.'
          end
          return 'Không đọc được chiều sâu của model phía sau mặt đã chọn.' unless values[:selected_model_depth_mm]&.positive?
          if values[:mortise_depth_mm] > values[:selected_model_depth_mm] + 0.001
            return "Chiều sâu mộng âm vượt quá chiều sâu model (mộng #{format_mm(values[:mortise_depth_mm])}, model #{format_mm(values[:selected_model_depth_mm])})."
          end

          nil
        end

        def validate_tenon(values)
          return 'Vui lòng chọn đúng một mặt phẳng của model trước khi tạo mộng dương.' unless values[:selected_face]
          return 'Không đọc được hệ trục và kích thước của mặt đã chọn.' unless values[:selected_side_face]
          return 'Không đọc được chiều rộng hoặc chiều cao từ mặt đã chọn.' unless values[:tenon_face_width_mm]&.positive? && values[:tenon_height_mm]&.positive?
          return 'Vui lòng nhập số hợp lệ cho rộng, dày và bố trí mộng dương.' if tenon_values_invalid?(values)
          return 'Rộng mộng dương phải lớn hơn 0.' unless values[:tenon_width_mm].positive?
          return 'Độ vươn mộng dương từ mặt đã chọn phải lớn hơn 0.' unless values[:tenon_thickness_mm].positive?
          if values[:tenon_relief_enabled] && !values[:tenon_cutter_radius_mm].positive?
            return 'Bán kính dao phải lớn hơn 0.'
          end
          return 'Số lượng mộng dương phải lớn hơn 0.' unless values[:tenon_count].positive?
          return 'Độ hở phải nhỏ hơn rộng và chiều cao mộng dương.' unless values[:clearance_mm] < values[:tenon_width_mm] && values[:clearance_mm] < values[:tenon_height_mm]
          return 'Khoảng cách từ mép cạnh không được nhỏ hơn 0.' if values[:tenon_edge_offset_mm].negative?

          if values[:tenon_count] > 1
            finished_width = values[:tenon_width_mm] - values[:clearance_mm]
            required_width = (values[:tenon_edge_offset_mm] * 2.0) + (finished_width * values[:tenon_count])
            if required_width > values[:tenon_face_width_mm] + 0.001
              return "Bố trí mộng dương vượt quá chiều rộng mặt đã chọn (cần tối thiểu #{format_mm(required_width)}, có #{format_mm(values[:tenon_face_width_mm])})."
            end
          end

          nil
        end

        def tenon_values_invalid?(values)
          %i[
            tenon_width_mm
            tenon_thickness_mm
            tenon_cutter_radius_mm
            tenon_count
            tenon_edge_offset_mm
          ].any? { |key| values[key].nil? }
        end

        def to_settings_hash(values)
          {
            mortise_width: mm_to_length(values[:mortise_width_mm]),
            mortise_height: mm_to_length(values[:mortise_height_mm]),
            mortise_depth: mm_to_length(values[:mortise_depth_mm]),
            mortise_face_width: values[:selected_face_width_mm] ? mm_to_length(values[:selected_face_width_mm]) : nil,
            mortise_face_height: values[:selected_face_height_mm] ? mm_to_length(values[:selected_face_height_mm]) : nil,
            mortise_model_depth: values[:selected_model_depth_mm] ? mm_to_length(values[:selected_model_depth_mm]) : nil,
            cutter_radius: mm_to_length(values[:cutter_radius_mm]),
            clearance: mm_to_length(values[:clearance_mm]),
            tenon_width: mm_to_length(values[:tenon_width_mm] || values[:mortise_width_mm]),
            tenon_face_width: values[:tenon_face_width_mm] ? mm_to_length(values[:tenon_face_width_mm]) : nil,
            tenon_height: mm_to_length(values[:tenon_height_mm] || values[:mortise_height_mm]),
            tenon_face_height: mm_to_length(values[:tenon_height_mm] || values[:mortise_height_mm]),
            tenon_thickness: mm_to_length(values[:tenon_thickness_mm] || values[:mortise_depth_mm]),
            tenon_projection: mm_to_length(values[:tenon_thickness_mm] || values[:mortise_depth_mm]),
            tenon_length: mm_to_length(values[:tenon_thickness_mm] || values[:mortise_depth_mm]),
            tenon_cutter_radius: mm_to_length(values[:tenon_cutter_radius_mm] || NUMERIC_DEFAULTS_MM[:tenon_cutter_radius_mm]),
            tenon_count: values[:tenon_count] || NUMERIC_DEFAULTS_MM[:tenon_count],
            tenon_edge_offset: mm_to_length(values[:tenon_edge_offset_mm] || NUMERIC_DEFAULTS_MM[:tenon_edge_offset_mm]),
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
            "Bán kính dao: #{format_length(settings[:cutter_radius])} mm",
            "Độ hở lắp ráp: #{format_length(settings[:clearance])} mm",
            "Cấu hình mẫu: #{settings[:preset]}",
            "Khoét góc mộng âm: #{settings[:dogbone_style]}",
            "Tạo mộng âm: #{format_boolean(settings[:create_mortise])}",
            "Cắt mộng âm vào khối đã chọn: #{format_boolean(settings[:cut_mortise_into_selected_solid])}",
            "Tạo mộng dương: #{format_boolean(settings[:create_tenon])}",
            "Rộng mộng dương: #{format_length(settings[:tenon_width])} mm",
            "Độ vươn mộng dương từ mặt đã chọn: #{format_length(settings[:tenon_projection])} mm",
            "Chiều cao mặt đã chọn: #{format_length(settings[:tenon_face_height])} mm",
            "Bán kính dao: #{format_length(settings[:tenon_cutter_radius])} mm",
            "Số lượng mộng dương: #{settings[:tenon_count]}",
            "Khoảng cách từ mép cạnh: #{format_length(settings[:tenon_edge_offset])} mm",
            "Thêm nhãn: #{format_boolean(settings[:add_labels])}"
          ]
          lines.join("\n")
        end

        def numeric_value(value)
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def integer_value(value)
          numeric = numeric_value(value)
          return nil unless numeric && numeric == numeric.to_i

          numeric.to_i
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
