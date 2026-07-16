# SketchUp 2023 Drawer Smoke-Test Report

## Environment

- SketchUp version: 23.0.367 installed; live application version not confirmed from Ruby Console
- Ruby version: 2.7.7 target; live `RUBY_VERSION` not recorded
- Plugin version: 0.16.0
- Plugin commit: Not available — the plugin files are untracked in the containing worktree
- Package: `dist/SonVu_CNC_Plugins_0.16.0_Step8.rbz`
- Package SHA-256: `D59B6D4352932C21CC22B4549E7E85766671068700CD7F5F12E174900E1CDE6A`
- Operating system: Windows NT 10.0 build 26200, x64; registry display version 25H2
- Test date: 2026-07-16
- Tester: Pending manual tester

## Execution Status

Codex did not complete an interactive SketchUp smoke test. The configured
computer-control skill was unavailable. A hidden SketchUp 2023 process was
started with the existing disposable `-RubyStartup` smoke script, but it stayed
at startup without producing its JSON report after 45 seconds. Only that newly
launched process was terminated. No model was saved.

This document is therefore a ready-to-use test record. Do not change a status
to `PASS` until the expected behavior is observed in SketchUp 2023.

## Summary

- Passed: 0 live test groups
- Failed: 0 live test groups
- Blocked: 1 (`Plugin startup` — unattended launch could not pass startup)
- Not tested: 20
- Geometry-work pass gate: **NOT SATISFIED**

## Automated Pre-Test Results

| Check | Result | Evidence |
|---|---|---|
| 1. All project tests | PASS | 36 files, 374 runs, 2,203 assertions, 0 failures, 0 errors |
| 2. Drawer-builder tests | PASS | 16 files, 204 runs, 986 assertions, 0 failures, 0 errors |
| 3. Ruby syntax | PASS | All 102 plugin Ruby files syntax-clean |
| 4. UTF-8 validation | PASS | All 136 relevant Ruby/HTML/JavaScript/CSS/SVG/Markdown files decode as strict UTF-8 |
| 5. Ruby 2.7.7 compatibility scan | PASS with live confirmation pending | No endless methods, pattern matching, `Data.define`, `Regexp.timeout`, or Ruby 3 hash-value omission. Required/default keyword arguments found are Ruby 2.7-compatible. |
| 6. Duplicate menu registration | PASS statically | `@menu_registered` and `@context_menu_registered` guards exist; drawer registration has one loader call |
| 7. Raw English UI messages | PASS statically | Two English strings are internal `SpecificationOwner` exceptions; callback/command boundaries map them to Vietnamese before display |
| 8. JavaScript drawer formulas | PASS | Zero dimension-formula matches after comments and strings are stripped; JavaScript only gathers/displays values |
| 9. Direct metadata writes in commands | PASS | No `Metadata.write`, `set_attribute`, `delete_attribute`, or direct `Persistence.write` in drawer command handlers |
| 10. Geometry mutation in editor | PASS | No add/erase/transform/explode/push-pull/intersection calls in editor, presenter, parser, or owner service |

## Test Package and Installation

- SketchUp Plugins directory:
  `C:\Users\vuquo\AppData\Roaming\SketchUp\SketchUp 2023\SketchUp\Plugins`
- Entry file: `sonvu_cnc_plugins.rb`
- Root folder: `sonvu_cnc_plugins`
- Loader file: `sonvu_cnc_plugins/main.rb`
- Installable package: `dist/SonVu_CNC_Plugins_0.16.0_Step8.rbz`
- Required copy set: the entry file and the complete `sonvu_cnc_plugins` folder
- Restart required: Yes; close every SketchUp process and start SketchUp 2023 again
- Ruby Console: Open `Window → Ruby Console` immediately after startup and keep it visible
- Normal startup output: None expected. Any exception or load-error text is a failure record.
- Licensing: Use the existing license/trial flow. Do not bypass or modify it.

For this workstation the current source is already in the correct Plugins
directory. A clean restart tests that installed copy. To test Step 9 on another
SketchUp 2023 installation, copy the current `sonvu_cnc_plugins.rb` entry file
and complete `sonvu_cnc_plugins` folder, then restart SketchUp.

> Step 9 note: the Step 8 RBZ package predates the drawer toolbar. Test the
> currently installed development source for Step 9 until a new release package
> is prepared.

## Disposable Model Setup

1. Start a new blank model and do not save over a customer model.
2. Create and name four Groups: `Group A - Opening`, `Group B - Left slide`,
   `Group C - Right slide`, and `Group D - Drawer box`.
3. Create two ComponentInstances named `Component E - Second opening` and
   `Component F - Second drawer box`.
