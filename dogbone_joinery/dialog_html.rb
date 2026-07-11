# frozen_string_literal: true

require 'json'

# HTML UI for Dogbone Joinery. SketchUp's native inputbox gives little control
# over Vietnamese typography, so this renderer keeps the form readable.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module DialogHTML
        MORTISE_NUMERIC_FIELDS = [
          [:mortise_width_mm, 'Rộng mộng âm', 'any'],
          [:mortise_height_mm, 'Cao mộng âm', 'any'],
          [:mortise_depth_mm, 'Sâu mộng âm', 'any'],
          [:cutter_radius_mm, 'Bán kính dao', 'any']
        ].freeze

        TENON_NUMERIC_FIELDS = [
          [:tenon_width_mm, 'Rộng mộng dương', 'any'],
          [:tenon_thickness_mm, 'Độ vươn từ mặt đã chọn', 'any'],
          [:tenon_cutter_radius_mm, 'Bán kính dao', 'any'],
          [:tenon_count, 'Số lượng mộng dương', '1', nil, '1'],
          [:tenon_edge_offset_mm, 'Lề hai đầu cạnh', 'any']
        ].freeze

        module_function

        def html(face_context = {}, mode = :mortise)
          <<~HTML
            <!doctype html>
            <html lang="vi">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  :root {
                    color-scheme: light;
                    --bg: #f3f5f2;
                    --panel: #ffffff;
                    --text: #172019;
                    --muted: #5f6b62;
                    --line: #d9dfd8;
                    --accent: #226c4a;
                    --accent-strong: #18523a;
                    --accent-soft: #e8f4ed;
                    --danger: #b3261e;
                    --shadow: 0 14px 36px rgba(16, 24, 20, 0.14);
                  }

                  * {
                    box-sizing: border-box;
                  }

                  body {
                    margin: 0;
                    background: var(--bg);
                    color: var(--text);
                    font-family: "Segoe UI", "Noto Sans", "Helvetica Neue", Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.45;
                    letter-spacing: 0;
                    -webkit-font-smoothing: antialiased;
                    text-rendering: optimizeLegibility;
                  }

                  .shell {
                    max-width: 560px;
                    margin: 0 auto;
                    padding: 18px;
                  }

                  header {
                    margin-bottom: 14px;
                  }

                  .brand {
                    color: var(--accent);
                    font-size: 12px;
                    font-weight: 700;
                    text-transform: uppercase;
                  }

                  h1,
                  h2 {
                    margin: 0;
                    font-weight: 700;
                    letter-spacing: 0;
                  }

                  h1 {
                    margin-top: 4px;
                    font-size: 24px;
                  }

                  h2 {
                    font-size: 15px;
                  }

                  form {
                    display: grid;
                    gap: 12px;
                  }

                  .panel {
                    background: var(--panel);
                    border: 1px solid var(--line);
                    border-radius: 8px;
                    box-shadow: var(--shadow);
                    padding: 14px;
                  }

                  .section-title {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    margin-bottom: 12px;
                  }

                  .grid {
                    display: grid;
                    grid-template-columns: repeat(2, minmax(0, 1fr));
                    gap: 12px;
                  }

                  .field {
                    display: grid;
                    gap: 6px;
                  }

                  .field.full {
                    grid-column: 1 / -1;
                  }

                  .block-gap {
                    margin-top: 12px;
                  }

                  .compact-panel {
                    padding: 10px 14px;
                  }

                  label,
                  .label {
                    color: var(--muted);
                    font-size: 12px;
                    font-weight: 700;
                  }

                  input,
                  select,
                  button {
                    font: inherit;
                    letter-spacing: 0;
                  }

                  input[type="number"],
                  select {
                    width: 100%;
                    min-height: 38px;
                    border: 1px solid #cbd4cb;
                    border-radius: 6px;
                    background: #fff;
                    color: var(--text);
                    padding: 8px 10px;
                    outline: none;
                  }

                  input[type="number"]:focus,
                  select:focus {
                    border-color: var(--accent);
                    box-shadow: 0 0 0 3px rgba(34, 108, 74, 0.16);
                  }

                  .unit-input {
                    position: relative;
                  }

                  .unit-input input {
                    padding-right: 42px;
                  }

                  .unit {
                    position: absolute;
                    right: 10px;
                    top: 50%;
                    color: var(--muted);
                    transform: translateY(-50%);
                    pointer-events: none;
                  }

                  .segmented {
                    display: grid;
                    grid-template-columns: repeat(3, minmax(0, 1fr));
                    gap: 8px;
                  }

                  .segment input,
                  .switch input {
                    position: absolute;
                    opacity: 0;
                    pointer-events: none;
                  }

                  .segment span {
                    display: flex;
                    min-height: 40px;
                    align-items: center;
                    justify-content: center;
                    border: 1px solid #cbd4cb;
                    border-radius: 6px;
                    background: #fff;
                    color: var(--text);
                    font-weight: 700;
                    text-align: center;
                    cursor: pointer;
                  }

                  .segment input:checked + span {
                    border-color: var(--accent);
                    background: var(--accent-soft);
                    color: var(--accent-strong);
                  }

                  .switch-list {
                    display: grid;
                    gap: 8px;
                  }

                  .inline-switch span {
                    min-height: 32px;
                    padding: 6px 9px;
                    font-size: 12px;
                  }

                  .switch span {
                    display: flex;
                    min-height: 38px;
                    align-items: center;
                    gap: 10px;
                    border: 1px solid #cbd4cb;
                    border-radius: 6px;
                    background: #fff;
                    padding: 8px 10px;
                    color: var(--text);
                    font-weight: 650;
                    cursor: pointer;
                  }

                  .switch span::before {
                    width: 18px;
                    height: 18px;
                    border: 2px solid #8b978e;
                    border-radius: 5px;
                    content: "";
                    flex: 0 0 auto;
                  }

                  .switch input:checked + span {
                    border-color: var(--accent);
                    background: var(--accent-soft);
                  }

                  .switch input:checked + span::before {
                    border-color: var(--accent);
                    background:
                      linear-gradient(135deg, transparent 40%, #fff 41% 55%, transparent 56%),
                      linear-gradient(45deg, transparent 48%, #fff 49% 62%, transparent 63%),
                      var(--accent);
                  }

                  .face-measure {
                    border: 1px solid var(--line);
                    border-radius: 6px;
                    background: #f8faf8;
                    padding: 10px 12px;
                  }

                  .face-measure strong {
                    display: block;
                    font-size: 18px;
                  }

                  .face-measure.warning {
                    border-color: rgba(179, 38, 30, 0.32);
                    background: #fff8f7;
                    color: var(--danger);
                    font-weight: 700;
                  }

                  .error {
                    display: none;
                    border: 1px solid rgba(179, 38, 30, 0.32);
                    border-radius: 6px;
                    background: #fff4f3;
                    color: var(--danger);
                    padding: 10px 12px;
                    font-weight: 700;
                  }

                  .actions {
                    display: flex;
                    justify-content: flex-end;
                    gap: 10px;
                    padding-top: 2px;
                  }

                  button {
                    min-height: 38px;
                    border: 1px solid transparent;
                    border-radius: 6px;
                    padding: 8px 14px;
                    font-weight: 700;
                    cursor: pointer;
                  }

                  .secondary {
                    border-color: #cbd4cb;
                    background: #fff;
                    color: var(--text);
                  }

                  .primary {
                    background: var(--accent);
                    color: #fff;
                  }

                  .primary:hover {
                    background: var(--accent-strong);
                  }

                  @media (max-width: 440px) {
                    .shell {
                      padding: 12px;
                    }

                    .grid,
                    .segmented {
                      grid-template-columns: 1fr;
                    }

                    h1 {
                      font-size: 21px;
                    }
                  }
                </style>
              </head>
              <body>
                <main class="shell">
                  <header>
                    <div class="brand">SonVu CNC Plugins</div>
                    <h1>#{html_escape(Dialog.dialog_title(mode))}</h1>
                  </header>

                  <form id="dogbone-form">
                    <section class="panel">
                      <div class="field full">
                        <label for="preset">Cấu hình mẫu</label>
                        #{select_control(:preset, Dialog::PRESET_NAMES, Dialog::DEFAULTS[0])}
                      </div>
                    </section>

                    #{mode_sections(mode, face_context)}
                    #{mode == :mortise ? '' : clearance_section}

                    <section class="panel compact-panel">
                      <div class="switch-list">
                        #{switch_field(:add_labels, 'Thêm nhãn kích thước', false)}
                      </div>
                    </section>

                    <div id="error" class="error"></div>

                    <div class="actions">
                      <button class="secondary" type="button" id="cancel">Hủy</button>
                      <button class="primary" type="submit">Tạo mẫu</button>
                    </div>
                  </form>
                </main>

                <script>
                  const DATA = #{JSON.generate(dialog_data(face_context, mode))};
                  const form = document.getElementById('dogbone-form');
                  const errorBox = document.getElementById('error');

                  function showError(message) {
                    errorBox.textContent = message;
                    errorBox.style.display = 'block';
                  }

                  function clearError() {
                    errorBox.textContent = '';
                    errorBox.style.display = 'none';
                  }

                  function applyPreset(name) {
                    const preset = DATA.presets[name] || {};
                    DATA.mortiseNumericKeys.forEach((key) => {
                      if (form.elements[key] && Object.prototype.hasOwnProperty.call(preset, key)) {
                        form.elements[key].value = preset[key];
                      }
                    });
                    if (form.elements.tenon_thickness_mm && Object.prototype.hasOwnProperty.call(preset, 'tenon_length_mm')) {
                      form.elements.tenon_thickness_mm.value = preset.tenon_length_mm;
                    }
                  }

                  function valueFor(name) {
                    return form.elements[name] ? form.elements[name].value : DATA.defaults[name];
                  }

                  function checkedFor(name) {
                    return form.elements[name] ? form.elements[name].checked : DATA.defaults[name];
                  }

                  function updateTenonGap() {
                    const output = document.getElementById('tenon-gap-value');
                    if (!output) return;

                    const faceWidth = Number(DATA.tenonFaceWidthMM);
                    const width = Number(valueFor('tenon_width_mm')) - Number(valueFor('clearance_mm'));
                    const count = Number(valueFor('tenon_count'));
                    const margin = Number(valueFor('tenon_edge_offset_mm'));
                    if (![faceWidth, width, count, margin].every(Number.isFinite) || width <= 0 || count < 1) {
                      output.textContent = 'Không hợp lệ';
                      return;
                    }
                    if (count === 1) {
                      output.textContent = 'Một mộng — tự động căn giữa';
                      return;
                    }

                    const gap = (faceWidth - (2 * margin) - (count * width)) / (count - 1);
                    output.textContent = gap < 0 ? 'Không đủ chỗ' : `${gap.toFixed(3).replace(/\\.?0+$/, '')} mm`;
                  }

                  function payload() {
                    return {
                      preset: form.elements.preset.value,
                      mortise_width_mm: valueFor('mortise_width_mm'),
                      mortise_height_mm: valueFor('mortise_height_mm'),
                      mortise_depth_mm: valueFor('mortise_depth_mm'),
                      cutter_radius_mm: valueFor('cutter_radius_mm'),
                      clearance_mm: valueFor('clearance_mm'),
                      dogbone_style: valueFor('dogbone_style'),
                      create_mortise: checkedFor('create_mortise'),
                      cut_mortise_into_selected_solid: checkedFor('cut_mortise_into_selected_solid'),
                      tenon_width_mm: valueFor('tenon_width_mm'),
                      tenon_thickness_mm: valueFor('tenon_thickness_mm'),
                      tenon_cutter_radius_mm: valueFor('tenon_cutter_radius_mm'),
                      tenon_count: valueFor('tenon_count'),
                      tenon_edge_offset_mm: valueFor('tenon_edge_offset_mm'),
                      create_tenon: checkedFor('create_tenon'),
                      tenon_relief_enabled: checkedFor('tenon_relief_enabled'),
                      add_labels: checkedFor('add_labels')
                    };
                  }

                  form.elements.preset.addEventListener('change', (event) => {
                    clearError();
                    applyPreset(event.target.value);
                    updateTenonGap();
                  });

                  form.addEventListener('input', () => {
                    clearError();
                    updateTenonGap();
                  });
                  updateTenonGap();

                  form.addEventListener('submit', (event) => {
                    event.preventDefault();
                    clearError();
                    window.sketchup.submitForm(JSON.stringify(payload()));
                  });

                  document.getElementById('cancel').addEventListener('click', () => {
                    window.sketchup.cancelForm();
                  });
                </script>
              </body>
            </html>
          HTML
        end

        def dialog_data(face_context, mode)
          {
            presets: CNCPlugins::DOGBONE_PRESETS,
            mortiseNumericKeys: MORTISE_NUMERIC_FIELDS.map { |field| field[0].to_s },
            selectedSideFace: face_context[:side_face] == true,
            tenonFaceWidthMM: face_context[:width_mm],
            tenonFaceHeightMM: face_context[:height_mm],
            defaults: defaults_for_payload(mode)
          }
        end

        def defaults_for_payload(mode)
          {
            mortise_width_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:mortise_width_mm),
            mortise_height_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:mortise_height_mm),
            mortise_depth_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:mortise_depth_mm),
            cutter_radius_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:cutter_radius_mm),
            clearance_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:clearance_mm),
            dogbone_style: Dialog::DEFAULT_DOGBONE_STYLE,
            create_mortise: mode != :tenon,
            cut_mortise_into_selected_solid: false,
            tenon_width_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:tenon_width_mm),
            tenon_thickness_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:tenon_thickness_mm),
            tenon_cutter_radius_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:tenon_cutter_radius_mm),
            tenon_count: Dialog::NUMERIC_DEFAULTS_MM.fetch(:tenon_count),
            tenon_edge_offset_mm: Dialog::NUMERIC_DEFAULTS_MM.fetch(:tenon_edge_offset_mm),
            create_tenon: mode == :tenon,
            tenon_relief_enabled: true,
            add_labels: false
          }
        end

        def mode_sections(mode, face_context)
          case mode
          when :mortise
            mortise_section(face_context)
          when :tenon
            tenon_section(face_context)
          else
            mortise_section(face_context)
          end
        end

        def clearance_section
          <<~HTML
            <section class="panel compact-panel">
              <div class="grid">
                #{numeric_field(:clearance_mm, 'Độ hở lắp ráp tổng', 'any')}
              </div>
              <div class="helper-text">Độ hở được trừ một lần khỏi tổng chiều rộng và tổng chiều cao mộng dương.</div>
            </section>
          HTML
        end

        def mortise_section(face_context)
          <<~HTML
            <section class="panel">
              <div class="section-title">
                <h2>Tạo mộng âm</h2>
                #{hidden_checked(:create_mortise, true)}
              </div>
              #{mortise_face_panel(face_context)}
              <div class="grid">
                #{MORTISE_NUMERIC_FIELDS.map { |field| numeric_field(*field) }.join}
              </div>
              <div class="helper-text block-gap">
                Sau khi xác nhận, di chuyển bản xem trước trên mặt đã chọn và bấm để đặt tâm mộng âm.
              </div>
              <div class="field full block-gap">
                <div class="label">Kiểu khoét góc mộng âm</div>
                <div class="segmented">
                  #{Dialog::DOGBONE_STYLES.map { |style| segment_field(style) }.join}
                </div>
              </div>
            </section>
          HTML
        end

        def mortise_face_panel(face_context)
          if face_context[:selected]
            <<~HTML
              <div class="face-measure">
                <span class="label">Mặt đã chọn (rộng × cao × sâu model)</span>
                <strong>#{html_escape(face_context[:width_label])} × #{html_escape(face_context[:height_label])} × #{html_escape(face_context[:depth_label])}</strong>
              </div>
            HTML
          else
            <<~HTML
              <div class="face-measure warning">
                Chưa chọn mặt. Hãy chọn một mặt của model để định vị và kiểm tra chiều sâu mộng âm.
              </div>
            HTML
          end
        end

        def tenon_section(face_context)
          <<~HTML
            <section class="panel">
              <div class="section-title">
                <h2>Tạo mộng dương</h2>
                #{hidden_checked(:create_tenon, true)}
              </div>
              #{face_height_panel(face_context)}
              <div class="grid block-gap">
                #{TENON_NUMERIC_FIELDS.map { |field| numeric_field(*field) }.join}
              </div>
              <div class="face-measure block-gap">
                <span class="label">Khoảng cách trống tự động giữa các mộng</span>
                <strong id="tenon-gap-value">—</strong>
              </div>
              <div class="face-measure warning block-gap">
                Mộng dương sẽ được hợp khối với group/component solid chứa mặt đã chọn để tạo một chi tiết CNC duy nhất.
              </div>
              <div class="switch-list block-gap">
                #{switch_field(:tenon_relief_enabled, 'Khoét bán nguyệt hai đầu mộng dương', true)}
              </div>
            </section>
          HTML
        end

        def numeric_field(key, label, step, unit = 'mm', min = '0')
          default_value = numeric_default_value(key)
          unit_html = unit ? %(<span class="unit">#{html_escape(unit)}</span>) : ''
          <<~HTML
            <div class="field">
              <label for="#{html_escape(key)}">#{html_escape(label)}</label>
              <div class="unit-input">
                <input id="#{html_escape(key)}" name="#{html_escape(key)}" type="number" min="#{html_escape(min)}" step="#{html_escape(step)}" value="#{html_escape(default_value)}" inputmode="decimal">
                #{unit_html}
              </div>
            </div>
          HTML
        end

        def numeric_default_value(key)
          Dialog::NUMERIC_DEFAULTS_MM.fetch(key)
        end

        def segment_field(style)
          checked = style == Dialog::DEFAULT_DOGBONE_STYLE ? ' checked' : ''
          <<~HTML
            <label class="segment">
              <input type="radio" name="dogbone_style" value="#{html_escape(style)}"#{checked}>
              <span>#{html_escape(style)}</span>
            </label>
          HTML
        end

        def face_height_panel(face_context)
          if face_context[:side_face]
            <<~HTML
              <div class="face-measure">
                <span class="label">Kích thước mặt đã chọn (rộng × cao)</span>
                <strong>#{html_escape(face_context[:width_label])} × #{html_escape(face_context[:height_label])}</strong>
              </div>
            HTML
          elsif face_context[:selected]
            <<~HTML
              <div class="face-measure warning">
                Không đọc được hệ trục hoặc kích thước của mặt đã chọn. Hãy chọn một mặt phẳng hợp lệ.
              </div>
            HTML
          else
            <<~HTML
              <div class="face-measure warning">
                Chưa chọn mặt. Mộng dương cần một mặt phẳng để xác định chiều rộng, chiều cao và hướng vươn.
              </div>
            HTML
          end
        end

        def hidden_checked(key, checked_by_default)
          checked = checked_by_default ? ' checked' : ''
          %(<input type="checkbox" name="#{html_escape(key)}"#{checked} hidden>)
        end

        def switch_field(key, label, checked_by_default)
          checked = checked_by_default ? ' checked' : ''
          <<~HTML
            <label class="switch">
              <input type="checkbox" name="#{html_escape(key)}"#{checked}>
              <span>#{html_escape(label)}</span>
            </label>
          HTML
        end

        def select_control(name, options, selected)
          option_html = options.map do |option|
            selected_attr = option == selected ? ' selected' : ''
            %(<option value="#{html_escape(option)}"#{selected_attr}>#{html_escape(option)}</option>)
          end.join
          %(<select id="#{html_escape(name)}" name="#{html_escape(name)}">#{option_html}</select>)
        end

        def html_escape(value)
          value.to_s
               .gsub('&', '&amp;')
               .gsub('<', '&lt;')
               .gsub('>', '&gt;')
               .gsub('"', '&quot;')
               .gsub("'", '&#39;')
        end
      end
    end
  end
end
