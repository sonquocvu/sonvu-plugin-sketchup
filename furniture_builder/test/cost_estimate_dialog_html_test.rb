# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../cost_estimator'
require_relative '../cost_estimate_dialog_html'
require_relative '../cost_estimate_dialog'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CostEstimateDialogHTMLTest < Minitest::Test
        def test_form_is_vietnamese_escapes_catalog_names_and_exposes_callbacks
          html = CostEstimateDialogHTML.html(report, catalog)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'Dự toán chi phí'
          assert_includes html, 'Tỷ lệ hao hụt vật liệu'
          assert_includes html, 'Đơn giá dán cạnh'
          assert_includes html, 'Dự toán chi phí'
          assert_includes html, 'calculateCost'
          assert_includes html, 'exportCostEstimate'
          assert_includes html, 'MDF &quot;A&quot; &amp; B'
          refute_includes html, 'MDF "A" & B'
          assert_match(/Xuất báo giá CSV<\/button>/, html)
          assert_match(/button type="button" disabled onclick="window\.sketchup\.exportCostEstimate/, html)
        end

        def test_calculated_preview_shows_subtotals_and_per_cabinet_totals
          estimate = CostEstimator.calculate(report, catalog)
          html = CostEstimateDialogHTML.html(report, catalog, estimate)

          assert_includes html, 'Chi tiết dự toán ván'
          assert_includes html, 'Chi tiết phụ kiện'
          assert_includes html, 'Tổng theo tủ'
          assert_includes html, '360.000 ₫'
          assert_includes html, '180.000 ₫'
          refute_match(/button type="button" disabled onclick="window\.sketchup\.exportCostEstimate/, html)
        end

        def test_submitted_catalog_keeps_prices_for_materials_not_in_current_report
          current = catalog.merge(
            material_prices: catalog[:material_prices].merge('Vật liệu cũ' => 123_000)
          )
          submitted = {
            'waste_percent' => '5',
            'edge_band_price_per_m' => '6000',
            'material_prices' => { 'MDF "A" & B' => '210000' },
            'hardware_prices' => { 'Bản lề chén' => '35000' }
          }

          merged = CostEstimateDialog.merge_catalog(current, submitted)

          assert_equal 123_000, merged[:material_prices]['Vật liệu cũ']
          assert_equal '210000', merged[:material_prices]['MDF "A" & B']
          assert_equal '35000', merged[:hardware_prices]['Bản lề chén']
        end

        private

        def catalog
          {
            waste_percent: 10,
            edge_band_price_per_m: 5000,
            material_prices: { 'MDF "A" & B' => 200_000 },
            hardware_prices: { 'Bản lề chén' => 30_000 }
          }
        end

        def report
          {
            scope: 'Các tủ đang chọn', cabinet_count: 2,
            board_rows: [
              {
                name: 'Hông trái / Hông phải', quantity: 2,
                length_mm: 1000, width_mm: 500, thickness_mm: 18,
                material_name: 'MDF "A" & B', edge_front: true, edge_back: true,
                edge_left: false, edge_right: false, cabinet_names: %w[Tủ-A Tủ-B],
                cabinet_ids: %w[a b], cabinet_breakdown: breakdown(1)
              }
            ],
            hardware_rows: [
              {
                name: 'Bản lề chén', quantity: 4, length_mm: 35, width_mm: 35,
                thickness_mm: 12, cabinet_names: %w[Tủ-A Tủ-B], cabinet_ids: %w[a b],
                cabinet_breakdown: breakdown(2)
              }
            ]
          }
        end

        def breakdown(quantity)
          [
            { occurrence_key: 'a#1', cabinet_id: 'a', cabinet_name: 'Tủ-A', quantity: quantity },
            { occurrence_key: 'b#2', cabinet_id: 'b', cabinet_name: 'Tủ-B', quantity: quantity }
          ]
        end
      end
    end
  end
end
