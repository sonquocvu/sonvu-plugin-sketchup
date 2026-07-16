(function () {
  'use strict';

  var currentState = null;
  var settingsInitialized = false;
  var generationInProgress = false;
  var settingIds = [
    'joint_length_mm', 'requested_count',
    'edge_offset_mm', 'minimum_gap_mm', 'mortise_depth_mm',
    'tenon_height_mm', 'cutter_radius_mm', 'clearance_mm'
  ];

  function byId(id) { return document.getElementById(id); }
  function send(action, payload) {
    if (!window.sketchup || typeof window.sketchup[action] !== 'function') return;
    if (payload === undefined) window.sketchup[action]();
    else window.sketchup[action](JSON.stringify(payload));
  }
  function settingsPayload() {
    var payload = {};
    settingIds.forEach(function (id) { payload[id] = byId(id).value; });
    return payload;
  }
  function setSettings(settings) {
    settingIds.forEach(function (id) {
      if (settings[id] !== undefined) byId(id).value = settings[id];
    });
    settingsInitialized = true;
  }
  function setPreviewDisplay(display) {
    byId('displayTenons').checked = Boolean(display && display.show_tenons);
    byId('displayMortises').checked = Boolean(display && display.show_mortises);
    byId('displayContact').checked = Boolean(display && display.show_contact_region);
  }
  function sendPreviewDisplay() {
    send('update_preview_display', {
      show_tenons: byId('displayTenons').checked,
      show_mortises: byId('displayMortises').checked,
      show_contact_region: byId('displayContact').checked,
      show_legend: true
    });
  }
  function renderSummary(state) {
    var summary = state.summary;
    byId('scannedCount').textContent = summary.scanned_part_count;
    byId('validCount').textContent = summary.valid_connection_count;
    byId('jointCount').textContent = summary.preview_joint_count;
    byId('skippedCount').textContent = summary.skipped_position_count;
    byId('skippedMetric').hidden = summary.skipped_position_count === 0;
    byId('skippedNote').hidden = !state.skipped_note;
    byId('skippedNote').textContent = state.skipped_note || '';
    byId('skippedDetails').hidden = !state.skipped_groups || state.skipped_groups.length === 0;
    var list = byId('skippedReasons');
    while (list.firstChild) list.removeChild(list.firstChild);
    (state.skipped_groups || []).forEach(function (group) {
      var item = document.createElement('li');
      item.textContent = group.label + ': ' + group.count;
      list.appendChild(item);
    });
    byId('summaryHint').textContent = state.preview_calculated ?
      'Đang hiển thị toàn bộ liên kết hợp lệ trong mô hình.' : 'Bấm Xem trước để bắt đầu.';
  }
  function renderReadiness(state) {
    byId('createButton').disabled = generationInProgress || !state.ready_for_generation;
    byId('recalculateButton').disabled = generationInProgress || !state.preview_calculated || state.stale;
    byId('previewButton').disabled = generationInProgress;
    byId('readinessMessage').textContent = state.readiness_message;
    byId('staleBanner').hidden = !state.stale;
    byId('staleBanner').textContent = state.stale_message || '';
  }
  function receiveState(state) {
    currentState = state;
    hideError();
    if (!settingsInitialized || (state.input_valid && state.preview_calculated)) setSettings(state.settings);
    setPreviewDisplay(state.preview_display);
    renderSummary(state);
    renderReadiness(state);
  }
  function showError(error) {
    var message = error && error.message ? error.message : 'Không thể xử lý yêu cầu.';
    byId('globalError').textContent = message;
    byId('globalError').hidden = false;
    byId('settingsError').textContent = message;
    byId('settingsError').hidden = false;
    settingIds.forEach(function (id) { byId(id).classList.remove('field-error'); });
    if (error && error.field && byId(error.field)) byId(error.field).classList.add('field-error');
    byId('createButton').disabled = true;
  }
  function hideError() {
    byId('globalError').hidden = true;
    byId('settingsError').hidden = true;
    settingIds.forEach(function (id) { byId(id).classList.remove('field-error'); });
  }
  function markInputsDirty() {
    hideError();
    byId('createButton').disabled = true;
    byId('readinessMessage').textContent = 'Thông số đã thay đổi. Bấm Tính lại để cập nhật xem trước.';
  }

  function setGenerating(value) {
    generationInProgress = Boolean(value);
    settingIds.forEach(function (id) {
      byId(id).disabled = generationInProgress;
    });
    byId('previewButton').disabled = generationInProgress;
    byId('recalculateButton').disabled = generationInProgress || !currentState ||
      !currentState.preview_calculated || currentState.stale;
    byId('createButton').disabled = generationInProgress || !currentState ||
      !currentState.ready_for_generation;
    byId('closeButton').disabled = generationInProgress;
    if (generationInProgress) {
      byId('readinessMessage').textContent = 'Đang tạo toàn bộ mộng hợp lệ...';
    } else if (currentState) {
      renderReadiness(currentState);
    }
  }

  window.SonVuAutomaticPreview = {
    receiveState: receiveState,
    showError: showError,
    setGenerating: setGenerating
  };

  byId('settingsForm').addEventListener('submit', function (event) { event.preventDefault(); });
  settingIds.forEach(function (id) { byId(id).addEventListener('input', markInputsDirty); });
  ['displayTenons', 'displayMortises', 'displayContact'].forEach(function (id) {
    byId(id).addEventListener('change', sendPreviewDisplay);
  });
  byId('previewButton').addEventListener('click', function () {
    send('preview_selection', settingsPayload());
  });
  byId('recalculateButton').addEventListener('click', function () {
    send('recalculate_preview', settingsPayload());
  });
  byId('createButton').addEventListener('click', function () { send('ready_for_generation'); });
  byId('closeButton').addEventListener('click', function () { send('close_preview'); });
  document.addEventListener('DOMContentLoaded', function () { send('preview_ready'); });
}());
