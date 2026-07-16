# frozen_string_literal: true

# Read-only SketchUp controller for the Step 5 machining rules, preview, and
# explicit controller-neutral export.

require 'json'
if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/machining_exporter'
else
  require_relative 'machining_exporter'
end

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module MachiningPreviewDialog
        PREFERENCES_SECTION = 'SonVu CNC Plugins - Furniture Machining'
        RULES_KEY = 'rules_json'

        module_function

        def show
          rules = load_rules
          project = project_for_model(Sketchup.active_model, rules: rules)
          if project[:cabinet_count].zero?
            CNCPlugins::UIHelpers.message(
              'Không tìm thấy tủ nội thất SonVu có dữ liệu hợp lệ trong vùng chọn hoặc model.'
            )
            return nil
          end
          return show_fallback(project) unless defined?(::UI::HtmlDialog)

          options = {
            dialog_title: 'Xem trước gia công CNC',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_machining_preview",
            scrollable: true,
            resizable: true,
            width: 1040,
            height: 780
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          dialog = ::UI::HtmlDialog.new(options)
          @dialog = dialog
          dialog.add_action_callback('calculateMachiningPreview') do |_context, payload|
            begin
              rules = MachiningRules.normalize(JSON.parse(payload.to_s))
              project = project_for_model(Sketchup.active_model, rules: rules)
              save_rules(rules)
              dialog.set_html(MachiningPreviewHTML.html(project))
            rescue StandardError => e
              dialog.execute_script("showMachiningError(#{JSON.generate(e.message)});")
            end
          end
          dialog.add_action_callback('refreshMachiningPreview') do
            refreshed = refresh(dialog, rules)
            project = refreshed if refreshed
          end
          dialog.add_action_callback('exportMachiningPackage') { export(project) }
          dialog.add_action_callback('closeMachiningPreview') do
            @dialog = nil
            dialog.close
          end
          dialog.set_html(MachiningPreviewHTML.html(project))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được xem trước gia công CNC:\n#{e.message}")
          nil
        end

        def refresh(dialog, rules = nil)
          active_rules = rules || load_rules
          project = project_for_model(Sketchup.active_model, rules: active_rules)
          dialog.set_html(MachiningPreviewHTML.html(project))
          project
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không làm mới được dữ liệu gia công:\n#{e.message}")
          nil
        end

        def export(project)
          MachiningExporter.validate_project!(project)
          selected = ::UI.savepanel('Xuất gói gia công CNC', nil, 'cong_trinh.dxf')
          return nil if selected.nil? || selected.to_s.strip.empty?

          directory = MachiningExporter.output_directory(selected)
          overwrite = false
          if File.exist?(directory)
            unless Dir.exist?(directory) && MachiningExporter.owned_directory?(directory)
              raise ArgumentError, 'Thư mục đích đã tồn tại và không do SonVu CNC Plugins tạo. Hãy chọn tên gói khác.'
            end
            choice = ::UI.messagebox(
              "Gói #{File.basename(directory)} đã tồn tại. Bạn có muốn thay thế toàn bộ gói này không?",
              ::MB_YESNO
            )
            return nil unless choice == ::IDYES

            overwrite = true
          end

          result = MachiningExporter.write(project, selected, overwrite: overwrite)
          CNCPlugins::UIHelpers.message(
            "Đã xuất gói gia công CNC:\n" \
            "- #{result[:dxf_count]} file DXF theo mặt chi tiết\n" \
            "- #{File.basename(result[:manifest_path])}\n\n" \
            "Thư mục: #{result[:directory]}\n\n" \
            'Gói này không chứa G-code; hãy kiểm tra quy trình gá đặt và thiết lập trên phần mềm máy.'
          )
          result
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không xuất được gói gia công CNC:\n#{e.message}")
          nil
        end

        def project_for_model(model, rules: nil)
          selected = CutList.find_cabinets(CutList.enumerable_entities(model.selection))
          cabinets = selected.empty? ? CutList.find_cabinets(CutList.enumerable_entities(model.entities)) : selected
          scope = selected.empty? ? 'Toàn bộ model' : 'Các tủ đang chọn'
          inputs = cabinets.map do |cabinet|
            {
              settings: Geometry.settings_from_group(cabinet),
              cabinet_id: cabinet.get_attribute(
                CNCPlugins::ATTRIBUTE_DICTIONARY,
                Geometry::CABINET_ID_ATTRIBUTE,
                ''
              ),
              cabinet_name: cabinet.get_attribute(
                CNCPlugins::ATTRIBUTE_DICTIONARY,
                'furniture_name_vi',
                cabinet.respond_to?(:name) ? cabinet.name.to_s : ''
              )
            }
          end
          MachiningPlanner.project(inputs, scope: scope, rules: rules)
        end

        def load_rules
          payload = Sketchup.read_default(PREFERENCES_SECTION, RULES_KEY, '').to_s
          values = payload.empty? ? {} : JSON.parse(payload)
          MachiningRules.normalize(values)
        rescue JSON::ParserError, TypeError, ArgumentError
          MachiningRules.defaults
        end

        def save_rules(rules)
          Sketchup.write_default(PREFERENCES_SECTION, RULES_KEY, JSON.generate(rules))
        end

        def show_fallback(project)
          CNCPlugins::UIHelpers.message(
            "XEM TRƯỚC GIA CÔNG CNC — BƯỚC 5\n\n" \
            "Tủ: #{project[:cabinet_count]}\n" \
            "Chi tiết ván: #{project[:panel_count]}\n" \
            "Nguyên công sẵn sàng: #{project[:ready_operation_count]}\n" \
            "Tham chiếu cần mẫu khoan: #{project[:reference_count]}"
          )
          project
        end
      end
    end
  end
end
