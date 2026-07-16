# frozen_string_literal: true

require 'cgi'
require_relative 'sheet_layout_svg'

# Vietnamese Phase 4C optimizer with interactive SVG maps and explicit export.
# The coordinate table remains available as an auditable Phase 4A data view.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module SheetOptimizationDialogHTML
        module_function

        def html(report, settings, result = nil)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root { color-scheme:light; --bg:#f2f4f2; --panel:#fff; --text:#172019; --muted:#68716a; --line:#d9dedb; --accent:#226c4a; --danger:#ad2e24; --warn:#765b14; }
                  * { box-sizing:border-box; }
                  body { margin:0; background:var(--bg); color:var(--text); font:13px/1.45 "Segoe UI",Arial,sans-serif; }
                  .shell { padding:18px; min-width:820px; }
                  .brand { color:var(--accent); font-size:11px; font-weight:800; text-transform:uppercase; }
                  h1 { margin:2px 0 4px; font-size:23px; }
                  h2 { margin:0 0 12px; font-size:15px; }
                  h3 { margin:14px 0 8px; font-size:13px; }
                  .scope,.note { color:var(--muted); }
                  .panel { margin:12px 0; padding:14px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .grid { display:grid; grid-template-columns:repeat(5,minmax(120px,1fr)); gap:10px; }
                  .field { display:grid; gap:5px; }
                  label { color:var(--muted); font-size:11px; font-weight:750; }
                  input[type=number] { width:100%; min-height:36px; border:1px solid #c8d0ca; border-radius:6px; padding:7px 9px; font:inherit; text-align:right; }
                  .unit-input { position:relative; }
                  .unit-input input { padding-right:33px; }
                  .unit { position:absolute; right:9px; top:50%; transform:translateY(-50%); color:var(--muted); font-size:11px; }
                  .checks { display:flex; flex-wrap:wrap; gap:18px; margin-top:12px; }
                  .check { display:flex; align-items:center; gap:7px; color:var(--text); font-size:12px; cursor:pointer; }
                  .summary { display:grid; grid-template-columns:repeat(6,minmax(115px,1fr)); gap:8px; margin:12px 0; }
                  .card { padding:10px 11px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .card strong { display:block; color:var(--accent); font-size:17px; }
                  .card span { color:var(--muted); font-size:10px; }
                  .group { margin:12px 0; overflow:hidden; background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .group-head { display:flex; justify-content:space-between; gap:15px; padding:11px 13px; background:#f7f9f7; border-bottom:1px solid var(--line); }
                  .group-head strong { overflow-wrap:anywhere; }
                  .sheet-nav { display:flex; flex-wrap:wrap; gap:6px; padding:10px 13px 0; }
                  .sheet-tab { min-height:31px; padding:5px 11px; border-color:#c8d0ca; background:#fff; color:var(--text); font-size:11px; }
                  .sheet-tab.active { border-color:var(--accent); background:#e6f2eb; color:var(--accent); }
                  .sheet { padding:0 13px 13px; }
                  .sheet-title { display:flex; justify-content:space-between; gap:10px; margin:13px 0 7px; }
                  .map-shell { border:1px solid var(--line); border-radius:7px; background:#eef1ed; overflow:hidden; }
                  .map-toolbar { display:flex; justify-content:space-between; align-items:center; gap:10px; padding:7px 9px; border-bottom:1px solid var(--line); background:#fff; }
                  .legend { display:flex; flex-wrap:wrap; gap:12px; color:var(--muted); font-size:10px; }
                  .legend span { display:inline-flex; align-items:center; gap:5px; }
                  .legend-part { width:16px; height:10px; border:1px solid #315b46; background:#b8dfca; }
                  .legend-trim { width:16px; height:10px; border:1px dashed #ad2e24; }
                  .legend-grain { color:#315b46; font-size:16px; line-height:10px; }
                  .zoom-controls { display:flex; align-items:center; gap:5px; white-space:nowrap; }
                  .map-button { min-width:31px; min-height:29px; padding:3px 8px; border-color:#c8d0ca; background:#fff; color:var(--text); font-size:12px; }
                  .zoom-label { min-width:39px; color:var(--muted); text-align:center; font-size:10px; }
                  .sheet-map-viewport { max-height:520px; overflow:auto; padding:12px; }
                  .sheet-map-scale { width:100%; transition:width .15s ease; }
                  .sheet-map { display:block; width:100%; height:auto; filter:drop-shadow(0 2px 3px rgba(0,0,0,.12)); }
                  .stock-sheet { fill:#faf8ef; stroke:#354039; stroke-width:5; vector-effect:non-scaling-stroke; }
                  .usable-area { fill:none; stroke:#ad2e24; stroke-width:2; stroke-dasharray:10 8; vector-effect:non-scaling-stroke; }
                  .part-rectangle { stroke:#315b46; stroke-width:2; vector-effect:non-scaling-stroke; }
                  .part-shape:hover .part-rectangle { stroke:#102d20; stroke-width:4; filter:brightness(1.04); }
                  .part-label text { fill:#172019; text-anchor:middle; dominant-baseline:middle; font-weight:750; pointer-events:none; }
                  .part-label .part-dimensions { fill:#405149; font-weight:600; }
                  .grain-arrow { stroke:#315b46; stroke-width:3; vector-effect:non-scaling-stroke; }
                  .rotation-badge { fill:#8a3f1f; font-weight:900; pointer-events:none; }
                  .sheet-axes { fill:#56645b; text-anchor:middle; font-weight:700; pointer-events:none; }
                  details.coordinates { margin-top:10px; }
                  details.coordinates summary { color:var(--accent); font-size:11px; font-weight:750; cursor:pointer; }
                  .table-wrap { overflow:auto; max-height:250px; border:1px solid var(--line); border-radius:6px; }
                  table { width:100%; border-collapse:collapse; white-space:nowrap; background:#fff; }
                  th,td { padding:7px 8px; border-bottom:1px solid #edf0ee; text-align:left; }
                  th { position:sticky; top:0; background:#f7f9f7; color:#4f5d53; font-size:11px; }
                  .num { text-align:right; }
                  .warning { margin:12px 13px; padding:10px 12px; border:1px solid #ead8a9; border-radius:7px; background:#fff8e8; color:var(--warn); }
                  .warning ul { margin:6px 0 0 18px; padding:0; }
                  .error { display:none; margin:12px 0; padding:10px; border:1px solid #e2b6b2; border-radius:7px; background:#fff3f2; color:var(--danger); font-weight:700; }
                  .actions { display:flex; justify-content:flex-end; gap:8px; margin-top:12px; }
                  button { min-height:38px; border:1px solid var(--accent); border-radius:6px; background:var(--accent); color:#fff; padding:8px 15px; font:inherit; font-weight:750; cursor:pointer; }
                  button.secondary { border-color:#c8d0ca; background:#fff; color:var(--text); }
                  button:disabled { opacity:.45; cursor:not-allowed; }
                </style>
              </head>
              <body>
                <main class="shell">
                  <div class="brand">SonVu Furniture Builder — Bước 4</div>
                  <h1>Tối ưu cắt ván</h1>
                  <div class="scope">Phạm vi: #{h(report[:scope])} · #{report[:cabinet_count].to_i} tủ · #{Array(report[:board_rows]).sum { |row| row[:quantity].to_i }} chi tiết ván</div>
                  <form id="optimizationForm">
                    <section class="panel">
                      <h2>Thông số tấm và đường cắt</h2>
                      <div class="grid">
                        #{number_input('sheet_length_mm', 'Chiều dài tấm', settings[:sheet_length_mm], 1)}
                        #{number_input('sheet_width_mm', 'Chiều rộng tấm', settings[:sheet_width_mm], 1)}
                        #{number_input('edge_trim_mm', 'Lề xén mỗi cạnh', settings[:edge_trim_mm], 0)}
                        #{number_input('kerf_mm', 'Bề rộng đường cưa', settings[:kerf_mm], 0)}
                        #{number_input('part_spacing_mm', 'Khoảng cách chi tiết', settings[:part_spacing_mm], 0)}
                      </div>
                      <div class="checks">
                        #{checkbox('allow_rotation', 'Cho phép xoay chi tiết 90°', settings[:allow_rotation])}
                        #{checkbox('respect_grain', 'Giữ đúng chiều vân đã thiết kế', settings[:respect_grain])}
                      </div>
                    </section>
                    <div id="error" class="error"></div>
                    #{result_html(result)}
                    <div class="note">Xuất phương án tạo một báo cáo HTML tự chứa để in/lưu PDF và một bảng CSV tọa độ. Bước này chưa tạo đường CNC.</div>
                    <div class="actions"><button class="secondary" type="button" onclick="window.sketchup.closeSheetOptimization()">Đóng</button><button type="submit">Tính phương án</button><button type="button" #{result ? '' : 'disabled'} onclick="window.sketchup.exportSheetOptimization()">Xuất phương án</button></div>
                  </form>
                </main>
                <script>
                  document.getElementById('optimizationForm').addEventListener('submit', (event) => {
                    event.preventDefault();
                    const payload = {};
                    ['sheet_length_mm','sheet_width_mm','edge_trim_mm','kerf_mm','part_spacing_mm'].forEach((id) => {
                      payload[id] = document.getElementById(id).value;
                    });
                    payload.allow_rotation = document.getElementById('allow_rotation').checked;
                    payload.respect_grain = document.getElementById('respect_grain').checked;
                    window.sketchup.calculateSheetOptimization(JSON.stringify(payload));
                  });
                  function showOptimizationError(message) {
                    const box = document.getElementById('error');
                    box.textContent = message;
                    box.style.display = 'block';
                  }
                  function showSheet(groupId, sheetId) {
                    const group = document.getElementById(groupId);
                    if (!group) return;
                    group.querySelectorAll('.sheet-view').forEach((view) => {
                      view.hidden = view.id !== sheetId;
                    });
                    group.querySelectorAll('.sheet-tab').forEach((button) => {
                      const active = button.dataset.sheetTarget === sheetId;
                      button.classList.toggle('active', active);
                      button.setAttribute('aria-selected', active ? 'true' : 'false');
                    });
                  }
                  function changeSheetZoom(scaleId, amount) {
                    const scale = document.getElementById(scaleId);
                    if (!scale) return;
                    const current = Number(scale.dataset.zoom || 100);
                    setSheetZoom(scaleId, Math.max(50, Math.min(250, current + amount)));
                  }
                  function setSheetZoom(scaleId, value) {
                    const scale = document.getElementById(scaleId);
                    if (!scale) return;
                    scale.dataset.zoom = value;
                    scale.style.width = value + '%';
                    const label = document.getElementById(scaleId + '-label');
                    if (label) label.textContent = value + '%';
                  }
                </script>
              </body>
            </html>
          HTML
        end

        def result_html(result)
          return '' unless result

          <<~HTML
            <section class="summary">
              #{summary_card(result[:sheet_count], 'Số tấm')}
              #{summary_card(result[:part_count], 'Tổng chi tiết')}
              #{summary_card(result[:placed_count], 'Đã xếp')}
              #{summary_card(result[:unplaced_count], 'Chưa xếp')}
              #{summary_card("#{decimal(result[:utilization_percent])}%", 'Hiệu suất')}
              #{summary_card("#{decimal(result[:waste_area_m2])} m²", 'Diện tích thừa')}
            </section>
            #{result[:groups].each_with_index.map { |group, index| group_html(group, result[:settings], index) }.join}
          HTML
        end

        def group_html(group, settings, group_index)
          group_id = "sheet-group-#{group_index + 1}"
          sheets = group[:sheets].each_with_index.map do |sheet, sheet_index|
            sheet_html(sheet, settings, group_index, sheet_index)
          end.join
          <<~HTML
            <section id="#{group_id}" class="group">
              <div class="group-head"><strong>#{h(group[:material_name])} · #{dimension(group[:thickness_mm])} mm</strong><span>#{group[:sheets].length} tấm · #{group[:placed_count]}/#{group[:part_count]} chi tiết · #{decimal(group[:utilization_percent])}%</span></div>
              #{sheet_navigation(group[:sheets], group_id, group_index)}
              #{sheets}
              #{unplaced_html(group[:unplaced])}
            </section>
          HTML
        end

        def sheet_html(sheet, settings, group_index, sheet_index)
          sheet_id = "sheet-view-#{group_index + 1}-#{sheet_index + 1}"
          scale_id = "sheet-scale-#{group_index + 1}-#{sheet_index + 1}"
          svg_id = "sheet-map-#{group_index + 1}-#{sheet_index + 1}"
          rows = sheet[:placements].map do |item|
            "<tr><td>#{h(item[:name])}</td><td class=\"num\">#{dimension(item[:x])}</td><td class=\"num\">#{dimension(item[:y])}</td><td class=\"num\">#{dimension(item[:placed_length_mm])}</td><td class=\"num\">#{dimension(item[:placed_width_mm])}</td><td>#{item[:rotated] ? 'Có' : 'Không'}</td><td>#{h(item[:cabinet_names].join(' / '))}</td></tr>"
          end.join
          <<~HTML
            <div id="#{sheet_id}" class="sheet sheet-view" #{sheet_index.zero? ? '' : 'hidden'}>
              <div class="sheet-title"><strong>Tấm #{sheet[:index]}</strong><span>#{sheet[:part_count]} chi tiết · hiệu suất #{decimal(sheet[:utilization_percent])}% · thừa #{decimal(sheet[:waste_area_m2])} m²</span></div>
              <div class="map-shell">
                <div class="map-toolbar"><div class="legend"><span><i class="legend-part"></i>Chi tiết</span><span><i class="legend-trim"></i>Lề xén</span><span><i class="legend-grain">→</i>Chiều vân</span></div><div class="zoom-controls"><button class="map-button" type="button" title="Thu nhỏ" onclick="changeSheetZoom('#{scale_id}',-25)">−</button><span id="#{scale_id}-label" class="zoom-label">100%</span><button class="map-button" type="button" title="Phóng to" onclick="changeSheetZoom('#{scale_id}',25)">+</button><button class="map-button" type="button" onclick="setSheetZoom('#{scale_id}',100)">Vừa khung</button></div></div>
                <div class="sheet-map-viewport"><div id="#{scale_id}" class="sheet-map-scale" data-zoom="100">#{SheetLayoutSVG.render(sheet, settings, identifier: svg_id)}</div></div>
              </div>
              <details class="coordinates"><summary>Xem bảng tọa độ (#{sheet[:part_count]} chi tiết)</summary><div class="table-wrap"><table><thead><tr><th>Chi tiết</th><th class="num">X (mm)</th><th class="num">Y (mm)</th><th class="num">Dài đặt</th><th class="num">Rộng đặt</th><th>Xoay 90°</th><th>Tủ sử dụng</th></tr></thead><tbody>#{rows}</tbody></table></div></details>
            </div>
          HTML
        end

        def sheet_navigation(sheets, group_id, group_index)
          return '' if sheets.empty?

          buttons = sheets.each_with_index.map do |sheet, sheet_index|
            sheet_id = "sheet-view-#{group_index + 1}-#{sheet_index + 1}"
            active = sheet_index.zero?
            "<button class=\"sheet-tab#{active ? ' active' : ''}\" type=\"button\" data-sheet-target=\"#{sheet_id}\" aria-selected=\"#{active}\" onclick=\"showSheet('#{group_id}','#{sheet_id}')\">Tấm #{sheet[:index]}</button>"
          end.join
          "<nav class=\"sheet-nav\" aria-label=\"Chọn tấm ván\">#{buttons}</nav>"
        end

        def unplaced_html(items)
          return '' if items.empty?

          rows = items.map do |item|
            "<li>#{h(item[:name])} — #{dimension(item[:length_mm])} × #{dimension(item[:width_mm])} mm: #{h(item[:reason])}</li>"
          end.join
          "<div class=\"warning\"><strong>Chi tiết chưa xếp được (#{items.length})</strong><ul>#{rows}</ul></div>"
        end

        def number_input(id, label, value, minimum)
          "<div class=\"field\"><label for=\"#{id}\">#{h(label)}</label><div class=\"unit-input\"><input id=\"#{id}\" type=\"number\" min=\"#{minimum}\" step=\"0.1\" value=\"#{h(value)}\"><span class=\"unit\">mm</span></div></div>"
        end

        def checkbox(id, label, checked)
          "<label class=\"check\" for=\"#{id}\"><input id=\"#{id}\" type=\"checkbox\" #{checked ? 'checked' : ''}>#{h(label)}</label>"
        end

        def summary_card(value, label)
          "<div class=\"card\"><strong>#{h(value)}</strong><span>#{h(label)}</span></div>"
        end

        def dimension(value)
          decimal(value)
        end

        def decimal(value)
          format('%.2f', value.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
