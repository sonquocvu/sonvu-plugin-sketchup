# frozen_string_literal: true

# Phase 3A report dialog with user-initiated Phase 3B CSV export.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CutListDialog
        module_function

        def show(report)
          return show_fallback(report) unless defined?(::UI::HtmlDialog)

          options = {
            dialog_title: 'Danh sách chi tiết nội thất',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_cut_list",
            scrollable: true,
            resizable: true,
            width: 1060,
            height: 720
          }
          if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
            options[:style] = ::UI::HtmlDialog::STYLE_DIALOG
          end
          dialog = ::UI::HtmlDialog.new(options)
          @dialog = dialog
          dialog.add_action_callback('closeCutList') do
            @dialog = nil
            dialog.close
          end
          dialog.add_action_callback('exportCutList') do
            export(report)
          end
          dialog.add_action_callback('openCostEstimate') do
            CostEstimateDialog.show(report)
          end
          dialog.add_action_callback('openSheetOptimization') do
            SheetOptimizationDialog.show(report)
          end
          dialog.set_html(CutListDialogHTML.html(report))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        end

        def show_fallback(report)
          message = [
            'DANH SÁCH CHI TIẾT NỘI THẤT',
            "Phạm vi: #{report[:scope]}",
            "Số tủ: #{report[:cabinet_count]}",
            "Chi tiết ván: #{report[:board_count]}",
            "Phụ kiện: #{report[:hardware_count]}",
            '',
            'SketchUp hiện tại không hỗ trợ bảng HTML.',
            'Bạn có muốn xuất hai file CSV ngay bây giờ?'
          ].join("\n")
          result = ::UI.messagebox(message, ::MB_YESNO)
          export(report) if result == ::IDYES
          nil
        end

        def export(report)
          base_path = ::UI.savepanel(
            'Xuất danh sách chi tiết CSV',
            nil,
            'danh_sach_chi_tiet.csv'
          )
          return nil if base_path.nil? || base_path.to_s.strip.empty?

          paths = CutListCSVExporter.output_paths(base_path)
          return nil unless overwrite_allowed?(paths)

          written = CutListCSVExporter.write(report, base_path)
          CNCPlugins::UIHelpers.message(
            "Đã xuất danh sách chi tiết:\n" \
            "- #{File.basename(written[:boards])}\n" \
            "- #{File.basename(written[:hardware])}\n\n" \
            "Thư mục: #{File.dirname(File.expand_path(written[:boards]))}"
          )
          written
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không xuất được danh sách CSV:\n#{e.message}")
          nil
        end

        def overwrite_allowed?(paths)
          existing = paths.values.select { |path| File.exist?(path) }
          return true if existing.empty?

          names = existing.map { |path| "- #{File.basename(path)}" }.join("\n")
          result = ::UI.messagebox(
            "Các file sau đã tồn tại:\n#{names}\n\nBạn có muốn ghi đè không?",
            ::MB_YESNO
          )
          result == ::IDYES
        end
      end
    end
  end
end