4. Keep one loose Face.
5. Create one Group and lock it through Entity Info.
6. Create `Group G - Metadata preservation`, select it, and seed only actual
   repository metadata with this Ruby Console snippet:

```ruby
entity = Sketchup.active_model.selection.first
dictionary = 'SonVu_CNC_Plugins'
{
  'furniture_panel' => true,
  'furniture_cabinet_id' => 'SMOKE-CAB-01',
  'part_key' => 'smoke_hardware_01',
  'part_name_vi' => 'Phụ kiện kiểm tra',
  'part_role' => 'drawer_slide_left',
  'part_kind' => 'hardware',
  'material_name' => 'Phụ kiện kim khí',
  'finished_length_mm' => 500.0,
  'finished_width_mm' => 45.0,
  'thickness_mm' => 12.5,
  'grain_direction' => 'none',
  'grain_axis' => 'length',
  'geometry_shape' => 'box',
  'edge_band_front' => false,
  'edge_band_back' => false,
  'edge_band_left' => false,
  'edge_band_right' => false,
  'drawer_index' => 7,
  'owner_part_key' => 'smoke_owner_01',
  'hardware_type' => 'drawer_slide_left'
}.each { |key, value| entity.set_attribute(dictionary, key, value) }
```

Costing catalogs and CNC plans are currently derived/read-only data, not
production entity attribute keys. Do not invent `costing` or `cnc_operation`
attributes for this test.

Capture metadata and geometry before assignment:

```ruby
dictionary = 'SonVu_CNC_Plugins'
metadata_snapshot = lambda do |entity|
  values = {}
  data = entity.attribute_dictionary(dictionary, false)
  data.each_pair { |key, value| values[key] = value } if data
  values
end
geometry_snapshot = lambda do |entity|
  entities = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
  bounds = entity.bounds
  {
    name: entity.name,
    transformation: entity.transformation.to_a,
    bounds: [bounds.min.to_a, bounds.max.to_a],
    faces: entities.grep(Sketchup::Face).length,
    edges: entities.grep(Sketchup::Edge).length
  }
end
metadata_before = metadata_snapshot.call(entity)
geometry_before = geometry_snapshot.call(entity)
```

After each preservation test, compare:

```ruby
metadata_snapshot.call(entity).reject { |key, _| key.start_with?('drawer_') } ==
  metadata_before.reject { |key, _| key.start_with?('drawer_') }
geometry_snapshot.call(entity) == geometry_before
```

## Test Results

### Test 1 — Plugin startup

Status: BLOCKED

Observed: SketchUp 2023 executable 23.0.367 was found. The unattended hidden
launch remained responsive but produced no runtime report or main-window title
after 45 seconds, so the launched process was terminated without saving.

Expected: SketchUp starts without plugin-load errors; existing SonVu features
load once; Vietnamese text has no broken UTF-8 characters.

Ruby Console: Not available during unattended attempt.

Screenshot: None.

Manual checklist:

- [ ] Fresh SketchUp restart completed
- [ ] `RUBY_VERSION` in Ruby Console reports `2.7.7`
- [ ] No startup exception
- [ ] Existing SonVu tools load
- [ ] Vietnamese characters render correctly
- [ ] No duplicate `SonVu CNC Plugins` menus

### Test 2 — Extensions menu

Status: NOT TESTED

Observed: Pending.

Expected: Exactly one `SonVu CNC Plugins → Ngăn kéo` submenu with one `Gán vai
trò` submenu and one `Chỉnh sửa thông số ngăn kéo` item. Assignment labels and
`Bỏ gán vai trò ngăn kéo` are Vietnamese and occur once. Existing menu items and
license gating remain intact.

Ruby Console: Pending.

Screenshot: Pending.

### Test 3 — Right-click menu visibility

Status: NOT TESTED

Observed: Pending.

Expected: No drawer context menu for empty, loose-Face, multiple, or deleted
selection. An unassigned Group shows assignment commands but not Unassign or
Edit. One assigned Group or ComponentInstance also shows `Bỏ gán vai trò ngăn
kéo` and `Chỉnh sửa thông số ngăn kéo`. Record delay or duplicates.

Ruby Console: Pending.

Screenshot: Pending for unassigned and assigned cases.

### Test 4 — New drawer system assignment

Status: NOT TESTED

Observed: Pending.

Expected: Select Group A and run `Gán làm khoang ngăn kéo`. One new standalone
system identity and one Undo entry are created; unrelated metadata and geometry
are unchanged. Undo restores the prior identity state.

Ruby Console: Pending.

Screenshot: Pending.

### Test 5 — Joining an existing system

Status: NOT TESTED

Observed: Pending.

