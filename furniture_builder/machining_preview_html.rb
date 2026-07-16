# frozen_string_literal: true

require 'cgi'
require 'json'

# Vietnamese, read-only CNC preparation preview for customer-facing Step 5.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module MachiningPreviewHTML
        module_function

        def html(project)
          rules = project[:rules] || MachiningRules.normalize
          views = face_views(project)
          presets_json = safe_json(MachiningRules.presets_for_json)
          rules_json = safe_json(rules)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root { color-scheme:light; --bg:#edf1ee; --panel:#fff; --text:#18231c; --muted:#687269; --line:#d4ddd6; --green:#1f6848; --green-dark:#164b35; --soft:#e9f4ed; --gold:#c98924; --danger:#aa3028; --warn:#815f18; }
                  * { box-sizing:border-box; }
                  body { margin:0; background:var(--bg); color:var(--text); font:13px/1.45 "Segoe UI","Noto Sans",Arial,sans-serif; }
                  .shell { max-width:1100px; margin:auto; padding:18px; }
                  header { display:flex; justify-content:space-between; gap:16px; align-items:start; margin-bottom:12px; }
                  .brand { color:var(--green); font-size:11px; font-weight:850; letter-spacing:.05em; text-transform:uppercase; }
                  h1 { margin:3px 0 4px; font-size:25px; }
                  h2 { margin:0; font-size:16px; }
                  .muted,.scope { color:var(--muted); }
                  .header-actions,.actions { display:flex; gap:8px; flex-wrap:wrap; }
                  button { min-height:36px; border:1px solid var(--green); border-radius:7px; padding:7px 13px; background:var(--green); color:#fff; font:inherit; font-weight:750; cursor:pointer; }
                  button.secondary { border-color:#c4cec7; background:#fff; color:var(--text); }
                  button:disabled { border-color:#c8cfca; background:#dfe4e1; color:#7b847e; cursor:not-allowed; }
                  .export-note { max-width:330px; margin-top:5px; color:var(--muted); font-size:10px; text-align:right; }
                  .notice { margin-bottom:12px; padding:10px 12px; border:1px solid #c5dacd; border-radius:8px; background:var(--soft); color:var(--green-dark); }
                  .rules { margin-bottom:12px; border:1px solid var(--line); border-radius:9px; background:#fff; }
                  .rules summary { cursor:pointer; padding:11px 13px; color:var(--green-dark); font-weight:850; }
                  .rules-body { padding:0 13px 13px; }
                  .rule-grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }
                  .field { display:grid; gap:5px; }
                  .field label { color:var(--muted); font-size:10px; font-weight:750; }
                  .field input,.field select { width:100%; min-height:35px; border:1px solid #c7d0ca; border-radius:6px; background:#fff; padding:6px 8px; font:inherit; }
                  .check { display:flex; align-items:center; gap:7px; min-height:35px; color:var(--text); font-size:11px; font-weight:700; }
                  .check input { width:17px; height:17px; accent-color:var(--green); }
                  .rule-group { grid-column:1/-1; display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; padding-top:9px; border-top:1px solid #e5eae6; }
                  .rule-group h3 { grid-column:1/-1; margin:0; font-size:12px; }
                  .rule-actions { display:flex; justify-content:flex-end; gap:8px; margin-top:11px; }
                  .error { display:none; margin-top:10px; padding:9px 11px; border:1px solid #e1b5b1; border-radius:7px; background:#fff2f1; color:var(--danger); font-weight:750; }
                  .summary { display:grid; grid-template-columns:repeat(4,minmax(115px,1fr)); gap:9px; margin-bottom:12px; }
                  .metric { padding:11px 12px; border:1px solid var(--line); border-radius:8px; background:#fff; }
                  .metric strong { display:block; color:var(--green); font-size:20px; }
                  .metric span { color:var(--muted); font-size:10px; }
                  .warnings { margin-bottom:12px; border:1px solid #e3cf9e; border-radius:8px; background:#fff9e9; padding:10px 13px; color:var(--warn); }
                  .warnings strong { display:block; margin-bottom:4px; }
                  .warnings ul { margin:0; padding-left:18px; }
                  .section-title { display:flex; justify-content:space-between; align-items:end; gap:10px; margin:16px 0 9px; }
                  .panel-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
                  .panel-card { overflow:hidden; border:1px solid var(--line); border-radius:9px; background:var(--panel); }
                  .panel-head { display:flex; justify-content:space-between; gap:12px; padding:11px 13px; border-bottom:1px solid var(--line); }
                  .panel-head .name { font-weight:800; }
                  .panel-head .dims { color:var(--muted); font-size:11px; text-align:right; }
                  .preview { padding:12px; background:#f8faf8; }
                  .panel-map { display:block; width:100%; height:210px; }
                  .board { fill:#e7c98e; stroke:#67491f; stroke-width:2; vector-effect:non-scaling-stroke; }
                  .grain { stroke:#b58b49; stroke-width:1; stroke-dasharray:8 7; vector-effect:non-scaling-stroke; opacity:.65; }
                  .operation { fill:#1f6848; fill-opacity:.22; stroke:#164b35; stroke-width:2; vector-effect:non-scaling-stroke; }
                  .operation.dowel { fill:#2d78a5; stroke:#174b6a; }
                  .operation.cam_pocket { fill:#d18b25; stroke:#835414; }
                  .operation.shelf_pin { fill:#606d65; stroke:#344139; }
                  .operation.back_groove { fill:#7b4f24; fill-opacity:.35; stroke:#523215; }
                  .operation.invalid { fill:#d5483f; stroke:#9e2922; }
                  .origin { fill:var(--gold); }
                  .legend { display:flex; gap:14px; margin-top:7px; color:var(--muted); font-size:10px; }
                  .dot { display:inline-block; width:9px; height:9px; margin-right:4px; border-radius:50%; background:var(--green); }
                  table { width:100%; border-collapse:collapse; }
                  th,td { padding:7px 9px; border-top:1px solid #e5eae6; text-align:left; font-size:11px; }
                  th { color:var(--muted); font-size:9px; text-transform:uppercase; }
                  .ready { color:var(--green); font-weight:800; }
                  .invalid-text { color:var(--danger); font-weight:800; }
                  .empty { padding:26px; border:1px dashed #bcc8c0; border-radius:9px; background:#f8faf8; color:var(--muted); text-align:center; }
                  footer { display:flex; justify-content:space-between; gap:12px; margin-top:14px; color:var(--muted); font-size:10px; }
                  @media (max-width:760px) { .panel-grid { grid-template-columns:1fr; } .summary { grid-template-columns:repeat(2,1fr); } header { flex-direction:column; } .rule-grid,.rule-group { grid-template-columns:repeat(2,1fr); } }
                </style>
              </head>
              <body>
                <main class="shell">
                  <header>
                    <div><div class="brand">SonVu Furniture Builder — Bước 5</div><h1>Xem trước gia công CNC</h1><div class="scope">Phạm vi: #{h(project[:scope])}</div></div>
                    <div>#{export_controls(project)}</div>
                  </header>
                  <div class="notice"><strong>Chế độ chuẩn bị an toàn.</strong> Bảng này chỉ đọc dữ liệu, không khoan/cắt model và chưa tạo mã máy CNC.</div>
                  #{rules_form(rules)}
                  <section class="summary">
                    #{metric(project[:cabinet_count], 'Tủ nội thất')}
                    #{metric(project[:panel_count], 'Chi tiết ván')}
                    #{metric(project[:ready_operation_count], 'Nguyên công sẵn sàng')}
                    #{metric(project[:reference_count], 'Tham chiếu phụ kiện')}
                  </section>
                  #{operation_type_summary(project[:operation_types])}
                  #{warnings_html(project[:warnings])}
                  <div class="section-title"><div><h2>Mặt có gia công</h2><div class="muted">Tọa độ X theo chiều dài, Y theo chiều rộng; gốc nằm ở góc dưới trái của chi tiết.</div></div><div class="muted">#{views.length} mặt gia công</div></div>
                  #{views.empty? ? empty_html : "<section class=\"panel-grid\">#{views.map { |view| panel_html(view[:panel], view[:face], view[:operations]) }.join}</section>"}
                  <footer><span>Mặt A: mặt chính · Mặt B: mặt sau</span><span>Bước này chưa xuất G-code</span></footer>
                </main>
                <script>
                  const machiningPresets = #{presets_json};
                  const initialRules = #{rules_json};
                  const numericRuleFields = #{safe_json(MachiningRules::NUMERIC_KEYS.map(&:to_s))};
                  const booleanRuleFields = #{safe_json(MachiningRules::BOOLEAN_KEYS.map(&:to_s))};
                  const presetSelect = document.getElementById('preset_key');

                  function applyMachiningRules(values) {
                    numericRuleFields.forEach((id) => { if (values[id] !== undefined) document.getElementById(id).value = values[id]; });
                    booleanRuleFields.forEach((id) => { if (values[id] !== undefined) document.getElementById(id).checked = Boolean(values[id]); });
                  }

                  presetSelect.addEventListener('change', () => {
                    const preset = machiningPresets[presetSelect.value];
                    if (preset) applyMachiningRules(preset);
                  });
                  applyMachiningRules(initialRules);

                  document.getElementById('machiningRulesForm').addEventListener('submit', (event) => {
                    event.preventDefault();
                    const payload = { preset_key: presetSelect.value };
                    numericRuleFields.forEach((id) => { payload[id] = document.getElementById(id).value; });
                    booleanRuleFields.forEach((id) => { payload[id] = document.getElementById(id).checked; });
                    window.sketchup.calculateMachiningPreview(JSON.stringify(payload));
                  });

                  function showMachiningError(message) {
                    const box = document.getElementById('machiningError');
                    box.textContent = message;
                    box.style.display = 'block';
                  }
                </script>
              </body>
            </html>
          HTML
        end

        def rules_form(rules)
          <<~HTML
            <details class="rules">
              <summary>Quy tắc gia công và mẫu khoan</summary>
              <div class="rules-body">
                <form id="machiningRulesForm">
                  <div class="rule-grid">
                    <div class="field"><label for="preset_key">Mẫu quy tắc</label><select id="preset_key">#{MachiningRules.options.map { |key, label| "<option value=\"#{h(key)}\"#{key == rules[:preset_key] ? ' selected' : ''}>#{h(label)}</option>" }.join}</select></div>
                    <div class="rule-group"><h3>Liên kết cam và chốt gỗ</h3>
                      #{check_field('include_connectors', 'Tạo lỗ chốt gỗ', rules)}
                      #{check_field('include_cam_pockets', 'Tạo ổ cam', rules)}
                      #{number_field('dowel_diameter_mm', 'Đường kính chốt', rules)}
                      #{number_field('dowel_depth_mm', 'Sâu lỗ chốt', rules)}
                      #{number_field('connector_front_offset_mm', 'Cách mép trước', rules)}
                      #{number_field('connector_rear_offset_mm', 'Cách mép sau', rules)}
                      #{number_field('cam_diameter_mm', 'Đường kính cam', rules)}
                      #{number_field('cam_depth_mm', 'Sâu ổ cam', rules)}
                      #{number_field('cam_edge_offset_mm', 'Tâm cam cách cạnh', rules)}
                    </div>
                    <div class="rule-group"><h3>Hàng lỗ đợt</h3>
                      #{check_field('include_shelf_pins', 'Tạo hàng lỗ đợt', rules)}
                      #{number_field('shelf_pin_diameter_mm', 'Đường kính lỗ', rules)}
                      #{number_field('shelf_pin_depth_mm', 'Chiều sâu', rules)}
                      #{number_field('shelf_pin_pitch_mm', 'Bước hàng lỗ', rules)}
                      #{number_field('shelf_pin_bottom_margin_mm', 'Lề dưới', rules)}
                      #{number_field('shelf_pin_top_margin_mm', 'Lề trên', rules)}
                      #{number_field('shelf_pin_front_offset_mm', 'Hàng trước cách mép', rules)}
                      #{number_field('shelf_pin_rear_offset_mm', 'Hàng sau cách mép', rules)}
                    </div>
                    <div class="rule-group"><h3>Rãnh tấm hậu</h3>
                      #{check_field('include_back_grooves', 'Tạo rãnh hậu', rules)}
                      #{number_field('back_groove_width_mm', 'Rộng rãnh', rules)}
                      #{number_field('back_groove_depth_mm', 'Sâu rãnh', rules)}
                      #{number_field('back_groove_rear_offset_mm', 'Rãnh cách mép sau', rules)}
                    </div>
                  </div>
                  <div id="machiningError" class="error"></div>
                  <div class="rule-actions"><button type="submit">Cập nhật xem trước</button></div>
                </form>
              </div>
            </details>
          HTML
        end

        def export_controls(project)
          ready = project[:ready_operation_count].to_i
          invalid = project[:invalid_operation_count].to_i
          allowed = ready.positive? && invalid.zero?
          note = if invalid.positive?
                   "Cần xử lý #{invalid} nguyên công chưa hợp lệ trước khi xuất."
                 elsif ready.zero?
                   'Chưa có nguyên công sẵn sàng để xuất.'
                 else
                   'Xuất DXF theo từng mặt chi tiết và bảng nguyên công CSV.'
                 end
          disabled = allowed ? '' : ' disabled'
          <<~HTML
            <div class="header-actions"><button type="button"#{disabled} onclick="window.sketchup.exportMachiningPackage()">Xuất gói CNC</button><button class="secondary" type="button" onclick="window.sketchup.refreshMachiningPreview()">Làm mới</button><button class="secondary" type="button" onclick="window.sketchup.closeMachiningPreview()">Đóng</button></div>
            <div class="export-note">#{h(note)}</div>
          HTML
        end

        def check_field(id, label, rules)
          checked = rules[id.to_sym] ? ' checked' : ''
          "<label class=\"check\"><input id=\"#{id}\" type=\"checkbox\"#{checked}> #{h(label)}</label>"
        end

        def number_field(id, label, rules)
          "<div class=\"field\"><label for=\"#{id}\">#{h(label)} (mm)</label><input id=\"#{id}\" type=\"number\" min=\"0\" step=\"0.1\" value=\"#{n(rules[id.to_sym])}\"></div>"
        end

        def face_views(project)
          Array(project[:cabinets]).flat_map do |cabinet|
            cabinet[:panels].flat_map do |panel|
              panel[:operations].group_by { |operation| operation[:face] }.map do |face, operations|
                { panel: panel, face: face, operations: operations }
              end
            end
          end
        end

        def panel_html(panel, face, operations)
          <<~HTML
            <article class="panel-card">
              <div class="panel-head"><div><div class="name">#{h(panel[:name])}</div><div class="muted">#{h(panel[:cabinet_name])} · #{h(panel[:material_name])}</div></div><div class="dims">#{n(panel[:length_mm])} × #{n(panel[:width_mm])} × #{n(panel[:thickness_mm])} mm<br>Mặt gia công: #{h(face)}</div></div>
              <div class="preview">#{panel_svg(panel, operations)}<div class="legend"><span><i class="dot"></i>Nguyên công</span><span>Trục: X=#{h(panel[:length_axis])}, Y=#{h(panel[:width_axis])}</span></div></div>
              #{operations_table(operations)}
            </article>
          HTML
        end

        def panel_svg(panel, operations_for_face)
          length = [panel[:length_mm].to_f, 1.0].max
          width = [panel[:width_mm].to_f, 1.0].max
          padding = [length, width].max * 0.06
          view_width = length + (2 * padding)
          view_height = width + (2 * padding)
          operations = operations_for_face.map do |operation|
            operation_svg(operation, padding, width)
          end.join
          grain_y = padding + (width / 2.0)
          <<~SVG
            <svg class="panel-map" viewBox="0 0 #{n(view_width)} #{n(view_height)}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="Sơ đồ gia công #{h(panel[:name])}">
              <rect class="board" x="#{n(padding)}" y="#{n(padding)}" width="#{n(length)}" height="#{n(width)}" rx="3"/>
              <line class="grain" x1="#{n(padding + (length * 0.08))}" y1="#{n(grain_y)}" x2="#{n(padding + (length * 0.92))}" y2="#{n(grain_y)}"/>
              <circle class="origin" cx="#{n(padding)}" cy="#{n(padding + width)}" r="#{n([padding * 0.15, 3].max)}"><title>Gốc X0 Y0</title></circle>
              #{operations}
            </svg>
          SVG
        end

        def operations_table(operations)
          rows = operations.map do |operation|
            status = operation[:status] == 'ready' ? '<span class="ready">Sẵn sàng</span>' : '<span class="invalid-text">Cần kiểm tra</span>'
            size = operation[:shape] == 'groove' ? "#{n(operation[:length_mm])} × #{n(operation[:width_mm])}" : "Ø#{n(operation[:diameter_mm])}"
            "<tr><td>#{h(operation[:label])}</td><td>#{n(operation[:x_mm])}</td><td>#{n(operation[:y_mm])}</td><td>#{size}</td><td>#{n(operation[:depth_mm])}</td><td>#{status}</td></tr>"
          end.join
          "<table><thead><tr><th>Nguyên công</th><th>X (mm)</th><th>Y (mm)</th><th>Kích thước</th><th>Sâu (mm)</th><th>Trạng thái</th></tr></thead><tbody>#{rows}</tbody></table>"
        end

        def operation_svg(operation, padding, panel_width)
          css = "operation #{h(operation[:type])}"
          css += ' invalid' unless operation[:status] == 'ready'
          x = padding + operation[:x_mm].to_f
          y_top = padding + panel_width - operation[:y_mm].to_f
          if operation[:shape] == 'groove'
            y = y_top - operation[:width_mm].to_f
            title = "#{operation[:label]} · X #{n(operation[:x_mm])} · Y #{n(operation[:y_mm])} · #{n(operation[:length_mm])}×#{n(operation[:width_mm])} · sâu #{n(operation[:depth_mm])} mm"
            return "<rect class=\"#{css}\" x=\"#{n(x)}\" y=\"#{n(y)}\" width=\"#{n(operation[:length_mm])}\" height=\"#{n(operation[:width_mm])}\"><title>#{h(title)}</title></rect>"
          end

          radius = operation[:diameter_mm].to_f / 2.0
          title = "#{operation[:label]} · X #{n(operation[:x_mm])} · Y #{n(operation[:y_mm])} · Ø#{n(operation[:diameter_mm])} · sâu #{n(operation[:depth_mm])} mm"
          "<circle class=\"#{css}\" cx=\"#{n(x)}\" cy=\"#{n(y_top)}\" r=\"#{n(radius)}\"><title>#{h(title)}</title></circle>"
        end

        def operation_type_summary(counts)
          labels = {
            'hinge_cup' => 'Chén bản lề', 'dowel' => 'Chốt gỗ',
            'cam_pocket' => 'Ổ cam', 'shelf_pin' => 'Lỗ đợt',
            'back_groove' => 'Rãnh hậu'
          }
          content = labels.map do |type, label|
            "<span><strong>#{(counts || {}).to_h[type].to_i}</strong> #{h(label)}</span>"
          end.join(' · ')
          "<div class=\"notice\">#{content}</div>"
        end

        def warnings_html(warnings)
          items = Array(warnings)
          return '' if items.empty?

          "<section class=\"warnings\"><strong>Lưu ý trước khi gia công</strong><ul>#{items.map { |warning| "<li>#{h(warning)}</li>" }.join}</ul></section>"
        end

        def empty_html
          '<div class="empty">Chưa có nguyên công được hỗ trợ. Hãy bật bản lề chén trong Bước 2 hoặc chọn tủ khác.</div>'
        end

        def metric(value, label)
          "<div class=\"metric\"><strong>#{value.to_i}</strong><span>#{h(label)}</span></div>"
        end

        def n(value)
          format('%.3f', value.to_f).sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\\1')
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end

        def safe_json(value)
          JSON.generate(value).gsub('<', '\\u003c').gsub('>', '\\u003e').gsub('&', '\\u0026')
        end
      end
    end
  end
end
