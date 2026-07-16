# frozen_string_literal: true

require 'cgi'

# Vietnamese Phase 3C pricing form and calculated quotation preview.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CostEstimateDialogHTML
        module_function

        def html(report, catalog, estimate = nil)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root { color-scheme:light; --bg:#f2f4f2; --panel:#fff; --text:#172019; --muted:#68716a; --line:#d9dedb; --accent:#226c4a; --danger:#ad2e24; }
                  * { box-sizing:border-box; }
                  body { margin:0; background:var(--bg); color:var(--text); font:13px/1.45 "Segoe UI",Arial,sans-serif; }
                  .shell { padding:18px; min-width:780px; }
                  .brand { color:var(--accent); font-size:11px; font-weight:800; text-transform:uppercase; }
                  h1 { margin:2px 0 4px; font-size:23px; }
                  h2 { margin:0 0 12px; font-size:15px; }
                  .scope,.note { color:var(--muted); }
                  .panel { margin:12px 0; padding:14px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }
                  .field { display:grid; gap:5px; }
                  label { color:var(--muted); font-size:11px; font-weight:750; }
                  input { width:100%; min-height:36px; border:1px solid #c8d0ca; border-radius:6px; padding:7px 9px; font:inherit; }
                  .price-list { display:grid; grid-template-columns:minmax(180px,1fr) 180px; gap:8px 12px; align-items:center; }
                  .price-list .label { overflow-wrap:anywhere; }
                  .unit-input { position:relative; }
                  .unit-input input { padding-right:62px; text-align:right; }
                  .unit { position:absolute; right:9px; top:50%; transform:translateY(-50%); color:var(--muted); font-size:11px; }
                  .summary { display:grid; grid-template-columns:repeat(4,minmax(130px,1fr)); gap:9px; margin:12px 0; }
                  .card { padding:11px 12px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }
                  .card strong { display:block; color:var(--accent); font-size:18px; }
                  .card span { color:var(--muted); font-size:11px; }
                  .table-wrap { overflow:auto; max-height:260px; border:1px solid var(--line); border-radius:7px; }
                  table { width:100%; border-collapse:collapse; white-space:nowrap; background:#fff; }
                  th,td { padding:7px 9px; border-bottom:1px solid #edf0ee; text-align:left; }
                  th { position:sticky; top:0; background:#f7f9f7; color:#4f5d53; font-size:11px; }
                  .num { text-align:right; }
                  .error { display:none; margin:12px 0; padding:10px; border:1px solid #e2b6b2; border-radius:7px; background:#fff3f2; color:var(--danger); font-weight:700; }
                  .actions { display:flex; justify-content:flex-end; gap:8px; margin-top:12px; }
                  button { min-height:38px; border:1px solid var(--accent); border-radius:6px; background:var(--accent); color:#fff; padding:8px 15px; font:inherit; font-weight:750; cursor:pointer; }
                  button.secondary { border-color:#c8d0ca; background:#fff; color:var(--text); }
                  button:disabled { opacity:.45; cursor:not-allowed; }
                </style>
              </head>
              <body>
                <main class="shell">
                  <div class="brand">SonVu Furniture Builder — Bước 3</div>
                  <h1>Dự toán chi phí</h1>
                  <div class="scope">Phạm vi: #{h(report[:scope])} · #{report[:cabinet_count].to_i} tủ</div>
                  <form id="costForm">
                    <section class="panel">
                      <h2>Thông số chung</h2>
                      <div class="grid">
                        #{number_input('waste_percent', 'Tỷ lệ hao hụt vật liệu', catalog[:waste_percent], '%')}
                        #{number_input('edge_band_price_per_m', 'Đơn giá dán cạnh', catalog[:edge_band_price_per_m], 'VND/m')}
                      </div>
                    </section>
                    <section class="panel">
                      <h2>Đơn giá vật liệu</h2>
                      <div class="price-list">#{price_inputs(catalog[:material_prices], 'material-price', 'VND/m²')}</div>
                    </section>
                    <section class="panel">
                      <h2>Đơn giá phụ kiện</h2>
                      <div class="price-list">#{price_inputs(catalog[:hardware_prices], 'hardware-price', 'VND/cái')}</div>
                    </section>
                    <div id="error" class="error"></div>
                    #{estimate_html(estimate)}
                    <div class="note">Đơn giá được lưu trên máy này sau khi tính. Hao hụt chỉ áp dụng cho diện tích vật liệu; dán cạnh và phụ kiện tính theo số lượng thực tế.</div>
                    <div class="actions">
                      <button class="secondary" type="button" onclick="window.sketchup.closeCostEstimate()">Đóng</button>
                      <button type="submit">Tính lại</button>
                      <button type="button" #{estimate ? '' : 'disabled'} onclick="window.sketchup.exportCostEstimate()">Xuất báo giá CSV</button>
                    </div>
                  </form>
                </main>
                <script>
                  document.getElementById('costForm').addEventListener('submit', (event) => {
                    event.preventDefault();
                    const payload = {
                      waste_percent: document.getElementById('waste_percent').value,
                      edge_band_price_per_m: document.getElementById('edge_band_price_per_m').value,
                      material_prices: {},
                      hardware_prices: {}
                    };
                    document.querySelectorAll('.material-price').forEach((input) => {
                      payload.material_prices[input.dataset.priceKey] = input.value;
                    });
                    document.querySelectorAll('.hardware-price').forEach((input) => {
                      payload.hardware_prices[input.dataset.priceKey] = input.value;
                    });
                    window.sketchup.calculateCost(JSON.stringify(payload));
                  });
                  function showCostError(message) {
                    const box = document.getElementById('error');
                    box.textContent = message;
                    box.style.display = 'block';
                  }
                </script>
              </body>
            </html>
          HTML
        end

        def number_input(id, label, value, unit)
          <<~HTML
            <div class="field"><label for="#{id}">#{h(label)}</label><div class="unit-input"><input id="#{id}" type="number" min="0" step="0.01" value="#{h(value)}"><span class="unit">#{h(unit)}</span></div></div>
          HTML
        end

        def price_inputs(prices, css_class, unit)
          return '<div class="note">Không có dữ liệu.</div>' if prices.empty?

          prices.sort_by { |name, _price| name }.map do |name, price|
            "<div class=\"label\">#{h(name)}</div><div class=\"unit-input\"><input class=\"#{css_class}\" data-price-key=\"#{h(name)}\" type=\"number\" min=\"0\" step=\"1\" value=\"#{h(price)}\"><span class=\"unit\">#{h(unit)}</span></div>"
          end.join
        end

        def estimate_html(estimate)
          return '' unless estimate

          <<~HTML
            <section class="summary">
              #{summary_card(estimate[:material_subtotal], 'Vật liệu')}
              #{summary_card(estimate[:edge_subtotal], 'Dán cạnh')}
              #{summary_card(estimate[:hardware_subtotal], 'Phụ kiện')}
              #{summary_card(estimate[:project_total], 'Tổng cộng')}
            </section>
            <section class="panel"><h2>Chi tiết dự toán ván</h2>#{board_table(estimate[:board_rows])}</section>
            <section class="panel"><h2>Chi tiết phụ kiện</h2>#{hardware_table(estimate[:hardware_rows])}</section>
            <section class="panel"><h2>Tổng theo tủ</h2>#{cabinet_table(estimate[:cabinet_totals])}</section>
          HTML
        end

        def summary_card(value, label)
          "<div class=\"card\"><strong>#{money(value)}</strong><span>#{h(label)}</span></div>"
        end

        def board_table(rows)
          body = rows.map do |row|
            "<tr><td>#{h(row[:name])}</td><td class=\"num\">#{row[:quantity]}</td><td class=\"num\">#{decimal(row[:billable_area_m2])}</td><td class=\"num\">#{money(row[:material_cost])}</td><td class=\"num\">#{decimal(row[:edge_length_m])}</td><td class=\"num\">#{money(row[:edge_cost])}</td><td class=\"num\">#{money(row[:total_cost])}</td></tr>"
          end.join
          table(%w[Chi_tiết SL m² Tiền_vật_liệu Mét_cạnh Tiền_cạnh Thành_tiền], body)
        end

        def hardware_table(rows)
          body = rows.map do |row|
            "<tr><td>#{h(row[:name])}</td><td class=\"num\">#{row[:quantity]}</td><td class=\"num\">#{money(row[:unit_price])}</td><td class=\"num\">#{money(row[:total_cost])}</td></tr>"
          end.join
          table(%w[Phụ_kiện SL Đơn_giá Thành_tiền], body)
        end

        def cabinet_table(rows)
          body = rows.map do |row|
            "<tr><td>#{h(row[:cabinet_name])}</td><td>#{h(row[:cabinet_id])}</td><td class=\"num\">#{money(row[:total_cost])}</td></tr>"
          end.join
          table(%w[Tên_tủ Mã_tủ Thành_tiền], body)
        end

        def table(headers, body)
          labels = headers.map { |header| "<th>#{h(header.tr('_', ' '))}</th>" }.join
          "<div class=\"table-wrap\"><table><thead><tr>#{labels}</tr></thead><tbody>#{body}</tbody></table></div>"
        end

        def money(value)
          digits = value.to_f.round.to_i.to_s
          "#{digits.reverse.scan(/.{1,3}/).join('.').reverse} ₫"
        end

        def decimal(value)
          format('%.3f', value.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
