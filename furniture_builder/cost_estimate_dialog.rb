# frozen_string_literal: true

require 'json'

# Phase 3C dialog controller. Catalog values are stored in SketchUp preferences,
# never in the model, and only after the user explicitly calculates a quote.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CostEstimateDialog
        PREFERENCES_SECTION = 'SonVu CNC Plugins - Furniture Costing'
        CATALOG_KEY = 'price_catalog_json'

        module_function

        def show(report)
          catalog = load_catalog(report)
          estimate = nil
          options = {
            dialog_title: 'Dự toán chi phí nội thất',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_cost_estimate",
            scrollable: true,
            resizable: true,
            width: 1060,
            height: 760
          }
          if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
            options[:style] = ::UI::HtmlDialog::STYLE_DIALOG
          end
          dialog = ::UI::HtmlDialog.new(options)
          @dialog = dialog
          dialog.add_action_callback('calculateCost') do |_context, payload|
            begin
              submitted = JSON.parse(payload.to_s)
              catalog = CostEstimator.normalize_catalog(report, merge_catalog(catalog, submitted))
              estimate = CostEstimator.calculate(report, catalog)
              save_catalog(catalog)
              dialog.set_html(CostEstimateDialogHTML.html(report, catalog, estimate))
            rescue StandardError => e
              dialog.execute_script("showCostError(#{JSON.generate(e.message)});")
            end
          end
          dialog.add_action_callback('exportCostEstimate') do
            export_estimate(estimate) if estimate
          end
          dialog.add_action_callback('closeCostEstimate') do
            @dialog = nil
            dialog.close
          end
          dialog.set_html(CostEstimateDialogHTML.html(report, catalog, estimate))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được dự toán chi phí:\n#{e.message}")
          nil
        end

        def load_catalog(report)
          payload = Sketchup.read_default(PREFERENCES_SECTION, CATALOG_KEY, '').to_s
          values = payload.empty? ? {} : JSON.parse(payload)
          CostEstimator.normalize_catalog(report, values)
        rescue JSON::ParserError, TypeError
          CostEstimator.default_catalog(report)
        end

        def save_catalog(catalog)
          Sketchup.write_default(PREFERENCES_SECTION, CATALOG_KEY, JSON.generate(catalog))
        end

        def merge_catalog(current, submitted)
          {
            waste_percent: submitted['waste_percent'],
            edge_band_price_per_m: submitted['edge_band_price_per_m'],
            material_prices: current[:material_prices].merge(
              stringify_map(submitted['material_prices'])
            ),
            hardware_prices: current[:hardware_prices].merge(
              stringify_map(submitted['hardware_prices'])
            )
          }
        end

        def stringify_map(value)
          return {} unless value.respond_to?(:each)

          value.each_with_object({}) { |(key, item), result| result[key.to_s] = item }
        end

        def export_estimate(estimate)
          selected = ::UI.savepanel('Xuất báo giá CSV', nil, 'bao_gia_noi_that.csv')
          return nil if selected.nil? || selected.to_s.strip.empty?

          path = CostEstimateCSVExporter.output_path(selected)
          if File.exist?(path)
            result = ::UI.messagebox(
              "File #{File.basename(path)} đã tồn tại. Bạn có muốn ghi đè không?",
              ::MB_YESNO
            )
            return nil unless result == ::IDYES
          end
          written = CostEstimateCSVExporter.write(estimate, path)
          CNCPlugins::UIHelpers.message(
            "Đã xuất báo giá:\n#{File.basename(written)}\n\n" \
            "Thư mục: #{File.dirname(File.expand_path(written))}"
          )
          written
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không xuất được báo giá CSV:\n#{e.message}")
          nil
        end
      end
    end
  end
end
