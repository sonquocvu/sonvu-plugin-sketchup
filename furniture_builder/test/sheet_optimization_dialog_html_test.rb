# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../sheet_optimizer'
require_relative '../sheet_optimization_dialog_html'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class SheetOptimizationDialogHTMLTest < Minitest::Test
        def test_vietnamese_form_exposes_saved_dimensions_and_callbacks
          html = SheetOptimizationDialogHTML.html(report, settings)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'Tối ưu cắt ván'
          assert_includes html, 'Chiều dài tấm'
          assert_includes html, 'Bề rộng đường cưa'
          assert_includes html, 'Cho phép xoay chi tiết 90°'
          assert_includes html, 'Giữ đúng chiều vân đã thiết kế'
          assert_includes html, 'value="2440"'
          assert_includes html, 'calculateSheetOptimization'
          assert_includes html, 'exportSheetOptimization'
          assert_includes html, 'closeSheetOptimization'
          assert_includes html, 'SonVu Furniture Builder — Phase 4C'
          assert_match(/button type="button" disabled onclick="window\.sketchup\.exportSheetOptimization/, html)
          refute_includes html, 'Số tấm</span>'
          refute_includes html, 'class="sheet-map"'
        end

        def test_result_shows_sheet_coordinates_summary_and_escaped_names
          result = SheetOptimizer.optimize(report, settings)
          html = SheetOptimizationDialogHTML.html(report, settings, result)

          assert_includes html, 'Số tấm</span>'
          assert_includes html, 'Hiệu suất'
          assert_includes html, 'Tấm 1'
          assert_includes html, 'X (mm)'
          assert_includes html, 'Xoay 90°'
          assert_includes html, 'SonVu Furniture Builder — Phase 4C'
          assert_includes html, 'class="sheet-map"'
          assert_includes html, 'class="stock-sheet"'
          assert_includes html, 'class="usable-area"'
          assert_includes html, 'class="part-shape"'
          assert_includes html, 'class="grain-arrow"'
          assert_includes html, 'Chiều vân'
          assert_includes html, 'Vừa khung'
          assert_includes html, 'changeSheetZoom'
          assert_includes html, 'showSheet'
          assert_includes html, 'Xem bảng tọa độ'
          assert_includes html, 'Xuất phương án'
          refute_match(/button type="button" disabled onclick="window\.sketchup\.exportSheetOptimization/, html)
          assert_includes html, 'MDF &quot;A&quot; &amp; B'
          assert_includes html, 'Hông &lt;trái&gt;'
          refute_includes html, 'Hông <trái>'
        end

        def test_multiple_sheets_have_navigation_and_only_first_is_initially_visible
          multiple = report
          multiple[:board_rows].first.merge!(quantity: 2, length_mm: 900, width_mm: 450)
          options = settings.merge(
            sheet_length_mm: 1000, sheet_width_mm: 500,
            edge_trim_mm: 0, kerf_mm: 0, part_spacing_mm: 0
          )
          result = SheetOptimizer.optimize(multiple, options)
          html = SheetOptimizationDialogHTML.html(multiple, options, result)

          assert_equal 2, result[:sheet_count]
          assert_equal 2, html.scan('class="sheet-tab').length
          assert_includes html, 'data-sheet-target="sheet-view-1-1"'
          assert_includes html, 'data-sheet-target="sheet-view-1-2"'
          assert_match(/id="sheet-view-1-2" class="sheet sheet-view" hidden/, html)
          assert_equal 2, html.scan('class="sheet-map"').length
        end

        def test_unplaced_part_reason_is_visible
          oversized = report
          oversized[:board_rows].first[:length_mm] = 3000
          result = SheetOptimizer.optimize(oversized, settings)
          html = SheetOptimizationDialogHTML.html(oversized, settings, result)

          assert_includes html, 'Chi tiết chưa xếp được (1)'
          assert_includes html, 'lớn hơn vùng sử dụng'
        end

        private

        def settings
          {
            sheet_length_mm: 2440, sheet_width_mm: 1220, edge_trim_mm: 10,
            kerf_mm: 3.2, part_spacing_mm: 3.2, allow_rotation: true, respect_grain: true
          }
        end

        def report
          {
            scope: 'Các tủ đang chọn', cabinet_count: 1,
            board_rows: [
              {
                category: 'Thùng tủ', name: 'Hông <trái>', quantity: 1,
                length_mm: 720, width_mm: 580, thickness_mm: 18,
                material_name: 'MDF "A" & B', grain_direction: 'dọc', grain_axis: 'length',
                cabinet_names: ['Tủ A']
              }
            ]
          }
        end
      end
    end
  end
end
