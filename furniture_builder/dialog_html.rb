# frozen_string_literal: true

require 'json'

# Vietnamese HtmlDialog for creating and editing furniture, fronts, drawers,
# and Phase 2C hardware templates.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DialogHTML
        module_function

        def html(initial_values, mode)
          presets_json = safe_json(Presets::ITEMS)
          initial_json = safe_json(initial_values)
          edit_mode = mode == :edit
          action_label = edit_mode ? 'Cập nhật tủ' : 'Tạo và đặt tủ'
          title = edit_mode ? 'Chỉnh sửa tủ nội thất' : 'Tạo tủ nội thất'

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
                    --muted: #667168;
                    --line: #d7ded8;
                    --accent: #226c4a;
                    --accent-dark: #18523a;
                    --accent-soft: #e8f4ed;
                    --danger: #b3261e;
                  }
                  * { box-sizing: border-box; }
                  body {
                    margin: 0;
                    background: var(--bg);
                    color: var(--text);
                    font-family: "Segoe UI", "Noto Sans", Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.45;
                  }
                  .shell { max-width: 660px; margin: 0 auto; padding: 18px; }
                  header { margin-bottom: 14px; }
                  .brand { color: var(--accent); font-size: 12px; font-weight: 800; text-transform: uppercase; }
                  h1 { margin: 3px 0 0; font-size: 24px; }
                  h2 { margin: 0 0 12px; font-size: 15px; }
                  form { display: grid; gap: 12px; }
                  .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 9px; padding: 14px; }
                  .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
                  .field { display: grid; gap: 6px; }
                  .full { grid-column: 1 / -1; }
                  label, .label { color: var(--muted); font-size: 12px; font-weight: 750; }
                  input, select, button { font: inherit; }
                  input[type="text"], input[type="number"], select {
                    width: 100%; min-height: 38px; border: 1px solid #c6d0c8; border-radius: 6px;
                    background: #fff; color: var(--text); padding: 8px 10px; outline: none;
                  }
                  input:focus, select:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(34, 108, 74, .15); }
                  .unit-wrap { position: relative; }
                  .unit-wrap input { padding-right: 42px; }
                  .unit { position: absolute; right: 10px; top: 50%; transform: translateY(-50%); color: var(--muted); }
                  .checks { display: grid; gap: 9px; }
                  .check { display: flex; align-items: center; gap: 9px; color: var(--text); font-weight: 650; }
                  .check input { width: 18px; height: 18px; accent-color: var(--accent); }
                  .note { margin-top: 10px; border-radius: 6px; background: var(--accent-soft); color: var(--accent-dark); padding: 9px 11px; font-size: 12px; }
                  .error { display: none; border: 1px solid rgba(179, 38, 30, .35); border-radius: 6px; background: #fff4f3; color: var(--danger); padding: 10px 12px; font-weight: 700; }
                  .actions { display: flex; justify-content: flex-end; gap: 10px; }
                  button { min-height: 38px; border-radius: 6px; padding: 8px 15px; font-weight: 750; cursor: pointer; }
                  .secondary { border: 1px solid #c6d0c8; background: #fff; color: var(--text); }
                  .primary { border: 1px solid var(--accent); background: var(--accent); color: #fff; }
                  .primary:hover { background: var(--accent-dark); }
                  @media (max-width: 470px) { .grid { grid-template-columns: 1fr; } .shell { padding: 12px; } }
                </style>
              </head>
              <body>
                <main class="shell">
                  <header>
                    <div class="brand">SonVu Furniture Builder</div>
                    <h1>#{title}</h1>
                  </header>
                  <form id="furnitureForm">
                    <section class="panel">
                      <h2>Loại tủ và tên gọi</h2>
                      <div class="grid">
                        <div class="field">
                          <label for="preset_key">Mẫu tủ</label>
                          <select id="preset_key"></select>
                        </div>
                        <div class="field">
                          <label for="cabinet_name">Tên tủ</label>
                          <input id="cabinet_name" type="text" maxlength="100">
                        </div>
                      </div>
                    </section>

                    <section class="panel">
                      <h2>Kích thước tổng thể</h2>
                      <div class="grid">
                        #{number_field('width_mm', 'Rộng tủ', 1)}
                        #{number_field('height_mm', 'Cao tủ', 1)}
                        #{number_field('depth_mm', 'Sâu tủ', 1)}
                        #{number_field('panel_thickness_mm', 'Dày ván chính', 0.1)}
                        #{number_field('back_thickness_mm', 'Dày tấm hậu', 0.1)}
                      </div>
                    </section>

                    <section class="panel">
                      <h2>Khoang tủ và chân tủ</h2>
                      <div class="grid">
                        #{integer_field('shelf_count', 'Số hàng đợt mỗi khoang')}
                        #{integer_field('divider_count', 'Số vách đứng')}
                        #{number_field('plinth_height_mm', 'Cao chân tủ', 1)}
                        #{number_field('plinth_setback_mm', 'Lùi chân tủ từ mặt trước', 1)}
                      </div>
                      <div class="note">Khi có vách đứng, mỗi hàng đợt được chia thành từng tấm riêng theo từng khoang.</div>
                    </section>

                    <section class="panel">
                      <h2>Vật liệu và dữ liệu sản xuất</h2>
                      <div class="grid">
                        <div class="field">
                          <label for="material_name">Tên vật liệu</label>
                          <input id="material_name" type="text" maxlength="100">
                        </div>
                        <div class="field">
                          <label for="grain_mode">Hướng vân</label>
                          <select id="grain_mode">
                            #{Presets::GRAIN_OPTIONS.map { |item| "<option value=\"#{item}\">#{item}</option>" }.join}
                          </select>
                        </div>
                        <div class="field full checks">
                          <label class="check"><input id="include_back" type="checkbox"> Tạo tấm hậu</label>
                          <label class="check"><input id="edge_band_front" type="checkbox"> Đánh dấu dán cạnh trước cho các tấm chính</label>
                        </div>
                      </div>
                    </section>

                    <section class="panel">
                      <h2>Mặt cánh và mặt ngăn kéo</h2>
                      <div class="grid">
                        <div class="field">
                          <label for="front_layout">Bố trí mặt trước</label>
                          <select id="front_layout">
                            #{Presets::FRONT_LAYOUTS.map { |key, label| "<option value=\"#{key}\">#{label}</option>" }.join}
                          </select>
                        </div>
                        <div class="field">
                          <label for="front_cover_mode">Kiểu phủ mặt cánh</label>
                          <select id="front_cover_mode">
                            #{Presets::COVER_OPTIONS.map { |item| "<option value=\"#{item}\">#{item}</option>" }.join}
                          </select>
                        </div>
                        #{number_field('front_thickness_mm', 'Dày mặt cánh', 0.1)}
                        #{number_field('front_gap_mm', 'Khe hở mặt cánh', 0.1)}
                        #{number_field('top_drawer_height_mm', 'Cao mặt ngăn kéo trên', 1)}
                        <div class="field">
                          <label for="front_material_name">Vật liệu mặt cánh</label>
                          <input id="front_material_name" type="text" maxlength="100">
                        </div>
                        <div class="field">
                          <label for="front_grain_mode">Hướng vân mặt cánh</label>
                          <select id="front_grain_mode">
                            #{Presets::GRAIN_OPTIONS.map { |item| "<option value=\"#{item}\">#{item}</option>" }.join}
                          </select>
                        </div>
                        <div class="field full checks">
                          <label class="check"><input id="front_edge_band_all" type="checkbox"> Đánh dấu dán cạnh bốn phía cho mặt cánh</label>
                        </div>
                      </div>
                      <div class="note">Giai đoạn 2A tạo mặt cánh và mặt ngăn kéo. Hộp ngăn kéo và phụ kiện được cấu hình ở các phần tiếp theo.</div>
                    </section>

                    <section class="panel">
                      <h2>Hộp ngăn kéo</h2>
                      <div class="grid">
                        <div class="field full checks">
                          <label class="check"><input id="include_drawer_boxes" type="checkbox"> Tạo hộp ngăn kéo theo các mặt ngăn kéo</label>
                        </div>
                        #{number_field('drawer_side_clearance_mm', 'Độ hở ray mỗi bên', 0.1)}
                        #{number_field('drawer_box_depth_mm', 'Sâu hộp (0 = tự động)', 1)}
                        #{number_field('drawer_box_height_mm', 'Cao hộp ngăn kéo', 1)}
                        #{number_field('drawer_panel_thickness_mm', 'Dày thành hộp', 0.1)}
                        #{number_field('drawer_bottom_thickness_mm', 'Dày đáy ngăn kéo', 0.1)}
                        #{number_field('drawer_front_setback_mm', 'Lùi hộp từ mặt trước', 1)}
                        #{number_field('drawer_rear_clearance_mm', 'Hở phía sau hộp', 1)}
                        <div class="field">
                          <label for="drawer_material_name">Vật liệu hộp ngăn kéo</label>
                          <input id="drawer_material_name" type="text" maxlength="100">
                        </div>
                      </div>
                      <div class="note">Độ hở ray được áp dụng riêng cho mỗi bên. Nhập sâu hộp bằng 0 để plugin tự dùng toàn bộ chiều sâu còn lại sau khoảng lùi trước và khoảng hở sau.</div>
                    </section>

                    <section class="panel">
                      <h2>Phụ kiện cơ bản</h2>
                      <div class="grid">
                        <div class="field full checks">
                          <label class="check"><input id="include_handles" type="checkbox"> Tạo tay nắm cho các mặt cánh</label>
                        </div>
                        #{number_field('handle_length_mm', 'Chiều dài tay nắm', 1)}
                        #{number_field('handle_width_mm', 'Chiều rộng tay nắm', 0.1)}
                        #{number_field('handle_projection_mm', 'Độ nhô tay nắm', 1)}
                        #{number_field('handle_edge_offset_mm', 'Cách mép đóng cánh', 1)}
                        <div class="field full checks">
                          <label class="check"><input id="include_hinges" type="checkbox"> Tạo mẫu bản lề chén cho cánh</label>
                        </div>
                        <div class="field">
                          <label for="hinge_count">Số bản lề mỗi cánh (0 = tự động)</label>
                          <input id="hinge_count" type="number" min="0" max="#{Specification::MAX_HINGE_COUNT}" step="1" inputmode="numeric">
                        </div>
                        #{number_field('hinge_cup_diameter_mm', 'Đường kính chén bản lề', 0.1)}
                        #{number_field('hinge_cup_depth_mm', 'Chiều sâu chén bản lề', 0.1)}
                        #{number_field('hinge_edge_offset_mm', 'Tâm chén cách cạnh bản lề', 0.1)}
                        #{number_field('hinge_end_offset_mm', 'Bản lề cách hai đầu cánh', 1)}
                        <div class="field full checks">
                          <label class="check"><input id="include_drawer_slides" type="checkbox"> Tạo ray cho hộp ngăn kéo</label>
                        </div>
                        #{number_field('drawer_slide_length_mm', 'Chiều dài ray (0 = tự động)', 1)}
                        #{number_field('drawer_slide_height_mm', 'Chiều cao ray', 0.1)}
                        #{number_field('drawer_slide_thickness_mm', 'Độ dày ray mỗi bên', 0.1)}
                        <div class="field">
                          <label for="hardware_material_name">Vật liệu phụ kiện</label>
                          <input id="hardware_material_name" type="text" maxlength="100">
                        </div>
                      </div>
                      <div class="note">Các phụ kiện là component mẫu để bố trí và thống kê. Plugin chưa khoan hay cắt trực tiếp vào tấm ván. Số bản lề bằng 0 sẽ tự chọn theo chiều cao cánh; chiều dài ray bằng 0 sẽ theo chiều sâu hộp.</div>
                    </section>

                    <div id="error" class="error"></div>
                    <div class="actions">
                      <button class="secondary" type="button" onclick="cancelDialog()">Hủy</button>
                      <button class="primary" type="submit">#{action_label}</button>
                    </div>
                  </form>
                </main>
                <script>
                  const presets = #{presets_json};
                  const initial = #{initial_json};
                  const presetSelect = document.getElementById('preset_key');
                  const valueFields = [
                    'cabinet_name', 'width_mm', 'height_mm', 'depth_mm', 'panel_thickness_mm',
                    'back_thickness_mm', 'shelf_count', 'divider_count', 'plinth_height_mm',
                    'plinth_setback_mm', 'material_name', 'grain_mode', 'front_layout',
                    'front_cover_mode', 'front_thickness_mm', 'front_gap_mm',
                    'top_drawer_height_mm', 'front_material_name', 'front_grain_mode',
                    'drawer_side_clearance_mm', 'drawer_box_depth_mm', 'drawer_box_height_mm',
                    'drawer_panel_thickness_mm', 'drawer_bottom_thickness_mm',
                    'drawer_front_setback_mm', 'drawer_rear_clearance_mm', 'drawer_material_name',
                    'handle_length_mm', 'handle_width_mm', 'handle_projection_mm',
                    'handle_edge_offset_mm', 'hinge_count', 'hinge_cup_diameter_mm',
                    'hinge_cup_depth_mm', 'hinge_edge_offset_mm', 'hinge_end_offset_mm',
                    'drawer_slide_length_mm', 'drawer_slide_height_mm',
                    'drawer_slide_thickness_mm', 'hardware_material_name'
                  ];
                  const checkboxFields = [
                    'include_back', 'edge_band_front', 'front_edge_band_all', 'include_drawer_boxes',
                    'include_handles', 'include_hinges', 'include_drawer_slides'
                  ];
                  const drawerFrontLayouts = #{safe_json(Presets::DRAWER_FRONT_LAYOUTS)};
                  const hingeFrontLayouts = #{safe_json([
                    Presets::FRONT_SINGLE_DOOR,
                    Presets::FRONT_DOUBLE_DOOR,
                    Presets::FRONT_TOP_DRAWER_DOUBLE_DOOR,
                    Presets::FRONT_FLAP
                  ])};

                  Object.keys(presets).forEach((key) => {
                    const option = document.createElement('option');
                    option.value = key;
                    option.textContent = presets[key].label;
                    presetSelect.appendChild(option);
                  });

                  function applyValues(values) {
                    valueFields.forEach((id) => {
                      if (values[id] !== undefined && values[id] !== null) document.getElementById(id).value = values[id];
                    });
                    checkboxFields.forEach((id) => {
                      if (values[id] !== undefined) document.getElementById(id).checked = Boolean(values[id]);
                    });
                    updateBackState();
                    updateFrontState();
                  }

                  function applyPreset(key) {
                    const preset = presets[key];
                    if (!preset) return;
                    applyValues(preset);
                  }

                  function updateBackState() {
                    document.getElementById('back_thickness_mm').disabled = !document.getElementById('include_back').checked;
                  }

                  function updateFrontState() {
                    const layout = document.getElementById('front_layout').value;
                    const disabled = layout === '#{Presets::FRONT_NONE}';
                    [
                      'front_cover_mode', 'front_thickness_mm', 'front_gap_mm',
                      'front_material_name', 'front_grain_mode', 'front_edge_band_all'
                    ].forEach((id) => { document.getElementById(id).disabled = disabled; });
                    document.getElementById('top_drawer_height_mm').disabled =
                      disabled || layout !== '#{Presets::FRONT_TOP_DRAWER_DOUBLE_DOOR}';
                    updateDrawerState();
                  }

                  function updateDrawerState() {
                    const hasDrawerFront = drawerFrontLayouts.includes(document.getElementById('front_layout').value);
                    const includeDrawer = document.getElementById('include_drawer_boxes');
                    includeDrawer.disabled = !hasDrawerFront;
                    if (!hasDrawerFront) includeDrawer.checked = false;
                    const disabled = !hasDrawerFront || !includeDrawer.checked;
                    [
                      'drawer_side_clearance_mm', 'drawer_box_depth_mm', 'drawer_box_height_mm',
                      'drawer_panel_thickness_mm', 'drawer_bottom_thickness_mm',
                      'drawer_front_setback_mm', 'drawer_rear_clearance_mm', 'drawer_material_name'
                    ].forEach((id) => { document.getElementById(id).disabled = disabled; });
                    updateHardwareState();
                  }

                  function updateHardwareState() {
                    const layout = document.getElementById('front_layout').value;
                    const hasFront = layout !== '#{Presets::FRONT_NONE}';
                    const hasHingedFront = hingeFrontLayouts.includes(layout);
                    const hasDrawerBox = drawerFrontLayouts.includes(layout) &&
                      document.getElementById('include_drawer_boxes').checked;

                    const handles = document.getElementById('include_handles');
                    handles.disabled = !hasFront;
                    if (!hasFront) handles.checked = false;
                    [
                      'handle_length_mm', 'handle_width_mm', 'handle_projection_mm',
                      'handle_edge_offset_mm'
                    ].forEach((id) => { document.getElementById(id).disabled = !hasFront || !handles.checked; });

                    const hinges = document.getElementById('include_hinges');
                    hinges.disabled = !hasHingedFront;
                    if (!hasHingedFront) hinges.checked = false;
                    [
                      'hinge_count', 'hinge_cup_diameter_mm', 'hinge_cup_depth_mm',
                      'hinge_edge_offset_mm', 'hinge_end_offset_mm'
                    ].forEach((id) => { document.getElementById(id).disabled = !hasHingedFront || !hinges.checked; });

                    const slides = document.getElementById('include_drawer_slides');
                    slides.disabled = !hasDrawerBox;
                    if (!hasDrawerBox) slides.checked = false;
                    [
                      'drawer_slide_length_mm', 'drawer_slide_height_mm',
                      'drawer_slide_thickness_mm'
                    ].forEach((id) => { document.getElementById(id).disabled = !hasDrawerBox || !slides.checked; });

                    document.getElementById('hardware_material_name').disabled =
                      !handles.checked && !hinges.checked && !slides.checked;
                  }

                  presetSelect.addEventListener('change', () => applyPreset(presetSelect.value));
                  document.getElementById('include_back').addEventListener('change', updateBackState);
                  document.getElementById('front_layout').addEventListener('change', updateFrontState);
                  document.getElementById('include_drawer_boxes').addEventListener('change', updateDrawerState);
                  document.getElementById('include_handles').addEventListener('change', updateHardwareState);
                  document.getElementById('include_hinges').addEventListener('change', updateHardwareState);
                  document.getElementById('include_drawer_slides').addEventListener('change', updateHardwareState);
                  presetSelect.value = initial.preset_key || '#{Presets::DEFAULT_KEY}';
                  applyValues(initial);

                  document.getElementById('furnitureForm').addEventListener('submit', (event) => {
                    event.preventDefault();
                    const payload = { preset_key: presetSelect.value };
                    valueFields.forEach((id) => { payload[id] = document.getElementById(id).value; });
                    checkboxFields.forEach((id) => { payload[id] = document.getElementById(id).checked; });
                    window.sketchup.submitFurniture(JSON.stringify(payload));
                  });

                  function showError(message) {
                    const box = document.getElementById('error');
                    box.textContent = message;
                    box.style.display = 'block';
                    box.scrollIntoView({ behavior: 'smooth', block: 'center' });
                  }

                  function cancelDialog() { window.sketchup.cancelFurniture(); }
                </script>
              </body>
            </html>
          HTML
        end

        def number_field(id, label, step)
          <<~HTML
            <div class="field">
              <label for="#{id}">#{label}</label>
              <div class="unit-wrap">
                <input id="#{id}" type="number" min="0" step="#{step}" inputmode="decimal">
                <span class="unit">mm</span>
              </div>
            </div>
          HTML
        end

        def integer_field(id, label)
          <<~HTML
            <div class="field">
              <label for="#{id}">#{label}</label>
              <input id="#{id}" type="number" min="0" max="#{Specification::MAX_REPEAT_COUNT}" step="1" inputmode="numeric">
            </div>
          HTML
        end

        def safe_json(value)
          JSON.generate(value).gsub('<', '\\u003c').gsub('>', '\\u003e').gsub('&', '\\u0026')
        end
      end
    end
  end
end