Expected: Group B joins Group A as `drawer_slide_left`; Group C joins as
`drawer_slide_right`; Group D joins as `drawer_box`. Confirmation or picker is
Vietnamese. All share one internal system ID, verified only in Ruby Console.
Normal UI must not expose the ID.

Ruby Console: Pending.

Screenshot: Pending.

### Test 6 — Partial systems

Status: NOT TESTED

Observed: Pending.

Expected: Opening-only, slides-only, box-only, opening-and-box, and
opening-and-slides systems are accepted. Registry state is correct and
read-only inspection creates no attribute writes or Undo entries.

Ruby Console: Pending.

Screenshot: Pending.

### Test 7 — Role conflicts and reassignment

Status: NOT TESTED

Observed: Pending.

Expected: A duplicate left slide is rejected without overwriting existing data.
Changing `ray trái` to `ray phải` requires explicit Vietnamese confirmation.
Cancel changes nothing; confirm is atomic; Undo restores the old role.

Ruby Console: Pending.

Screenshot: Pending for conflict and confirmation.

### Test 8 — Moving between systems

Status: NOT TESTED — STATIC UX RISK RECORDED

Observed: Static inspection found that the command method accepts an explicit
`target_system_id`, but the normal command path retains the entity's current
system ID before opening `SystemPicker`. No visible destination-system selector
for an already assigned entity was identified. Verify this in SketchUp before
classifying it as a failure.

Expected: Moving between two systems requires explicit Vietnamese confirmation;
cancel is unchanged; confirm moves atomically; destination conflicts remain
enforced; Undo restores the original system.

Ruby Console: Pending.

Screenshot: Pending. If no destination UI exists, capture the available menu and
record a focused critical failure before any fix.

### Test 9 — Negative entity cases

Status: NOT TESTED

Observed: Pending.

Expected:

- Loose Face: `Vui lòng chọn một Group hoặc Component hợp lệ.`
- Locked Group: `Không thể thay đổi đối tượng đang bị khóa.`
- Empty selection: `Vui lòng chọn một đối tượng.`
- Multiple selection: `Vui lòng chỉ chọn một đối tượng.`
- No failed command leaves an open operation or Undo entry.

Ruby Console: Pending.

Screenshot: Pending.

### Test 10 — Specification editor

Status: NOT TESTED

Observed: Pending.

Expected: `Chỉnh sửa thông số ngăn kéo` opens `Thông số ngăn kéo`; all sections
and role-composition text are Vietnamese; UUID is hidden; partial systems open
safely; opening the dialog creates no model write.

Ruby Console: Pending.

Screenshot: Pending.

### Test 11 — Millimetre parsing

Status: NOT TESTED

Observed: Pending.

Expected: Opening `600 × 200 × 550` persists numerically in millimetres after
conversion. Both `12.5` and `12,5` normalize to the same value. Reopening shows
the same values without formatted `"mm"` strings in metadata.

Ruby Console: Pending.

Screenshot: Pending.

### Test 12 — Slide preset and legacy values

Status: NOT TESTED

Observed: Pending.

Expected: `Ray bi hai bên` with `Tương thích ngăn kéo SonVu hiện tại` resolves
left/right clearances to `12.5 mm` through Ruby. Changing preset refreshes from
`SlideConfigurations`. Unsupported automatic strategies display the Vietnamese
warning.

Ruby Console: Pending.

Screenshot: Pending.

### Test 13 — Calculation preview

Status: NOT TESTED

Observed: Pending.

Expected: `Tính lại kích thước thùng` returns width `575 mm` for a `600 mm`
opening with two `12.5 mm` side clearances. Legacy production inputs return
depth `531 mm`. Preview creates no attribute writes or Undo entry; cancel after
preview leaves persisted data unchanged.

Ruby Console: Pending.

Screenshot: Pending.

### Test 14 — Save, cancel, reset, and close

Status: NOT TESTED

Observed: Pending.

Expected: Save creates one atomic operation, persists, closes, and reopens with
saved values. Cancel and window close write nothing and create no Undo entry.
Reset restores dialog-open values and writes nothing until Save. Geometry is
unchanged in every case.

Ruby Console: Pending.

Screenshot: Pending.

### Test 15 — Stale dialog protection

Status: NOT TESTED

Observed: Pending.

Expected: Open the editor, then delete or reassign the selected entity before
saving. Save fails in Vietnamese, writes to no other system, and leaves no open
or partial operation.

Ruby Console: Pending.

Screenshot: Pending.

### Test 16 — Undo and redo

Status: NOT TESTED

Observed: Pending.

Expected: Assignment, reassignment, move, unassignment, and specification save
each use one logical Undo step. Undo restores the full prior metadata; Redo
restores the new state. Unrelated metadata and geometry remain unchanged.

