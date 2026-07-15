# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'
require 'tmpdir'

require_relative '../sheet_optimizer'
require_relative '../sheet_layout_exporter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class SheetLayoutExporterTest < Minitest::Test
        def test_output_paths_create_printable_report_and_placement_manifest
          paths = SheetLayoutExporter.output_paths('C:/du_an/tu_bep.HTML')

          assert_equal 'C:/du_an/tu_bep_phuong_an_cat.html', paths[:report]
          assert_equal 'C:/du_an/tu_bep_toa_do_cat.csv', paths[:placements]
          assert_raises(ArgumentError) { SheetLayoutExporter.output_paths(' ') }
        end

        def test_csv_contains_placed_and_unplaced_items_with_production_fields
          rows = parse_csv(SheetLayoutExporter.placement_csv(result))
          placed = rows.find { |row| row[1] == 'Đã xếp' }
          unplaced = rows.find { |row| row[1] == 'Chưa xếp' }

          assert_equal SheetLayoutExporter::PLACEMENT_HEADERS, rows.first
          assert_equal result[:part_count] + 1, rows.length
          assert_equal 'MDF <A> & B', placed[3]
          assert_equal '1', placed[5]
          assert_equal '1000', placed[6]
          assert_equal '800', placed[7]
          assert_equal "'=Cánh <A>", placed[12]
          assert_equal 'Có', placed[20]
          assert_equal 'Theo chiều rộng tấm', placed[23]
          assert_equal 'Tủ <bếp>', placed[24]
          assert_equal 'Chưa xếp', unplaced[1]
          assert_equal '', unplaced[5]
          assert_equal '', unplaced[16]
          assert_match(/lớn hơn vùng sử dụng/i, unplaced[25])
        end

        def test_csv_uses_utf8_bom_crlf_and_neutralizes_formula_like_text
          document = SheetLayoutExporter.placement_csv(result)

          assert document.start_with?(CutListCSVExporter::UTF8_BOM)
          assert_includes document, "\r\n"
          assert_includes document, "'=Cánh <A>"
        end

        def test_printable_html_embeds_every_sheet_and_escapes_model_text
          html = SheetLayoutExporter.report_html(report, result)

          assert_includes html, '<html lang="vi">'
          assert_includes html, 'SonVu Furniture Builder — Phase 4C'
          assert_includes html, '@page { size:A4 landscape'
          assert_includes html, 'In / Lưu PDF'
          assert_equal result[:sheet_count], html.scan('class="sheet-map"').length
          assert_equal result[:placed_count], html.scan('class="part-shape"').length
          assert_includes html, 'Phạm vi &lt;đang chọn&gt; &amp; kiểm tra'
          assert_includes html, 'MDF &lt;A&gt; &amp; B'
          assert_includes html, '=Cánh &lt;A&gt;'
          assert_includes html, 'Chi tiết chưa xếp được (1)'
          refute_includes html, '<script src='
          refute_includes html, '<link rel='
        end

        def test_write_emits_both_files_without_stale_temporary_files
          Dir.mktmpdir('sonvu-sheet-layout') do |directory|
            base = File.join(directory, 'phuong_an.html')
            paths = SheetLayoutExporter.write(report, result, base)

            assert File.file?(paths[:report])
            assert File.file?(paths[:placements])
            assert_includes File.binread(paths[:report]).force_encoding(Encoding::UTF_8), 'Phương án cắt ván'
            assert_equal [0xEF, 0xBB, 0xBF], File.binread(paths[:placements]).bytes.first(3)
            assert_empty Dir.glob(File.join(directory, '*.tmp'))
          end
        end

        private

        def parse_csv(document)
          CSV.parse(document.delete_prefix(CutListCSVExporter::UTF8_BOM))
        end

        def result
          @result ||= SheetOptimizer.optimize(
            report,
            sheet_length_mm: 1000, sheet_width_mm: 800, edge_trim_mm: 0,
            kerf_mm: 3.2, part_spacing_mm: 5,
            allow_rotation: true, respect_grain: false
          )
        end

        def report
          @report ||= {
            scope: 'Phạm vi <đang chọn> & kiểm tra', cabinet_count: 1,
            board_rows: [
              {
                category: 'Mặt cánh', name: '=Cánh <A>', quantity: 1,
                length_mm: 700, width_mm: 900, thickness_mm: 18,
                material_name: 'MDF <A> & B', grain_direction: 'dọc', grain_axis: 'length',
                cabinet_names: ['Tủ <bếp>']
              },
              {
                category: 'Thùng tủ', name: 'Chi tiết quá khổ', quantity: 1,
                length_mm: 1200, width_mm: 900, thickness_mm: 18,
                material_name: 'MDF <A> & B', grain_direction: '', grain_axis: 'length',
                cabinet_names: ['Tủ <bếp>']
              }
            ]
          }
        end
      end
    end
  end
end
