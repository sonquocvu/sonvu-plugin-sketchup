# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'csv'

require_relative '../cost_estimate_csv_exporter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CostEstimateCSVExporterTest < Minitest::Test
        def test_output_path_adds_csv_extension
          assert_equal 'C:/du_an/bao_gia.csv', CostEstimateCSVExporter.output_path('C:/du_an/bao_gia')
          assert_equal 'C:/du_an/bao_gia.CSV', CostEstimateCSVExporter.output_path('C:/du_an/bao_gia.CSV')
          assert_raises(ArgumentError) { CostEstimateCSVExporter.output_path(' ') }
        end

        def test_csv_contains_line_items_cabinet_totals_and_project_summary
          document = CostEstimateCSVExporter.csv(estimate)
          rows = CSV.parse(document.delete_prefix(CutListCSVExporter::UTF8_BOM))

          assert document.start_with?(CutListCSVExporter::UTF8_BOM)
          assert_equal CostEstimateCSVExporter::LINE_HEADERS, rows.first
          assert_equal 'Chi tiết ván', rows[1][1]
          assert_equal '240000', rows[1][14]
          assert_equal 'Phụ kiện', rows[2][1]
          assert_equal '120000', rows[2][14]
          assert rows.any? { |row| row[0] == 'TỔNG THEO TỦ' }
          assert rows.any? { |row| row[0] == 'TỔNG CỘNG' && row[1] == '360000' }
        end

        def test_csv_neutralizes_formula_like_model_text
          dangerous = Marshal.load(Marshal.dump(estimate))
          dangerous[:board_rows][0][:name] = '=CMD()'

          rows = CSV.parse(
            CostEstimateCSVExporter.csv(dangerous).delete_prefix(CutListCSVExporter::UTF8_BOM)
          )

          assert_equal "'=CMD()", rows[1][2]
        end

        def test_write_uses_utf8_bom_and_leaves_no_temp_file
          Dir.mktmpdir('sonvu-cost') do |directory|
            target = File.join(directory, 'bao_gia')
            written = CostEstimateCSVExporter.write(estimate, target)

            assert_equal "#{target}.csv", written
            assert_equal [0xEF, 0xBB, 0xBF], File.binread(written).bytes.first(3)
            assert_empty Dir.glob(File.join(directory, '*.tmp'))
          end
        end

        private

        def estimate
          {
            board_rows: [
              {
                name: 'Hông tủ', quantity: 2, length_mm: 1000, width_mm: 500,
                thickness_mm: 18, billable_area_m2: 1.1,
                material_unit_price: 200_000, material_cost: 220_000,
                edge_length_m: 4, edge_unit_price: 5000, edge_cost: 20_000,
                total_cost: 240_000, cabinet_names: %w[Tủ-A Tủ-B]
              }
            ],
            hardware_rows: [
              {
                name: 'Bản lề chén', quantity: 4, length_mm: 35, width_mm: 35,
                thickness_mm: 12, unit_price: 30_000, total_cost: 120_000,
                cabinet_names: %w[Tủ-A Tủ-B]
              }
            ],
            cabinet_totals: [
              { cabinet_name: 'Tủ-A', cabinet_id: 'a', total_cost: 180_000 },
              { cabinet_name: 'Tủ-B', cabinet_id: 'b', total_cost: 180_000 }
            ],
            material_subtotal: 220_000,
            edge_subtotal: 20_000,
            hardware_subtotal: 120_000,
            project_total: 360_000
          }
        end
      end
    end
  end
end
