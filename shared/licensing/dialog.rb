# frozen_string_literal: true

require 'json'

module SonVu
  module CNCPlugins
    module Licensing
      module Dialog
        module_function

        def show(required_feature: nil, notice: nil)
          return show_inputbox(required_feature) unless defined?(::UI::HtmlDialog)

          if @dialog && @dialog.respond_to?(:visible?) && @dialog.visible?
            @dialog.bring_to_front if @dialog.respond_to?(:bring_to_front)
            return @dialog
          end

          dialog = create_dialog
          @dialog = dialog
          dialog.add_action_callback('activateLicense') do |_context, value|
            handle_action(dialog, required_feature) { Manager.activate(value) }
          end
          dialog.add_action_callback('refreshLicense') do
            handle_action(dialog, required_feature) { Manager.refresh(required_feature) }
          end
          dialog.add_action_callback('deactivateLicense') do
            handle_action(dialog, required_feature) { Manager.deactivate }
          end
          dialog.add_action_callback('closeLicenseDialog') do
            @dialog = nil
            dialog.close
          end
          dialog.set_on_closed { @dialog = nil } if dialog.respond_to?(:set_on_closed)
          dialog.set_html(html(Manager.view_model(required_feature, notice: notice)))
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        end

        def show_inputbox(required_feature)
          view = Manager.view_model(required_feature)
          CNCPlugins::UIHelpers.message(status_message(view))
          input = UI.inputbox(
            ['Mã giấy phép hoặc token đã ký'],
            [''],
            'SonVu CNC Plugins - Giấy phép'
          )
          return nil unless input

          Manager.activate(input.first)
          CNCPlugins::UIHelpers.message('Kích hoạt giấy phép thành công.')
        rescue LicenseClient::Error => e
          CNCPlugins::UIHelpers.message("Không kích hoạt được giấy phép:\n#{e.message}")
          nil
        end

        def create_dialog
          options = {
            dialog_title: 'SonVu CNC Plugins - Quản lý giấy phép',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.licensing",
            scrollable: true,
            resizable: true,
            width: 560,
            height: 650
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          ::UI::HtmlDialog.new(options)
        end

        def handle_action(dialog, required_feature)
          yield
          update_dialog(dialog, Manager.view_model(required_feature))
        rescue LicenseClient::Error => e
          update_dialog(dialog, Manager.view_model(required_feature, notice: e.message))
        rescue StandardError => e
          update_dialog(dialog, Manager.view_model(required_feature, notice: "Lỗi giấy phép: #{e.message}"))
        end

        def update_dialog(dialog, view)
          dialog.execute_script("renderStatus(#{safe_json(view)});")
        end

        def safe_json(value)
          JSON.generate(value).gsub('</', '<\\/')
        end

        def status_message(view)
          [view[:message], "Mã thiết bị: #{view[:device_id]}"].join("\n")
        end

        def html(view)
          data = safe_json(view)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>Quản lý giấy phép</title>
                <style>
                  :root { color-scheme: light; font-family: "Segoe UI", Arial, sans-serif; --green:#176b3a; --pale:#eef7f0; --line:#d5ded7; --red:#a52a24; --text:#243027; }
                  * { box-sizing:border-box; }
                  body { margin:0; background:#f5f7f5; color:var(--text); }
                  main { max-width:680px; margin:auto; padding:22px; }
                  header { margin-bottom:16px; }
                  .brand { color:var(--green); font-weight:800; letter-spacing:.04em; text-transform:uppercase; font-size:12px; }
                  h1 { margin:5px 0 0; font-size:25px; }
                  .card { background:#fff; border:1px solid var(--line); border-radius:9px; padding:16px; margin-bottom:13px; }
                  .status { border-left:5px solid var(--red); }
                  .status.ok { border-left-color:var(--green); background:var(--pale); }
                  .status.setup { border-left-color:#b27800; background:#fff8e7; }
                  .state { font-size:18px; font-weight:800; margin-bottom:5px; }
                  .message { line-height:1.45; }
                  dl { display:grid; grid-template-columns:125px 1fr; gap:8px 12px; margin:12px 0 0; }
                  dt { color:#607066; font-weight:700; }
                  dd { margin:0; overflow-wrap:anywhere; }
                  label { display:block; font-weight:750; margin-bottom:7px; }
                  textarea { width:100%; min-height:88px; resize:vertical; border:1px solid #aebbb1; border-radius:6px; padding:10px; font:13px Consolas, monospace; }
                  .hint { margin:7px 0 0; color:#647269; font-size:12px; line-height:1.4; }
                  .actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }
                  button { border:1px solid #b9c5bb; border-radius:6px; background:#fff; padding:9px 13px; font-weight:750; cursor:pointer; }
                  button.primary { border-color:var(--green); background:var(--green); color:#fff; }
                  button.danger { color:var(--red); }
                  button:disabled { opacity:.45; cursor:default; }
                  .device-row { display:flex; align-items:center; gap:8px; }
                  .device { flex:1; user-select:all; overflow-wrap:anywhere; font:12px Consolas, monospace; }
                </style>
              </head>
              <body>
                <main>
                  <header><div class="brand">SonVu CNC Plugins</div><h1>Quản lý giấy phép</h1></header>
                  <section id="status" class="card status">
                    <div id="state" class="state"></div>
                    <div id="message" class="message"></div>
                    <dl id="details">
                      <dt>Khách hàng</dt><dd id="customer">—</dd>
                      <dt>Mã giấy phép</dt><dd id="license-id">—</dd>
                      <dt>Loại</dt><dd id="license-type">—</dd>
                      <dt>Có hiệu lực đến</dt><dd id="expires-at">—</dd>
                    </dl>
                  </section>
                  <section class="card">
                    <label>Mã thiết bị</label>
                    <div class="device-row">
                      <div id="device-id" class="device"></div>
                      <button id="copy-device" type="button">Sao chép</button>
                    </div>
                    <p class="hint">Gửi mã này cho SonVu nếu bạn cần cấp token thủ công hoặc chuyển giấy phép sang máy mới.</p>
                  </section>
                  <section class="card">
                    <label for="license-value">Mã giấy phép hoặc token đã ký</label>
                    <textarea id="license-value" spellcheck="false" placeholder="Nhập mã giấy phép để kích hoạt online, hoặc dán token đã ký..."></textarea>
                    <div class="actions">
                      <button id="activate" class="primary" type="button">Kích hoạt</button>
                      <button id="refresh" type="button">Làm mới</button>
                      <button id="deactivate" class="danger" type="button">Hủy kích hoạt</button>
                      <button id="close" type="button">Đóng</button>
                    </div>
                    <p id="server-hint" class="hint"></p>
                  </section>
                </main>
                <script>
                  function text(id, value) { document.getElementById(id).textContent = value || '—'; }
                  function renderStatus(data) {
                    const status = document.getElementById('status');
                    status.className = `card status ${data.licensed ? 'ok' : ''} ${(data.state === 'setup' || data.state === 'trial') ? 'setup' : ''}`;
                    const activeState = data.state === 'setup' ? 'Chế độ phát triển' : (data.state === 'trial' ? 'Dùng thử 14 ngày' : 'Đã kích hoạt');
                    text('state', data.licensed ? activeState : (data.state === 'trial_expired' ? 'Đã hết hạn dùng thử' : 'Chưa kích hoạt'));
                    text('message', data.message);
                    text('customer', data.customer);
                    text('license-id', data.license_id);
                    text('license-type', data.license_type);
                    text('expires-at', data.expires_at);
                    text('device-id', data.device_id);
                    document.getElementById('refresh').disabled = !data.server_configured;
                    document.getElementById('deactivate').disabled = data.state === 'missing' || data.state === 'setup' || data.state === 'trial' || data.state === 'trial_expired';
                    text('server-hint', data.server_configured ? 'Máy chủ kích hoạt online đã sẵn sàng.' : 'Chưa cấu hình máy chủ online; vẫn có thể nhập token đã ký thủ công sau khi cấu hình khóa công khai.');
                  }
                  document.getElementById('activate').addEventListener('click', () => window.sketchup.activateLicense(document.getElementById('license-value').value));
                  document.getElementById('copy-device').addEventListener('click', () => {
                    const value = document.getElementById('device-id').textContent;
                    const temporary = document.createElement('textarea');
                    temporary.value = value;
                    temporary.style.position = 'fixed';
                    temporary.style.opacity = '0';
                    document.body.appendChild(temporary);
                    temporary.select();
                    document.execCommand('copy');
                    temporary.remove();
                    document.getElementById('copy-device').textContent = 'Đã sao chép';
                  });
                  document.getElementById('refresh').addEventListener('click', () => window.sketchup.refreshLicense());
                  document.getElementById('deactivate').addEventListener('click', () => window.sketchup.deactivateLicense());
                  document.getElementById('close').addEventListener('click', () => window.sketchup.closeLicenseDialog());
                  renderStatus(#{data});
                </script>
              </body>
            </html>
          HTML
        end
      end
    end
  end
end
