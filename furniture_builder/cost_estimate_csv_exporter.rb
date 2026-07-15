# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require_relative 'cut_list_csv_exporter'

# Phase 3C quotation CSV export. It reuses the Phase 3B encoding and cell-safety
# contract so Excel behavior stays consistent across every exported document.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CostEstimateCSVExporter
        LINE_HEADERS = [
          'STT', 'Loại', 'Hạng mục', 'Số lượng', 'Dài (mm)', 'Rộng (mm)',
          'Dày (mm)', 'Diện tích tính giá (m²)', 'Đơn giá vật liệu (VND/m²)',
          'Tiền vật liệu (VND)', 'Dài dán cạnh (m)', 'Đơn giá dán cạnh (VND/m)',
          'Tiền dán cạnh (VND)', 'Đơn giá phụ kiện (VND/cái)',
          'Thành tiền (VND)', 'Tủ sử dụng'
        ].freeze

        module_function

        def output_path(path)
          value = path.to_s.strip
          raise ArgumentError, 'Vui lòng chọn tên file báo giá CSV.' if value.empty?

          value.match?(/\.csv\z/i) ? value : "#{value}.csv"
        end

        def csv(estimate)
          rows = []
          rows << LINE_HEADERS
          index = 0
          Array(estimate[:board_rows]).each do |row|
            index += 1
            rows << board_line(index, row)
          end
          Array(estimate[:hardware_rows]).each do |row|
            index += 1
            rows << hardware_line(index, row)
          end
          rows << []
          rows << ['TỔNG THEO TỦ']
          rows << ['STT', 'Tên tủ', 'Mã tủ', 'Thành tiền (VND)']
          Array(estimate[:cabinet_totals]).each_with_index do |cabinet, cabinet_index|
            rows << [
              cabinet_index + 1,
              safe(cabinet[:cabinet_name]),
              safe(cabinet[:cabinet_id]),
              money_number(cabinet[:total_cost])
            ]
          end
          rows << []
          rows << ['TỔNG HỢP DỰ TOÁN']
          rows << ['Tiền vật liệu', money_number(estimate[:material_subtotal])]
          rows << ['Tiền dán cạnh', money_number(estimate[:edge_subtotal])]
          rows << ['Tiền phụ kiện', money_number(estimate[:hardware_subtotal])]
          rows << ['TỔNG CỘNG', money_number(estimate[:project_total])]
          body = CSV.generate(row_sep: "\r\n", force_quotes: true) do |document|
            rows.each { |row| document << row }
          end
          CutListCSVExporter::UTF8_BOM + body
        end

        def write(estimate, path)
          target = output_path(path)
          directory = File.dirname(File.expand_path(target))
          raise ArgumentError, "Thư mục xuất không tồn tại: #{directory}" unless Dir.exist?(directory)

          temporary = "#{target}.sonvu-#{Process.pid}-#{SecureRandom.hex(6)}.tmp"
          File.open(temporary, 'wb') { |file| file.write(csv(estimate).encode(Encoding::UTF_8)) }
          FileUtils.mv(temporary, target, force: true)
          target
        ensure
          begin
            File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
          rescue StandardError
            # Preserve the original export result or error if temp cleanup fails.
          end
        end

        def board_line(index, row)
          [
            index, 'Chi tiết ván', safe(row[:name]), row[:quantity],
            dimension(row[:length_mm]), dimension(row[:width_mm]), dimension(row[:thickness_mm]),
            decimal(row[:billable_area_m2]), money_number(row[:material_unit_price]),
            money_number(row[:material_cost]), decimal(row[:edge_length_m]),
            money_number(row[:edge_unit_price]), money_number(row[:edge_cost]), '',
            money_number(row[:total_cost]), safe(Array(row[:cabinet_names]).join(' / '))
          ]
        end

        def hardware_line(index, row)
          [
            index, 'Phụ kiện', safe(row[:name]), row[:quantity],
            dimension(row[:length_mm]), dimension(row[:width_mm]), dimension(row[:thickness_mm]),
            '', '', '', '', '', '', money_number(row[:unit_price]),
            money_number(row[:total_cost]), safe(Array(row[:cabinet_names]).join(' / '))
          ]
        end

        def safe(value)
          CutListCSVExporter.spreadsheet_text(value)
        end

        def dimension(value)
          CutListCSVExporter.dimension(value)
        end

        def decimal(value)
          format('%.3f', value.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        end

        def money_number(value)
          value.to_f.round.to_i
        end
      end
    end
  end
end