Ruby Console: Pending.

Screenshot: Pending.

### Test 17 — Metadata preservation

Status: NOT TESTED

Observed: Pending.

Expected: Use Group G and the snapshots above. Assignment, specification save,
reassignment, move, unassignment, and Undo preserve every unrelated production
key value-for-value. Only standalone drawer identity and the authoritative
`drawer_specification_json` may change as intended.

Ruby Console: Pending comparison output.

Screenshot: Pending.

### Test 18 — Component-instance safety

Status: NOT TESTED

Observed: Pending.

Expected: Assign Component E while another instance shares its definition. Only
the selected instance receives identity; the other instance and shared
definition remain unchanged. Specification editing does not change either
instance's geometry.

Ruby Console: Pending.

Screenshot: Pending.

### Test 19 — Active editing context

Status: NOT TESTED

Observed: Pending.

Expected: Inside a Group/Component edit context, only systems in
`model.active_entities` are offered. External systems are not mixed in;
transforms remain unchanged; no visible recursive-scan delay occurs; assignments
survive exiting the context.

Ruby Console: Pending.

Screenshot: Pending.

### Test 20 — Regression check

Status: NOT TESTED

Observed: Pending.

Expected: Existing cabinet creation, embedded drawer generation, cut lists,
costing, optimization, CNC planning, license gating, and metadata consumers
remain functional. Confirm automatic depth `531 mm` and left/right clearances
`12.5 mm` in the real runtime.

Ruby Console: Pending.

Screenshot: Pending.

### Test 21 — Vietnamese drawer toolbar

Status: NOT TESTED

Observed: Pending.

Expected: Exactly one toolbar named `Ngăn kéo` is available through
`View → Toolbars`. It uses the same command objects as the Extensions and
context menus, preserves its SketchUp-managed visibility state, and does not
change geometry during registration or validation.

Ruby Console: Pending.

Screenshot: Pending with the toolbar visible at normal display scaling.

Manual checklist:

1. [ ] Restart SketchUp 2023.
2. [ ] Open `View → Toolbars` and confirm one `Ngăn kéo` toolbar exists.
3. [ ] Show the toolbar.
4. [ ] Confirm button order: opening, left slide, right slide, drawer box,
   separator, edit specification, unassign.
5. [ ] Confirm `Gán làm hệ ngăn kéo` remains menu-only.
6. [ ] Confirm all six small/large icons render clearly without text or broken images.
7. [ ] Hover over each button and verify Vietnamese tooltip text.
8. [ ] With no selection, confirm every button is disabled.
9. [ ] With one loose Face, confirm every button is disabled.
10. [ ] With one unlocked unassigned Group, confirm the four assignment buttons
    are enabled while Edit and Unassign are disabled.
11. [ ] With one assigned Group, confirm assignment, Edit, and Unassign states
    update as documented.
12. [ ] Click each enabled button and compare behavior with the matching menu command.
13. [ ] Confirm the existing license message/gate is unchanged.
14. [ ] Restart SketchUp and confirm no duplicate drawer toolbar appears.
15. [ ] Confirm toolbar visibility/position is restored where SketchUp supports it.
16. [ ] Confirm the existing `Mộng CNC` and `SonVu Nội thất` toolbars are unchanged.

## Geometry Integrity Record

- Model entity count before: Pending
- Model entity count after: Pending
- Group A face/edge count before and after: Pending
- Group B face/edge count before and after: Pending
- Group C face/edge count before and after: Pending
- Group D face/edge count before and after: Pending
- Component E definition count before and after: Pending
- Component F definition count before and after: Pending
- Transformations unchanged: Pending
- Bounding boxes unchanged: Pending
- Names unchanged: Pending
- No exploded entities: Pending
- No plugin-generated drawer geometry: Pending

## Failure Record Template

Duplicate this section for every failure before changing code.

### Failure — Short title

- Test number:
- Exact Vietnamese command:
- Selected entity type:
- Active editing context:
- Expected behavior:
- Actual behavior:
- Ruby Console stack trace:
- Diagnostic log:
- Undo still functional: Yes / No / Unknown
- Unexpected metadata change:
- Unexpected geometry change:
- Minimal reproduction:
  1.
  2.
  3.
- Screenshot reference:
- Critical: Yes / No

## Pass Gate

The geometry-work gate remains **NOT SATISFIED** until real SketchUp 2023
evidence passes startup, menu/context registration, assignment/join/conflict,
moving systems, save/cancel/preview, Undo, metadata preservation,
ComponentInstance isolation, legacy regression, and geometry integrity.
The Step 9 gate also requires the drawer-toolbar checks above.
