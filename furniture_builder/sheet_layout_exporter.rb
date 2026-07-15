# frozen_string_literal: true

require 'cgi'
require 'csv'
require 'fileutils'
require 'securerandom'
require_relative 'cut_list_csv_exporter'
require_relative 'sheet_layout_svg'

# Phase 4C production handoff. It exports one self-contained printable HTML
# report and one Excel-friendly placement CSV without changing the model.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module SheetLayoutExporter
        HTML_SUFFIX = '_phuong_an_cat.html'
        CSV_SUFFIX = '_toa_do_cat.csv'
        PLACEMENT_HEADERS = [
          'STT', 'Trạng thái', 'Nhóm vật liệu', 'Vật liệu', 'Dày (mm)',
          'Tấm số', 'Dài tấm (mm)', 'Rộng tấm (mm)', 'Lề xén (mm)',
          'Đường cưa (mm)', 'Khoảng cách chi tiết (mm)', 'Mã chi tiết',
          'Tên chi tiết', 'Nhóm chi tiết', 'Dài gốc (mm)', 'Rộng gốc (mm)',
          'X (mm)', 'Y (mm)', 'Dài đặt (mm)', 'Rộng đặt (mm)', 'Xoay 90°',
          'Hướng vân', 'Trục vân trên chi tiết', 'Chiều vân trên tấm',
          'Tủ sử dụng', 'Lý do chưa xếp'
        ].freeze

        module_function

        def output_paths(base_path)
          value = base_path.to_s.strip
          raise ArgumentError, 'Vui lòng chọn tên file xuất phương án cắt.' if value.empty?

          stem = value.sub(/\.(?:html?|csv)\z/i, '')
          { report: "#{stem}#{HTML_SUFFIX}", placements: "#{stem}#{CSV_SUFFIX}" }
        end

        def placement_csv(result)
          body = CSV.generate(row_sep: "\r\n", force_quotes: true) do |document|
            document << PLACEMENT_HEADERS
            placement_rows(result).each { |row| document << row }
          end
          CutListCSVExporter::UTF8_BOM + body
        end

        def placement_rows(result)
          settings = result[:settings] || {}
          row_index = 0
          Array(result[:groups]).flat_map.with_index do |group, group_index|
            placed = Array(group[:sheets]).flat_map do |sheet|
              Array(sheet[:placements]).map do |item|
                row_index += 1
                placement_row(
                  row_index, 'Đã xếp', group, group_index, sheet[:index], item,
                  settings, ''
                )
              end
            end
            unplaced = Array(group[:unplaced]).map do |item|
              row_index += 1
              placement_row(
                row_index, 'Chưa xếp', group, group_index, '', item,
                settings, item[:reason]
              )
            end
            placed + unplaced
          end
        end

        def placement_row(index, status, group, group_index, sheet_index, item, settings, reason)
          placed = status == 'Đã xếp'
          [
            index,
            status,
            "Nhóm #{group_index + 1}",
            safe(group[:material_name]),
            dimension(group[:thickness_mm]),
            sheet_index,
            dimension(settings[:sheet_length_mm]),
            dimension(settings[:sheet_width_mm]),
            dimension(settings[:edge_trim_mm]),
            dimension(settings[:kerf_mm]),
            dimension(settings[:part_spacing_mm]),
            safe(item[:id]),
            safe(item[:name]),
            safe(item[:category]),
            dimension(item[:length_mm]),
            dimension(item[:width_mm]),
            placed ? dimension(item[:x]) : '',
            placed ? dimension(item[:y]) : '',
            placed ? dimension(item[:placed_length_mm]) : '',
            placed ? dimension(item[:placed_width_mm]) : '',
            placed ? yes_no(item[:rotated]) : '',
            grain_direction_label(item[:grain_direction]),
            grain_axis_label(item[:grain_axis]),
            placed ? sheet_grain_label(item) : '',
            safe(Array(item[:cabinet_names]).join(' / ')),
            safe(reason)
          ]
        end

        def report_html(report, result)
          settings = result[:settings] || {}
          sheets = Array(result[:groups]).each_with_index.flat_map do |group, group_index|
            Array(group[:sheets]).map do |sheet|
              report_sheet_html(group, group_index, sheet, settings)
            end
          end.join
          unplaced = report_unplaced_html(result[:groups])
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>Phương án cắt ván SonVu</title>
                <style>
                  :root { --text:#172019; --muted:#68716a; --line:#cfd6d1; --accent:#226c4a; }
                  * { box-sizing:border-box; }
                  body { margin:0; padding:18px; color:var(--text); background:#f2f4f2; font:12px/1.4 "Segoe UI",Arial,sans-serif; }
                  .document { max-width:1180px; margin:auto; }
                  header,.sheet-report,.unplaced { margin:0 0 16px; padding:16px; background:#fff; border:1px solid var(--line); border-radius:8px; }
                  h1 { margin:0 0 4px; font-size:24px; } h2 { margin:0 0 5px; font-size:17px; } h3 { margin:14px 0 7px; font-size:13px; }
                  .brand { color:var(--accent); font-size:10px; font-weight:800; text-transform:uppercase; }
                  .muted { color:var(--muted); }
                  .summary { display:grid; grid-template-columns:repeat(6,minmax(100px,1fr)); gap:8px; margin-top:12px; }
                  .card { padding:8px; border:1px solid var(--line); border-radius:5px; } .card strong { display:block; color:var(--accent); font-size:16px; }
                  .settings { margin-top:10px; color:var(--muted); }
                  .sheet-meta { display:flex; justify-content:space-between; gap:12px; margin-bottom:10px; }
                  .sheet-map { display:block; width:100%; height:auto; background:#eef1ed; }
                  .stock-sheet { fill:#faf8ef; stroke:#354039; stroke-width:5; vector-effect:non-scaling-stroke; }
                  .usable-area { fill:none; stroke:#ad2e24; stroke-width:2; stroke-dasharray:10 8; vector-effect:non-scaling-stroke; }
                  .part-rectangle { stroke:#315b46; stroke-width:2; vector-effect:non-scaling-stroke; }
                  .part-label text { fill:#172019; text-anchor:middle; dominant-baseline:middle; font-weight:750; }
                  .part-label .part-dimensions { fill:#405149; font-weight:600; }
                  .grain-arrow { stroke:#315b46; stroke-width:3; vector-effect:non-scaling-stroke; }
                  .rotation-badge { fill:#8a3f1f; font-weight:900; }
                  .sheet-axes { fill:#56645b; text-anchor:middle; font-weight:700; }
                  table { width:100%; border-collapse:collapse; font-size:10px; }
                  th,td { padding:5px 6px; border:1px solid #dfe4e1; text-align:left; } th { background:#f3f6f4; }
                  .num { text-align:right; }
                  .print-action { position:fixed; right:18px; top:18px; padding:9px 14px; border:0; border-radius:5px; background:var(--accent); color:#fff; font:inherit; font-weight:750; cursor:pointer; }
                  @page { size:A4 landscape; margin:10mm; }
                  @media print {
                    body { padding:0; background:#fff; } .document { max-width:none; } .print-action { display:none; }
                    header,.sheet-report,.unplaced { border:0; border-radius:0; padding:0; }
                    header { break-after:page; } .sheet-report { break-after:page; page-break-after:always; }
                    .sheet-map { max-height:125mm; }
                  }
                </style>
              </head>
              <body>
                <button class="print-action" type="button" onclick="window.print()">In / Lưu PDF</button>
                <main class="document">
                  <header>
                    <div class="brand">SonVu Furniture Builder — Phase 4C</div>
                    <h1>Phương án cắt ván</h1>
                    <div class="muted">Phạm vi: #{h(report[:scope])} · #{report[:cabinet_count].to_i} tủ</div>
                    #{report_summary_html(result)}
                    <div class="settings">Tấm #{dimension(settings[:sheet_length_mm])} × #{dimension(settings[:sheet_width_mm])} mm · Lề xén #{dimension(settings[:edge_trim_mm])} mm · Đường cưa #{dimension(settings[:kerf_mm])} mm · Khoảng cách #{dimension(settings[:part_spacing_mm])} mm · Xoay 90°: #{yes_no(settings[:allow_rotation])} · Giữ chiều vân: #{yes_no(settings[:respect_grain])}</div>
                  </header>
                  #{sheets}
                  #{unplaced}
                </main>
              </body>
            </html>
          HTML
        end

        def report_summary_html(result)
          values = [
            [result[:sheet_count], 'Số tấm'], [result[:part_count], 'Tổng chi tiết'],
            [result[:placed_count], 'Đã xếp'], [result[:unplaced_count], 'Chưa xếp'],
            ["#{decimal(result[:utilization_percent])}%", 'Hiệu suất'],
            ["#{decimal(result[:waste_area_m2])} m²", 'Diện tích thừa']
          ]
          cards = values.map do |value, label|
            "<div class=\"card\"><strong>#{h(value)}</strong><span>#{h(label)}</span></div>"
          end.join
          "<section class=\"summary\">#{cards}</section>"
        end

        def report_sheet_html(group, group_index, sheet, settings)
          rows = Array(sheet[:placements]).map do |item|
            "<tr><td>#{h(item[:id])}</td><td>#{h(item[:name])}</td><td class=\"num\">#{dimension(item[:x])}</td><td class=\"num\">#{dimension(item[:y])}</td><td class=\"num\">#{dimension(item[:placed_length_mm])}</td><td class=\"num\">#{dimension(item[:placed_width_mm])}</td><td>#{yes_no(item[:rotated])}</td><td>#{h(Array(item[:cabinet_names]).join(' / '))}</td></tr>"
          end.join
          <<~HTML
            <section class="sheet-report">
              <div class="sheet-meta"><div><div class="brand">Nhóm #{group_index + 1}</div><h2>#{h(group[:material_name])} · #{dimension(group[:thickness_mm])} mm · Tấm #{sheet[:index]}</h2></div><div class="muted">#{sheet[:part_count]} chi tiết · Hiệu suất #{decimal(sheet[:utilization_percent])}% · Thừa #{decimal(sheet[:waste_area_m2])} m²</div></div>
              #{SheetLayoutSVG.render(sheet, settings, identifier: "export-map-#{group_index + 1}-#{sheet[:index]}")}
              <h3>Bảng tọa độ</h3>
              <table><thead><tr><th>Mã</th><th>Chi tiết</th><th class="num">X</th><th class="num">Y</th><th class="num">Dài đặt</th><th class="num">Rộng đặt</th><th>Xoay 90°</th><th>Tủ sử dụng</th></tr></thead><tbody>#{rows}</tbody></table>
            </section>
          HTML
        end

        def report_unplaced_html(groups)
          items = Array(groups).flat_map do |group|
            Array(group[:unplaced]).map { |item| [group, item] }
          end
          return '' if items.empty?

          rows = items.map do |group, item|
            "<tr><td>#{h(group[:material_name])}</td><td>#{dimension(group[:thickness_mm])}</td><td>#{h(item[:id])}</td><td>#{h(item[:name])}</td><td>#{dimension(item[:length_mm])} × #{dimension(item[:width_mm])}</td><td>#{h(item[:reason])}</td></tr>"
          end.join
          "<section class=\"unplaced\"><h2>Chi tiết chưa xếp được (#{items.length})</h2><table><thead><tr><th>Vật liệu</th><th>Dày</th><th>Mã</th><th>Chi tiết</th><th>Kích thước</th><th>Lý do</th></tr></thead><tbody>#{rows}</tbody></table></section>"
        end

        def write(report, result, base_path)
          paths = output_paths(base_path)
          payloads = {
            paths[:report] => report_html(report, result).encode(Encoding::UTF_8),
            paths[:placements] => placement_csv(result).encode(Encoding::UTF_8)
          }
          temporary_paths = []
          payloads.each do |path, payload|
            directory = File.dirname(File.expand_path(path))
            raise ArgumentError, "Thư mục xuất không tồn tại: #{directory}" unless Dir.exist?(directory)

            temporary = temporary_path(path)
            temporary_paths << temporary
            File.open(temporary, 'wb') { |file| file.write(payload) }
          end
          payloads.keys.zip(temporary_paths).each do |target, temporary|
            FileUtils.mv(temporary, target, force: true)
          end
          paths
        ensure
          temporary_paths&.each do |temporary|
            File.delete(temporary) if File.exist?(temporary)
          rescue StandardError
            # Preserve the original export result or error if cleanup fails.
          end
        end

        def temporary_path(target)
          "#{target}.sonvu-#{Process.pid}-#{SecureRandom.hex(6)}.tmp"
        end

        def grain_direction_label(value)
          return 'Dọc' if value.to_s == 'dọc'
          return 'Ngang' if value.to_s == 'ngang'

          'Không áp dụng'
        end

        def grain_axis_label(value)
          value.to_s == 'width' ? 'Theo chiều rộng' : 'Theo chiều dài'
        end

        def sheet_grain_label(item)
          case SheetLayoutSVG.placed_grain_axis(item)
          when 'horizontal' then 'Theo chiều dài tấm'
          when 'vertical' then 'Theo chiều rộng tấm'
          else 'Không áp dụng'
          end
        end

        def yes_no(value)
          value == true ? 'Có' : 'Không'
        end

        def dimension(value)
          CutListCSVExporter.dimension(value)
        end

        def decimal(value)
          format('%.2f', value.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        end

        def safe(value)
          CutListCSVExporter.spreadsheet_text(value)
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
