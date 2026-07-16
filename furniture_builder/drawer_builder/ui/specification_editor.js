(function () {
  'use strict';

  var automaticSupported = true;

  function element(id) { return document.getElementById(id); }
  function value(id) { return element(id).value; }
  function checked(id) { return element(id).checked; }
  function setValue(id, item) { element(id).value = item === null || typeof item === 'undefined' ? '' : item; }
  function setText(id, item) { element(id).textContent = item || ''; }

  function callRuby(name, payload) {
    if (!window.sketchup || typeof window.sketchup[name] !== 'function') { return; }
    if (typeof payload === 'undefined') {
      window.sketchup[name]();
    } else {
      window.sketchup[name](JSON.stringify(payload));
    }
  }

  function fillOptions(id, options) {
    var select = element(id);
    var index;
    select.innerHTML = '';
    for (index = 0; index < options.length; index += 1) {
      var option = document.createElement('option');
      option.value = options[index].value;
      option.textContent = options[index].label;
      select.appendChild(option);
    }
  }

  function fieldValue(section, key) {
    return section && section[key] !== null && typeof section[key] !== 'undefined' ? section[key] : '';
  }

  function loadOpening(section) {
    element('opening-enabled').checked = !!section.enabled;
    setValue('opening-width', fieldValue(section, 'opening_width'));
    setValue('opening-height', fieldValue(section, 'opening_height'));
    setValue('opening-depth', fieldValue(section, 'opening_depth'));
  }

  function loadSlides(section) {
    element('slides-enabled').checked = !!section.enabled;
    setValue('slide-type', section.slide_type || 'side_mount_ball_bearing');
    setValue('slide-preset', section.preset_name || '');
    setValue('slide-manufacturer', section.manufacturer || '');
    setValue('left-clearance', fieldValue(section, 'left_clearance'));
    setValue('right-clearance', fieldValue(section, 'right_clearance'));
    setValue('top-clearance', fieldValue(section, 'top_clearance'));
    setValue('bottom-clearance', fieldValue(section, 'bottom_clearance'));
    setValue('front-setback', fieldValue(section, 'front_setback'));
    setValue('rear-clearance', fieldValue(section, 'rear_clearance'));
    setValue('slide-thickness', fieldValue(section, 'slide_thickness'));
    setValue('slide-height', fieldValue(section, 'slide_height'));
    setValue('slide-length', fieldValue(section, 'slide_length'));
    setValue('minimum-drawer-depth', fieldValue(section, 'minimum_drawer_depth'));
    setValue('maximum-drawer-depth', fieldValue(section, 'maximum_drawer_depth'));
    updateSlideStrategy(section.automatic_supported, section.unsupported_message);
  }

  function loadBox(section) {
    element('box-enabled').checked = !!section.enabled;
    setValue('dimension-mode', section.dimension_mode || 'calculated');
    setValue('box-width', fieldValue(section, 'box_width'));
    setValue('box-height', fieldValue(section, 'box_height'));
    setValue('box-depth', fieldValue(section, 'box_depth'));
    setValue('board-thickness', fieldValue(section, 'board_thickness'));
    setValue('bottom-thickness', fieldValue(section, 'bottom_thickness'));
    setValue('front-thickness', fieldValue(section, 'front_thickness'));
    setValue('back-thickness', fieldValue(section, 'back_thickness'));
  }

  function setSectionEnabled(sectionName, enabled) {
    var section = document.querySelector('[data-section="' + sectionName + '"]');
    var controls = section.querySelectorAll('input:not([type="checkbox"]), select');
    var index;
    for (index = 0; index < controls.length; index += 1) {
      controls[index].disabled = !enabled;
    }
  }

  function updateMode() {
    var manual = value('dimension-mode') === 'manual';
    var boxEnabled = checked('box-enabled');
    var canCalculate = checked('opening-enabled') && checked('slides-enabled') && automaticSupported;
    var ids = ['box-width', 'box-height', 'box-depth'];
    var index;
    setText('dimension-indicator', manual ? 'Nhập thủ công' : 'Tự động tính');
    for (index = 0; index < ids.length; index += 1) {
      element(ids[index]).readOnly = !manual;
    }
    element('dimension-mode').options[0].disabled = !canCalculate;
    element('preview-button').disabled = !canCalculate;
  }

  function updateSlideStrategy(supported, message) {
    var strategy = element('slide-strategy-message');
    automaticSupported = supported !== false;
    strategy.textContent = message || 'Chưa có công thức tính tự động cho loại ray này.';
    strategy.hidden = supported !== false;
    updateMode();
  }

  function collect() {
    return {
      opening: {
        enabled: checked('opening-enabled'),
        opening_width: value('opening-width'),
        opening_height: value('opening-height'),
        opening_depth: value('opening-depth')
      },
      slides: {
        enabled: checked('slides-enabled'),
        slide_type: value('slide-type'),
        preset_name: value('slide-preset'),
        manufacturer: value('slide-manufacturer'),
        left_clearance: value('left-clearance'),
        right_clearance: value('right-clearance'),
        top_clearance: value('top-clearance'),
        bottom_clearance: value('bottom-clearance'),
        front_setback: value('front-setback'),
        rear_clearance: value('rear-clearance'),
        slide_thickness: value('slide-thickness'),
        slide_height: value('slide-height'),
        slide_length: value('slide-length'),
        minimum_drawer_depth: value('minimum-drawer-depth'),
        maximum_drawer_depth: value('maximum-drawer-depth')
      },
      box: {
        enabled: checked('box-enabled'),
        dimension_mode: value('dimension-mode'),
        box_width: value('box-width'),
        box_height: value('box-height'),
        box_depth: value('box-depth'),
        board_thickness: value('board-thickness'),
        bottom_thickness: value('bottom-thickness'),
        front_thickness: value('front-thickness'),
        back_thickness: value('back-thickness')
      }
    };
  }

  function resolveSlide() {
    if (value('slide-type') !== 'side_mount_ball_bearing' && value('slide-preset') !== '') {
      setValue('slide-preset', '');
    }
    callRuby('drawer_editor_resolve_slide', { slides: collect().slides });
  }

  function bindEvents() {
    element('opening-enabled').addEventListener('change', function () {
      setSectionEnabled('opening', this.checked);
      updateMode();
    });
    element('slides-enabled').addEventListener('change', function () {
      setSectionEnabled('slides', this.checked);
      updateMode();
    });
    element('box-enabled').addEventListener('change', function () {
      setSectionEnabled('box', this.checked);
      updateMode();
    });
    element('dimension-mode').addEventListener('change', updateMode);
    element('slide-type').addEventListener('change', resolveSlide);
    element('slide-preset').addEventListener('change', resolveSlide);
    element('preview-button').addEventListener('click', function () {
      hideNotices();
      callRuby('drawer_editor_preview', collect());
    });
    element('save-button').addEventListener('click', function () {
      hideNotices();
      callRuby('drawer_editor_save', collect());
    });
    element('cancel-button').addEventListener('click', function () {
      callRuby('drawer_editor_cancel');
    });
    element('reset-button').addEventListener('click', function () {
      hideNotices();
      callRuby('drawer_editor_reset');
    });
  }

  function hideNotices() {
    element('error-panel').hidden = true;
    element('warning-panel').hidden = true;
  }

  window.SonVuDrawerEditor = {
    load: function (payload) {
      fillOptions('slide-type', payload.slide_options || []);
      fillOptions('slide-preset', payload.preset_options || []);
      setText('source-label', payload.source_label);
      setText('selected-role-label', payload.selected_role_label);
      setText('role-summary', payload.role_summary);
      loadOpening(payload.opening || {});
      loadSlides(payload.slides || {});
      loadBox(payload.box || {});
      setSectionEnabled('opening', !!payload.opening.enabled);
      setSectionEnabled('slides', !!payload.slides.enabled);
      setSectionEnabled('box', !!payload.box.enabled);
      updateMode();
      element('preview-panel').hidden = true;
      hideNotices();
    },

    showPreview: function (preview) {
      setText('preview-width', preview.box_width);
      setText('preview-height', preview.box_height);
      setText('preview-depth', preview.box_depth);
      setValue('box-width', preview.box_width);
      setValue('box-height', preview.box_height);
      setValue('box-depth', preview.box_depth);
      element('preview-panel').hidden = false;
      hideNotices();
    },

    applySlideConfiguration: function (configuration) {
      var keyMap = {
        left_clearance: 'left-clearance', right_clearance: 'right-clearance',
        top_clearance: 'top-clearance', bottom_clearance: 'bottom-clearance',
        front_setback: 'front-setback', rear_clearance: 'rear-clearance',
        slide_thickness: 'slide-thickness', slide_height: 'slide-height',
        slide_length: 'slide-length', minimum_drawer_depth: 'minimum-drawer-depth',
        maximum_drawer_depth: 'maximum-drawer-depth'
      };
      var key;
      for (key in keyMap) {
        if (Object.prototype.hasOwnProperty.call(keyMap, key)) {
          setValue(keyMap[key], configuration[key]);
        }
      }
      if (configuration.manufacturer !== null && typeof configuration.manufacturer !== 'undefined') {
        setValue('slide-manufacturer', configuration.manufacturer);
      }
      updateSlideStrategy(configuration.automatic_supported, configuration.unsupported_message);
      hideNotices();
    },

    showError: function (error) {
      var panel = element('error-panel');
      panel.textContent = error.message || 'Dữ liệu ngăn kéo không hợp lệ.';
      panel.hidden = false;
      if (error.field) {
        var fieldId = error.field.replace(/_/g, '-');
        if (element(fieldId)) { element(fieldId).focus(); }
      }
    },

    saved: function (result) {
      if (result.warnings && result.warnings.length) {
        element('warning-panel').textContent = result.warnings.join(' ');
        element('warning-panel').hidden = false;
      }
    }
  };

  document.addEventListener('DOMContentLoaded', function () {
    bindEvents();
    callRuby('drawer_editor_ready');
  });
}());
