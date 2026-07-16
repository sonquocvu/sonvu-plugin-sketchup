# frozen_string_literal: true

require 'json'
if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/furniture_builder/sheet_layout_exporter'
else
  require_relative 'sheet_layout_exporter'
end

# Phase 4A–4C controller for optimization, visualization, and explicit export.
# Settings are stored in preferences only after a successful calculation.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module SheetOptimizationDialog
        PREFERENCES_SECTION = 'SonVu CNC Plugins - Furniture Sheet Optimization'
        SETTINGS_KEY = 'settings_json'

        module_function

        def show(report)
          settings = load_settings
          return show_fallback(report, settings) unless defined?(::UI::HtmlDialog)

          result = nil
          options = {
            dialog_title: 'Tối ưu cắt ván',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_sheet_optimization",
            scrollable: true,
            resizable: true,
            width: 1100,
            height: 780
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          dialog = ::UI::HtmlDialog.new(options)
          @dialog = dialog
          dialog.add_action_callback('calculateSheetOptimization') do |_context, payload|
            begin
              submitted = JSON.parse(payload.to_s)
              settings = SheetOptimizer.normalize_settings(submitted)
              result = SheetOptimizer.optimize(report, settings)
              save_settings(settings)
              dialog.set_html(SheetOptimizationDialogHTML.html(report, settings, result))
            rescue StandardError => e
              dialog.execute_script("showOptimizationError(#{JSON.generate(e.message)});")
            end
          end
          dialog.add_action_callback('exportSheetOptimization') do
            export(report, result) if result
          end
          dialog.add_action_callback('closeSheetOptimization') do
            @dialog = nil
            dialog.close
          end
          dialog.set_html(SheetOptimizationDialogHTML.html(report, settings, result))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được công cụ tối ưu cắt ván:\n#{e.message}")
          nil
        end

        def load_settings
          payload = Sketchup.read_default(PREFERENCES_SECTION, SETTINGS_KEY, '').to_s
          values = payload.empty? ? {} : JSON.parse(payload)
          SheetOptimizer.normalize_settings(values)
        rescue JSON::ParserError, TypeError
          SheetOptimizer::DEFAULT_SETTINGS.dup
        end

        def save_settings(settings)
          Sketchup.write_default(PREFERENCES_SECTION, SETTINGS_KEY, JSON.generate(settings))
        end

        def export(report, result)
          selected = ::UI.savepanel(
            'Xuất phương án cắt ván',
            nil,
            'cong_trinh.html'
          )
          return nil if selected.nil? || selected.to_s.strip.empty?

          paths = SheetLayoutExporter.output_paths(selected)
          return nil unless overwrite_allowed?(paths)

          written = SheetLayoutExporter.write(report, result, selected)
          CNCPlugins::UIHelpers.message(
            "Đã xuất phương án cắt ván:\n" \
            "- #{File.basename(written[:report])}\n" \
            "- #{File.basename(written[:placements])}\n\n" \
            "Thư mục: #{File.dirname(File.expand_path(written[:report]))}"
          )
          written
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không xuất được phương án cắt ván:\n#{e.message}")
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

        def show_fallback(report, settings)
          result = SheetOptimizer.optimize(report, settings)
          message =
            "TỐI ƯU CẮT VÁN\n\n" \
            "Số tấm: #{result[:sheet_count]}\n" \
            "Đã xếp: #{result[:placed_count]}/#{result[:part_count]} chi tiết\n" \
            "Hiệu suất: #{format('%.1f', result[:utilization_percent])}%\n" \
            "Chưa xếp: #{result[:unplaced_count]} chi tiết\n\n" \
            'Bạn có muốn xuất phương án HTML và CSV không?'
          choice = ::UI.messagebox(message, ::MB_YESNO)
          export(report, result) if choice == ::IDYES
          result
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không tối ưu được cắt ván:\n#{e.message}")
          nil
        end
      end
    end
  end
end
