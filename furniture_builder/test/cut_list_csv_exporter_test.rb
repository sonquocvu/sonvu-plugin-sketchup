# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'csv'

require_relative '../cut_list_csv_exporter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CutListCSVExporterTest < Minitest::Test
        def test_output_paths_create_separate_vietnamese_tables
          paths = CutListCSVExporter.output_paths('C:/du_an/bao_cao.CSV')

          assert_equal 'C:/du_an/bao_cao_chi_tiet_van.csv', paths[:boards]
          assert_equal 'C:/du_an/bao_cao_phu_kien.csv', paths[:hardware]
          assert_raises(ArgumentError) { CutListCSVExporter.output_paths('  ') }
        end

        def test_board_csv_has_utf8_bom_vietnamese_headers_and_production_data
          csv = CutListCSVExporter.board_csv(sample_report)
          parsed = parse(csv)

          assert csv.start_with?(CutListCSVExporter::UTF8_BOM)
          assert_equal CutListCSVExporter::BOARD_HEADERS, parsed.first
          assert_equal 'Mặt cánh', parsed[1][1]
          assert_equal 'Cánh trái, mẫu "A"', parsed[1][2]
          assert_equal '2', parsed[1][3]
          assert_equal '716', parsed[1][4]
          assert_equal '397.5', parsed[1][5]
          assert_equal 'MDF chống ẩm, màu trắng', parsed[1][7]
          assert_equal 'Dọc', parsed[1][8]
          assert_equal 'Theo chiều dài', parsed[1][9]
          assert_equal %w[Có Không Có Không], parsed[1][10, 4]
          assert_equal 'Tủ bếp A / Tủ bếp B', parsed[1][14]
        end

        def test_hardware_csv_includes_owner_and_drawer_linkage
          parsed = parse(CutListCSVExporter.hardware_csv(sample_report))

          assert_equal CutListCSVExporter::HARDWARE_HEADERS, parsed.first
          assert_equal 'Ray ngăn kéo', parsed[1][1]
          assert_equal '4', parsed[1][2]
          assert_equal '531', parsed[1][3]
          assert_equal '1 / 2', parsed[1][9]
          assert_equal 'mat_ngan_keo_1 / mat_ngan_keo_2', parsed[1][10]
        end

        def test_write_emits_both_files_without_leaving_temporary_files
          Dir.mktmpdir('sonvu-cut-list') do |directory|
            base = File.join(directory, 'cong_trinh.csv')
            paths = CutListCSVExporter.write(sample_report, base)

            assert File.file?(paths[:boards])
            assert File.file?(paths[:hardware])
            assert_equal [0xEF, 0xBB, 0xBF], File.binread(paths[:boards]).bytes.first(3)
            assert_equal [0xEF, 0xBB, 0xBF], File.binread(paths[:hardware]).bytes.first(3)
            assert_empty Dir.glob(File.join(directory, '*.tmp'))
          end
        end

        def test_empty_sections_still_export_headers
          report = { board_rows: [], hardware_rows: [] }

          assert_equal [CutListCSVExporter::BOARD_HEADERS], parse(CutListCSVExporter.board_csv(report))
          assert_equal [CutListCSVExporter::HARDWARE_HEADERS], parse(CutListCSVExporter.hardware_csv(report))
        end

        def test_model_text_that_looks_like_excel_formula_is_neutralized
          report = sample_report
          report[:board_rows][0][:name] = '=HYPERLINK("https://example.test")'
          report[:board_rows][0][:material_name] = ' +CMD'

          row = parse(CutListCSVExporter.board_csv(report))[1]

          assert_equal '\'=HYPERLINK("https://example.test")', row[2]
          assert_equal "' +CMD", row[7]
        end

        private

        def parse(value)
          CSV.parse(value.delete_prefix(CutListCSVExporter::UTF8_BOM))
        end

        def sample_report
          {
            board_rows: [
              {
                category: 'Mặt cánh',
                name: 'Cánh trái, mẫu "A"',
                quantity: 2,
                length_mm: 716,
                width_mm: 397.5,
                thickness_mm: 18,
                material_name: 'MDF chống ẩm, màu trắng',
                grain_direction: 'dọc',
                grain_axis: 'length',
                edge_front: true,
                edge_back: false,
                edge_left: true,
                edge_right: false,
                cabinet_names: ['Tủ bếp A', 'Tủ bếp B'],
                cabinet_ids: %w[cabinet-a cabinet-b]
              }
            ],
            hardware_rows: [
              {
                name: 'Ray ngăn kéo',
                quantity: 4,
                length_mm: 531,
                width_mm: 45,
                thickness_mm: 12.5,
                material_name: 'Phụ kiện kim khí',
                cabinet_names: ['Tủ bếp A'],
                cabinet_ids: ['cabinet-a'],
                drawer_indices: [1, 2],
                owner_part_keys: %w[mat_ngan_keo_1 mat_ngan_keo_2]
              }
            ]
          }
        end
      end
    end
  end
end
