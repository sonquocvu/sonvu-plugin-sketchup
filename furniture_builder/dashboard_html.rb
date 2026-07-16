# frozen_string_literal: true

require 'cgi'

# Unified Vietnamese Furniture Builder home screen for Phases 1–5.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DashboardHTML
        module_function

        def html(state)
          actions = state[:actions] || {}
          license = state[:license] || {}
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root { color-scheme:light; --bg:#eef2ef; --panel:#fff; --text:#172019; --muted:#68716a; --line:#d7ded8; --accent:#226c4a; --accent-dark:#174f37; --soft:#e8f4ed; --warn:#805d13; --danger:#a92f27; }
                  * { box-sizing:border-box; }
                  body { margin:0; background:var(--bg); color:var(--text); font:13px/1.45 "Segoe UI","Noto Sans",Arial,sans-serif; }
                  .shell { max-width:1000px; margin:auto; padding:18px; }
                  header { display:grid; grid-template-columns:1fr auto; gap:16px; align-items:start; margin-bottom:12px; }
                  .brand { color:var(--accent); font-size:11px; font-weight:850; text-transform:uppercase; letter-spacing:.04em; }
                  h1 { margin:2px 0 4px; font-size:25px; }
                  .scope,.muted { color:var(--muted); }
                  .header-actions { display:flex; gap:7px; }
                  .license { display:flex; justify-content:space-between; gap:14px; align-items:center; padding:10px 12px; margin-bottom:12px; border:1px solid #{license[:licensed] ? '#bcd7c6' : '#e1b8b4'}; border-radius:8px; background:#{license[:licensed] ? '#edf8f1' : '#fff2f1'}; }
                  .license strong { display:block; color:#{license[:licensed] ? 'var(--accent)' : 'var(--danger)'}; }
                  .summary { display:grid; grid-template-columns:repeat(4,minmax(110px,1fr)); gap:9px; margin-bottom:12px; }
                  .metric { padding:10px 12px; border:1px solid var(--line); border-radius:8px; background:var(--panel); }
                  .metric strong { display:block; color:var(--accent); font-size:19px; }
                  .metric span { color:var(--muted); font-size:10px; }
                  .selection { margin-bottom:12px; padding:9px 11px; border:1px solid #cfe0d5; border-radius:7px; background:#f7fbf8; color:#405149; }
                  .workflow { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:11px; }
                  .step { display:grid; grid-template-columns:45px 1fr; gap:11px; min-height:150px; padding:14px; border:1px solid var(--line); border-radius:9px; background:var(--panel); }
                  .step-number { display:flex; width:40px; height:40px; align-items:center; justify-content:center; border-radius:50%; background:var(--soft); color:var(--accent); font-size:17px; font-weight:850; }
                  .step.future { opacity:.7; background:#f6f7f6; }
                  .step.future .step-number { background:#e5e8e6; color:#69736c; }
                  .step-label { color:var(--muted); font-size:10px; font-weight:800; text-transform:uppercase; }
                  h2 { margin:1px 0 5px; font-size:16px; }
                  .description { min-height:38px; color:var(--muted); font-size:11px; }
                  .actions { display:flex; flex-wrap:wrap; gap:7px; margin-top:11px; }
                  button { min-height:35px; border:1px solid var(--accent); border-radius:6px; background:var(--accent); color:#fff; padding:7px 12px; font:inherit; font-weight:750; cursor:pointer; }
                  button:hover:not(:disabled) { background:var(--accent-dark); }
                  button.secondary { border-color:#c7d0ca; background:#fff; color:var(--text); }
                  button.secondary:hover:not(:disabled) { background:#f5f8f6; }
                  button:disabled { opacity:.42; cursor:not-allowed; }
                  .error { display:none; margin:12px 0; padding:10px; border:1px solid #e2b6b2; border-radius:7px; background:#fff3f2; color:var(--danger); font-weight:700; }
                  footer { display:flex; justify-content:space-between; gap:12px; margin-top:12px; color:var(--muted); font-size:10px; }
                  @media (max-width:720px) { .workflow { grid-template-columns:1fr; } header { grid-template-columns:1fr; } .summary { grid-template-columns:repeat(2,1fr); } }
                </style>
              </head>
              <body>
                <main class="shell">
                  <header><div><div class="brand">SonVu CNC Plugins</div><h1>Trung tâm nội thất SonVu</h1><div class="scope">Phạm vi: #{h(state[:scope])}</div></div><div class="header-actions"><button class="secondary" type="button" onclick="window.sketchup.refreshFurnitureDashboard()">Làm mới</button><button class="secondary" type="button" onclick="window.sketchup.closeFurnitureDashboard()">Đóng</button></div></header>
                  #{license_html(license)}
                  <section class="summary">#{metric(state[:cabinet_count], 'Tủ nội thất')}#{metric(state[:board_count], 'Chi tiết ván')}#{metric(state[:hardware_count], 'Phụ kiện')}#{metric(state[:part_count], 'Tổng chi tiết')}</section>
                  <div class="selection">#{h(state[:selection_message])}#{state[:warning_count].to_i.positive? ? " · #{state[:warning_count].to_i} cảnh báo dữ liệu" : ''}</div>
                  <div id="dashboardError" class="error"></div>
                  <section class="workflow">
                    #{step_one(actions)}
                    #{step_two(actions)}
                    #{step_three(actions)}
                    #{step_four(actions)}
                    #{step_five(actions)}
                  </section>
                  <footer><span>Các lệnh cũ vẫn có trong menu Thiết kế nội thất.</span><span>Phiên bản #{h(state[:version])}</span></footer>
                </main>
                <script>
                  function showDashboardError(message) {
                    const box = document.getElementById('dashboardError');
                    box.textContent = message;
                    box.style.display = 'block';
                  }
                </script>
              </body>
            </html>
          HTML
        end

        def license_html(license)
          title = license[:licensed] ? 'Giấy phép sẵn sàng' : 'Tính năng đang bị khóa'
          details = [license[:message], license[:customer], license[:expires_at]].map(&:to_s).reject(&:empty?).join(' · ')
          "<section class=\"license\"><div><strong>#{h(title)}</strong><span>#{h(details)}</span></div><button class=\"secondary\" type=\"button\" onclick=\"window.sketchup.openDashboardLicense()\">Quản lý giấy phép</button></section>"
        end

        def step_one(actions)
          step(
            1, 'Thiết kế thùng tủ',
            'Chọn mẫu, nhập kích thước, khoang, đợt, chân tủ, vật liệu và chiều vân.',
            action_button('Tạo tủ mới', 'dashboardCreateFurniture', actions[:create]) +
              action_button('Sửa thùng tủ đã chọn', 'dashboardEditCarcass', actions[:edit_carcass], secondary: true)
          )
        end

        def step_two(actions)
          step(
            2, 'Mặt cánh, ngăn kéo và phụ kiện',
            'Cấu hình cánh, mặt ngăn kéo, hộp kéo, tay nắm, bản lề và ray.',
            action_button('Cấu hình tủ đã chọn', 'dashboardEditFittings', actions[:edit_fittings])
          )
        end

        def step_three(actions)
          step(
            3, 'Danh sách sản xuất và báo giá',
            'Thống kê ván/phụ kiện, xuất CSV và tính chi phí theo tủ hoặc toàn công trình.',
            action_button('Danh sách chi tiết', 'dashboardOpenCutList', actions[:cut_list]) +
              action_button('Dự toán chi phí', 'dashboardOpenCostEstimate', actions[:cost_estimate], secondary: true)
          )
        end

        def step_four(actions)
          step(
            4, 'Tối ưu và xuất phương án cắt',
            'Xếp chi tiết theo vật liệu/độ dày, xem sơ đồ tấm và xuất HTML cùng CSV tọa độ.',
            action_button('Tối ưu cắt ván', 'dashboardOpenSheetOptimization', actions[:sheet_optimization])
          )
        end

        def step_five(actions)
          step(
            5, 'Gia công CNC',
            'Kiểm tra mặt gia công, tọa độ và chiều sâu khoan trước khi xuất cho máy CNC.',
            action_button('Xem trước gia công', 'dashboardOpenMachiningPreview', actions[:phase_five])
          )
        end

        def step(number, title, description, buttons, future: false)
          "<article class=\"step#{future ? ' future' : ''}\"><div class=\"step-number\">#{number}</div><div><div class=\"step-label\">Bước #{number}</div><h2>#{h(title)}</h2><div class=\"description\">#{h(description)}</div><div class=\"actions\">#{buttons}</div></div></article>"
        end

        def action_button(label, callback, enabled, secondary: false)
          classes = secondary ? ' class="secondary"' : ''
          disabled = enabled ? '' : ' disabled'
          "<button#{classes} type=\"button\"#{disabled} onclick=\"window.sketchup.#{callback}()\">#{h(label)}</button>"
        end

        def metric(value, label)
          "<div class=\"metric\"><strong>#{value.to_i}</strong><span>#{h(label)}</span></div>"
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
