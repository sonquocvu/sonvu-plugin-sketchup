# frozen_string_literal: true

require 'cgi'

# Vietnamese Phase 3A report with the explicit Phase 3B CSV export callback.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CutListDialogHTML
        module_function

        def html(report)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root { color-scheme: light; --bg:#f2f4f2; --panel:#fff; --text:#172019; --muted:#68716a; --line:#d9dedb; --accent:#226c4a; }
                  * { box-sizing: border-box; }
                  body { margin:0; background:var(--bg); color:var(--text); font:13px/1.45 "Segoe UI", Arial, sans-serif; }
                  .shell { padding:18px; min-width:760px; }
                  header { display:flex; justify-content:space-between; gap:16px; align-items:flex-start; margin-bottom:14px; }
                  h1 { margin:2px 0 4px; font-size:23px; }
                  h2 { margin:0; padding:13px 14px; font-size:15px; border-bottom:1px solid var(--line); }
                  .brand { color:var(--accent); font-size:11px; font-weight:800; text-transform:uppercase; }
                  .scope { color:var(--muted); }
                  .summary { display:grid; grid-template-columns:repeat(4,minmax(120px,1fr)); gap:10px; margin-bottom:12px; }
                  .card,.section,.warning { background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .card { padding:11px 13px; }
                  .card strong { display:block; color:var(--accent); font-size:20px; }
                  .card span { color:var(--muted); font-size:11px; }
                  .section { margin-bottom:12px; overflow:hidden; }
                  .table-wrap { overflow:auto; max-height:310px; }
                  table { width:100%; border-collapse:collapse; white-space:nowrap; }
                  th,td { padding:8px 10px; border-bottom:1px solid #edf0ee; text-align:left; vertical-align:top; }
                  th { position:sticky; top:0; z-index:1; background:#f7f9f7; color:#4f5d53; font-size:11px; }
                  td.num,th.num { text-align:right; }
                  td.center,th.center { text-align:center; }
                  tbody tr:hover { background:#f5faf7; }
                  .name { white-space:normal; min-width:180px; font-weight:650; }
                  .cabinets { white-space:normal; min-width:150px; color:var(--muted); }
                  .empty { padding:18px; color:var(--muted); }
                  .warning { margin-bottom:12px; padding:10px 12px; background:#fff8e8; border-color:#ead8a9; color:#765b14; }
                  .warning ul { margin:5px 0 0 18px; padding:0; }
                  .footer { display:flex; justify-content:space-between; align-items:center; gap:12px; }
                  .note { color:var(--muted); font-size:11px; }
                  .actions { display:flex; gap:8px; }
                  button { border:1px solid var(--accent); border-radius:6px; background:var(--accent); color:#fff; padding:8px 16px; font:inherit; font-weight:750; cursor:pointer; }
                  button.secondary { border-color:#c8d0ca; background:#fff; color:var(--text); }
                </style>
              </head>
              <body>
                <main class="shell">
                  <header>
                    <div><div class="brand">SonVu Furniture Builder — Bước 3</div><h1>Danh sách chi tiết</h1><div class="scope">Phạm vi: #{h(report[:scope])}</div></div>
                  </header>
                  <section class="summary">
                    #{summary_card(report[:cabinet_count], 'Số tủ')}
                    #{summary_card(report[:part_count], 'Tổng chi tiết')}
                    #{summary_card(report[:board_count], 'Chi tiết ván')}
                    #{summary_card(report[:hardware_count], 'Phụ kiện')}
                  </section>
                  #{warning_html(report[:warnings])}
                  #{section_html('Chi tiết ván', report[:board_rows], false)}
                  #{section_html('Phụ kiện', report[:hardware_rows], true)}
                  <div class="footer"><div class="note">Bước 4 xếp, hiển thị và xuất phương án cắt theo vật liệu, độ dày và chiều vân.</div><div class="actions"><button class="secondary" type="button" onclick="window.sketchup.closeCutList()">Đóng</button><button type="button" onclick="window.sketchup.exportCutList()">Xuất CSV</button><button type="button" onclick="window.sketchup.openCostEstimate()">Dự toán chi phí</button><button type="button" onclick="window.sketchup.openSheetOptimization()">Tối ưu cắt ván</button></div></div>
                </main>
              </body>
            </html>
          HTML
        end

        def summary_card(value, label)
          "<div class=\"card\"><strong>#{value.to_i}</strong><span>#{h(label)}</span></div>"
        end

        def section_html(title, rows, hardware)
          body = rows.empty? ? '<div class="empty">Không có dữ liệu.</div>' : table_html(rows, hardware)
          "<section class=\"section\"><h2>#{h(title)} (#{rows.length} dòng)</h2>#{body}</section>"
        end

        def table_html(rows, hardware)
          headers = if hardware
                      '<th>Phụ kiện</th><th class="num">SL</th><th class="num">Dài</th><th class="num">Rộng</th><th class="num">Dày</th><th>Vật liệu</th><th>Tủ sử dụng</th>'
                    else
                      '<th>Nhóm</th><th>Chi tiết</th><th class="num">SL</th><th class="num">Dài</th><th class="num">Rộng</th><th class="num">Dày</th><th>Vật liệu</th><th class="center">Vân</th><th>Trục vân</th><th>Dán cạnh</th><th>Tủ sử dụng</th>'
                    end
          body = rows.map { |row| row_html(row, hardware) }.join
          "<div class=\"table-wrap\"><table><thead><tr>#{headers}</tr></thead><tbody>#{body}</tbody></table></div>"
        end

        def row_html(row, hardware)
          common = "<td class=\"name\">#{h(row[:name])}</td><td class=\"num\">#{row[:quantity]}</td>" \
                   "<td class=\"num\">#{dimension(row[:length_mm])}</td><td class=\"num\">#{dimension(row[:width_mm])}</td>" \
                   "<td class=\"num\">#{dimension(row[:thickness_mm])}</td><td>#{h(row[:material_name])}</td>"
          cabinets = "<td class=\"cabinets\">#{h(row[:cabinet_names].join(' / '))}</td>"
          return "<tr>#{common}#{cabinets}</tr>" if hardware

          "<tr><td>#{h(row[:category])}</td>#{common}<td class=\"center\">#{h(grain_label(row[:grain_direction]))}</td><td>#{h(grain_axis_label(row[:grain_axis]))}</td><td>#{h(edge_label(row))}</td>#{cabinets}</tr>"
        end

        def warning_html(warnings)
          return '' if warnings.empty?

          items = warnings.map { |warning| "<li>#{h(warning)}</li>" }.join
          "<div class=\"warning\"><strong>Cảnh báo dữ liệu</strong><ul>#{items}</ul></div>"
        end

        def edge_label(row)
          labels = []
          labels << 'Trước' if row[:edge_front]
          labels << 'Sau' if row[:edge_back]
          labels << 'Trái' if row[:edge_left]
          labels << 'Phải' if row[:edge_right]
          labels.empty? ? 'Không' : labels.join(', ')
        end

        def grain_label(value)
          return 'Dọc' if value == 'dọc'
          return 'Ngang' if value == 'ngang'

          '—'
        end

        def grain_axis_label(value)
          value == 'width' ? 'Theo chiều rộng' : 'Theo chiều dài'
        end

        def dimension(value)
          number = value.to_f.round(3)
          number == number.to_i ? number.to_i.to_s : format('%.3f', number).sub(/0+\z/, '')
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
