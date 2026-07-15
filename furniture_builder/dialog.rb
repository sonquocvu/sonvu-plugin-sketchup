# frozen_string_literal: true

require 'json'

# Dialog controller for Vietnamese furniture creation and editing.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Dialog
        YES = 'Có'
        NO = 'Không'
        INPUTBOX_PROMPTS = [
          'Mẫu tủ',
          'Tên tủ',
          'Rộng tủ (mm)',
          'Cao tủ (mm)',
          'Sâu tủ (mm)',
          'Dày ván chính (mm)',
          'Tạo tấm hậu?',
          'Dày tấm hậu (mm)',
          'Số hàng đợt mỗi khoang',
          'Số vách đứng',
          'Cao chân tủ (mm)',
          'Lùi chân tủ từ mặt trước (mm)',
          'Tên vật liệu',
          'Hướng vân',
          'Đánh dấu dán cạnh trước?',
          'Bố trí mặt trước',
          'Kiểu phủ mặt cánh',
          'Dày mặt cánh (mm)',
          'Khe hở mặt cánh (mm)',
          'Cao mặt ngăn kéo trên (mm)',
          'Vật liệu mặt cánh',
          'Hướng vân mặt cánh',
          'Dán cạnh bốn phía mặt cánh?',
          'Tạo hộp ngăn kéo?',
          'Độ hở ray mỗi bên (mm)',
          'Sâu hộp ngăn kéo (mm, 0 = tự động)',
          'Cao hộp ngăn kéo (mm)',
          'Dày thành hộp (mm)',
          'Dày đáy ngăn kéo (mm)',
          'Lùi hộp từ mặt trước (mm)',
          'Hở phía sau hộp (mm)',
          'Vật liệu hộp ngăn kéo',
          'Tạo tay nắm?',
          'Chiều dài tay nắm (mm)',
          'Chiều rộng tay nắm (mm)',
          'Độ nhô tay nắm (mm)',
          'Cách mép đóng cánh (mm)',
          'Tạo bản lề chén?',
          'Số bản lề mỗi cánh (0 = tự động)',
          'Đường kính chén bản lề (mm)',
          'Chiều sâu chén bản lề (mm)',
          'Tâm chén cách cạnh bản lề (mm)',
          'Bản lề cách hai đầu cánh (mm)',
          'Tạo ray ngăn kéo?',
          'Chiều dài ray (mm, 0 = tự động)',
          'Chiều cao ray (mm)',
          'Độ dày ray mỗi bên (mm)',
          'Vật liệu phụ kiện'
        ].freeze

        module_function

        def show(initial_values: nil, mode: :create, &block)
          initial = Specification.normalize(initial_values || Specification.defaults)
          return show_inputbox(initial, mode, &block) unless html_dialog_supported?

          dialog = create_html_dialog(mode)
          @dialog = dialog
          dialog.add_action_callback('submitFurniture') do |_context, payload|
            handle_submission(dialog, payload, &block)
          end
          dialog.add_action_callback('cancelFurniture') do
            @dialog = nil
            dialog.close
          end
          dialog.set_html(DialogHTML.html(initial, mode))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        end

        def show_inputbox(initial, mode)
          preset_labels = Presets.options.map(&:last)
          defaults = [
            Presets.fetch(initial[:preset_key])[:label],
            initial[:cabinet_name],
            initial[:width_mm],
            initial[:height_mm],
            initial[:depth_mm],
            initial[:panel_thickness_mm],
            initial[:include_back] ? YES : NO,
            initial[:back_thickness_mm],
            initial[:shelf_count],
            initial[:divider_count],
            initial[:plinth_height_mm],
            initial[:plinth_setback_mm],
            initial[:material_name],
            initial[:grain_mode],
            initial[:edge_band_front] ? YES : NO,
            Presets::FRONT_LAYOUTS.fetch(initial[:front_layout]),
            initial[:front_cover_mode],
            initial[:front_thickness_mm],
            initial[:front_gap_mm],
            initial[:top_drawer_height_mm],
            initial[:front_material_name],
            initial[:front_grain_mode],
            initial[:front_edge_band_all] ? YES : NO,
            initial[:include_drawer_boxes] ? YES : NO,
            initial[:drawer_side_clearance_mm],
            initial[:drawer_box_depth_mm],
            initial[:drawer_box_height_mm],
            initial[:drawer_panel_thickness_mm],
            initial[:drawer_bottom_thickness_mm],
            initial[:drawer_front_setback_mm],
            initial[:drawer_rear_clearance_mm],
            initial[:drawer_material_name],
            initial[:include_handles] ? YES : NO,
            initial[:handle_length_mm],
            initial[:handle_width_mm],
            initial[:handle_projection_mm],
            initial[:handle_edge_offset_mm],
            initial[:include_hinges] ? YES : NO,
            initial[:hinge_count],
            initial[:hinge_cup_diameter_mm],
            initial[:hinge_cup_depth_mm],
            initial[:hinge_edge_offset_mm],
            initial[:hinge_end_offset_mm],
            initial[:include_drawer_slides] ? YES : NO,
            initial[:drawer_slide_length_mm],
            initial[:drawer_slide_height_mm],
            initial[:drawer_slide_thickness_mm],
            initial[:hardware_material_name]
          ]
          lists = [
            preset_labels.join('|'), '', '', '', '', '', "#{YES}|#{NO}", '', '', '', '', '', '',
            Presets::GRAIN_OPTIONS.join('|'), "#{YES}|#{NO}",
            Presets::FRONT_LAYOUTS.values.join('|'), Presets::COVER_OPTIONS.join('|'), '', '', '', '',
            Presets::GRAIN_OPTIONS.join('|'), "#{YES}|#{NO}", "#{YES}|#{NO}",
            '', '', '', '', '', '', '', '', "#{YES}|#{NO}", '', '', '', '',
            "#{YES}|#{NO}", '', '', '', '', '', "#{YES}|#{NO}", '', '', '', ''
          ]
          unless INPUTBOX_PROMPTS.length == defaults.length && defaults.length == lists.length
            raise 'Cấu hình hộp thoại dự phòng không đồng bộ.'
          end
          input = UI.inputbox(INPUTBOX_PROMPTS, defaults, lists, dialog_title(mode))
          return nil unless input

          values = {
            preset_key: preset_key_for_label(input[0]),
            cabinet_name: input[1],
            width_mm: input[2],
            height_mm: input[3],
            depth_mm: input[4],
            panel_thickness_mm: input[5],
            include_back: input[6],
            back_thickness_mm: input[7],
            shelf_count: input[8],
            divider_count: input[9],
            plinth_height_mm: input[10],
            plinth_setback_mm: input[11],
            material_name: input[12],
            grain_mode: input[13],
            edge_band_front: input[14],
            front_layout: front_key_for_label(input[15]),
            front_cover_mode: input[16],
            front_thickness_mm: input[17],
            front_gap_mm: input[18],
            top_drawer_height_mm: input[19],
            front_material_name: input[20],
            front_grain_mode: input[21],
            front_edge_band_all: input[22],
            include_drawer_boxes: input[23],
            drawer_side_clearance_mm: input[24],
            drawer_box_depth_mm: input[25],
            drawer_box_height_mm: input[26],
            drawer_panel_thickness_mm: input[27],
            drawer_bottom_thickness_mm: input[28],
            drawer_front_setback_mm: input[29],
            drawer_rear_clearance_mm: input[30],
            drawer_material_name: input[31],
            include_handles: input[32],
            handle_length_mm: input[33],
            handle_width_mm: input[34],
            handle_projection_mm: input[35],
            handle_edge_offset_mm: input[36],
            include_hinges: input[37],
            hinge_count: input[38],
            hinge_cup_diameter_mm: input[39],
            hinge_cup_depth_mm: input[40],
            hinge_edge_offset_mm: input[41],
            hinge_end_offset_mm: input[42],
            include_drawer_slides: input[43],
            drawer_slide_length_mm: input[44],
            drawer_slide_height_mm: input[45],
            drawer_slide_thickness_mm: input[46],
            hardware_material_name: input[47]
          }
          finish_values(values, &block)
        end

        def handle_submission(dialog, payload)
          values = JSON.parse(payload.to_s)
          settings = Specification.normalize(values)
          error = Specification.validate(settings)
          if error
            dialog.execute_script("showError(#{JSON.generate(error)});")
            return nil
          end

          @dialog = nil
          dialog.close
          yield settings if block_given?
          settings
        rescue JSON::ParserError, TypeError
          dialog.execute_script("showError(#{JSON.generate('Không đọc được dữ liệu từ hộp thoại. Vui lòng thử lại.')} );")
          nil
        end

        def finish_values(values)
          settings = Specification.normalize(values)
          error = Specification.validate(settings)
          if error
            CNCPlugins::UIHelpers.message(error)
            return nil
          end

          yield settings if block_given?
          settings
        end

        def html_dialog_supported?
          defined?(::UI::HtmlDialog)
        end

        def create_html_dialog(mode)
          options = {
            dialog_title: dialog_title(mode),
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_builder",
            scrollable: true,
            resizable: true,
            width: 620,
            height: 780
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          ::UI::HtmlDialog.new(options)
        end

        def dialog_title(mode)
          mode == :edit ? 'Chỉnh sửa tủ nội thất' : 'Tạo tủ nội thất'
        end

        def preset_key_for_label(label)
          match = Presets.options.find { |_key, item_label| item_label == label.to_s }
          match ? match.first : Presets::DEFAULT_KEY
        end

        def front_key_for_label(label)
          match = Presets::FRONT_LAYOUTS.find { |_key, item_label| item_label == label.to_s }
          match ? match.first : Presets::FRONT_NONE
        end
      end
    end
  end
end
