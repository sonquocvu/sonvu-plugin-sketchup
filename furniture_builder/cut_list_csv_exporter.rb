# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'securerandom'

# Phase 3B dependency-free CSV export. Two UTF-8 BOM files are emitted so the
# board and hardware tables open separately and preserve Vietnamese in Excel.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CutListCSVExporter
        UTF8_BOM = "\uFEFF"
        BOARD_SUFFIX = '_chi_tiet_van.csv'
        HARDWARE_SUFFIX = '_phu_kien.csv'
        BOARD_HEADERS = [
          'STT', 'Nhóm', 'Tên chi tiết', 'Số lượng', 'Dài (mm)', 'Rộng (mm)',
          'Dày (mm)', 'Vật liệu', 'Hướng vân', 'Trục vân trên chi tiết',
          'Dán cạnh trước', 'Dán cạnh sau', 'Dán cạnh trái', 'Dán cạnh phải',
          'Tủ sử dụng', 'Mã tủ'
        ].freeze
        HARDWARE_HEADERS = [
          'STT', 'Phụ kiện', 'Số lượng', 'Dài (mm)', 'Rộng (mm)', 'Dày (mm)',
          'Vật liệu', 'Tủ sử dụng', 'Mã tủ', 'Chỉ số ngăn kéo',
          'Mã chi tiết chủ quản'
        ].freeze

        module_function

        def output_paths(base_path)
          path = base_path.to_s.strip
          raise ArgumentError, 'Vui lòng chọn tên file xuất CSV.' if path.empty?

          stem = path.sub(/\.csv\z/i, '')
          {
            boards: "#{stem}#{BOARD_SUFFIX}",
            hardware: "#{stem}#{HARDWARE_SUFFIX}"
          }
        end

        def board_csv(report)
          rows = Array(report[:board_rows]).each_with_index.map do |row, index|
            [
              index + 1,
              spreadsheet_text(row[:category]),
              spreadsheet_text(row[:name]),
              row[:quantity],
              dimension(row[:length_mm]),
              dimension(row[:width_mm]),
              dimension(row[:thickness_mm]),
              spreadsheet_text(row[:material_name]),
              grain_label(row[:grain_direction]),
              grain_axis_label(row[:grain_axis]),
              yes_no(row[:edge_front]),
              yes_no(row[:edge_back]),
              yes_no(row[:edge_left]),
              yes_no(row[:edge_right]),
              joined(row[:cabinet_names]),
              joined(row[:cabinet_ids])
            ]
          end
          csv_document(BOARD_HEADERS, rows)
        end

        def hardware_csv(report)
          rows = Array(report[:hardware_rows]).each_with_index.map do |row, index|
            [
              index + 1,
              spreadsheet_text(row[:name]),
              row[:quantity],
              dimension(row[:length_mm]),
              dimension(row[:width_mm]),
              dimension(row[:thickness_mm]),
              spreadsheet_text(row[:material_name]),
              joined(row[:cabinet_names]),
              joined(row[:cabinet_ids]),
              joined(row[:drawer_indices]),
              joined(row[:owner_part_keys])
            ]
          end
          csv_document(HARDWARE_HEADERS, rows)
        end

        def write(report, base_path)
          paths = output_paths(base_path)
          payloads = {
            paths[:boards] => board_csv(report),
            paths[:hardware] => hardware_csv(report)
          }
          temporary_paths = []
          payloads.each do |path, payload|
            directory = File.dirname(File.expand_path(path))
            raise ArgumentError, "Thư mục xuất không tồn tại: #{directory}" unless Dir.exist?(directory)

            temporary = temporary_path(path)
            temporary_paths << temporary
            File.open(temporary, 'wb') { |file| file.write(payload.encode(Encoding::UTF_8)) }
          end
          payloads.keys.zip(temporary_paths).each do |target, temporary|
            FileUtils.mv(temporary, target, force: true)
          end
          paths
        ensure
          temporary_paths&.each do |temporary|
            File.delete(temporary) if File.exist?(temporary)
          rescue StandardError
            # A stale temporary export is safer than hiding the original error.
          end
        end

        def csv_document(headers, rows)
          body = CSV.generate(row_sep: "\r\n", force_quotes: true) do |csv|
            csv << headers
            rows.each { |row| csv << row }
          end
          UTF8_BOM + body
        end

        def temporary_path(target)
          "#{target}.sonvu-#{Process.pid}-#{SecureRandom.hex(6)}.tmp"
        end

        def dimension(value)
          number = value.to_f.round(3)
          return number.to_i.to_s if number == number.to_i

          format('%.3f', number).sub(/0+\z/, '')
        end

        def grain_label(value)
          return 'Dọc' if value.to_s == 'dọc'
          return 'Ngang' if value.to_s == 'ngang'

          'Không áp dụng'
        end

        def grain_axis_label(value)
          value.to_s == 'width' ? 'Theo chiều rộng' : 'Theo chiều dài'
        end

        def yes_no(value)
          value == true ? 'Có' : 'Không'
        end

        def joined(values)
          spreadsheet_text(Array(values).join(' / '))
        end

        def spreadsheet_text(value)
          text = value.to_s
          return "'#{text}" if text.match?(/\A[\t\r ]*[=+\-@]/)

          text
        end
      end
    end
  end
end
