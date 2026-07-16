# SonVu CNC Plugins — Development Guide

This is the primary technical reference for future Codex sessions and human
developers. It describes the current implementation, not an aspirational API.

## 1. Product scope

The extension provides CNC woodworking template generators for SketchUp.
Customer-facing commands are intentionally separate:

- **Trung tâm nội thất** is the Vietnamese read-only workflow dashboard. It
  reports current selection/model counts and license state, then routes to the
  existing workflow commands. The `SonVu Nội thất` toolbar exposes Dashboard,
  Create, Edit, Cut List, Cost Estimate, Sheet Optimization, and CNC Preview as
  distinct icon commands.
- **Tạo tủ nội thất** creates a Vietnamese preset-based furniture carcass with
  optional Phase 2A doors/fronts, Phase 2B five-panel drawer boxes, and Phase
  2C hardware templates, then starts a click-to-place tool.
- **Chỉnh sửa tủ đã chọn** rebuilds only a tagged SonVu furniture group from
  its stored parameters while preserving its transformation.
- **Danh sách chi tiết** reads selected SonVu cabinets, or all cabinets when
  none are selected, displays the Phase 3A aggregated report, and exports the
  Phase 3B board/hardware CSV pair on explicit user request. Phase 3C adds a
  saved price catalog, cabinet/project cost totals, and quotation CSV export.
- **Dự toán chi phí** opens the same Phase 3C costing workflow directly for the
  selected-cabinet or whole-model report scope.
- **Tối ưu cắt ván** opens the Phase 4A read-only rectangular sheet optimizer
  and Phase 4B interactive SVG sheet maps for the same report scope. Phase 4C
  exports a printable HTML report and placement CSV on explicit user request.
- **Xem trước gia công CNC** opens the Phase 5A–5C read-only per-panel machining
  plan. It reconstructs hinge pockets, applies saved connector/shelf-pin/groove
  rules, validates both faces, flags manufacturer-pattern references, and can
  explicitly export a neutral per-face DXF/CSV package.
- **Tạo mộng âm** creates a recessed dog-bone mortise template on one selected
  model face.
- **Tạo mộng dương** creates one or more outward tenons and unions them into the
  solid owning the selected edge face so CNC exporters see one part.
- **Xóa mẫu mộng đã tạo** deletes groups created and tagged by the plugin.
- **Tạo mộng tự động** opens a compact Vietnamese bulk-analysis dialog, skips
  unsafe contacts, previews every valid mortise/tenon pair at once, then creates
  the finalized valid batch in one atomic SketchUp operation. Its joint length
  is user-configurable; each tenon/mortise thickness is resolved from that
  connection's male-board geometry.

Mortise normally generates a separate group. Tenon is an explicitly confirmed
destructive workflow: it preserves a hidden backup, unions into the selected
solid, and remains one undoable operation. Boolean mortise cutting is advanced
internal functionality and must remain optional.

## 2. Runtime and file map

```text
sonvu_cnc_plugins.rb                 SketchUp extension registration
sonvu_cnc_plugins/
  main.rb                            dependency loading and menu startup
  constants.rb                       IDs, menu strings, presets
  version.rb                         extension version
  shared/
    units.rb                         mm/model-unit conversion
    materials.rb                     checking materials
    ui_helpers.rb                    message boxes
    licensing/                       signed-token licensing client and UI
  furniture_builder/
    dashboard_state.rb                pure dashboard summary/action enablement
    dashboard_html.rb                 Vietnamese Phase 1–5 workflow cards
    dashboard.rb                      read-only HtmlDialog controller and routing
    presets.rb                       Vietnamese cabinet, front, drawer, hardware presets
    specification.rb                 pure millimetre validation and part/hardware layout
    dialog.rb                         HtmlDialog/native inputbox controller
    dialog_html.rb                    Vietnamese Phase 1/2 tabbed furniture wizard
    geometry.rb                       tagged cabinet, panel, and hardware creation
    cut_list.rb                       read-only Phase 3A collection and aggregation
    cut_list_csv_exporter.rb          Phase 3B UTF-8 board/hardware CSV writer
    sheet_optimizer.rb                pure deterministic Phase 4A rectangle packing
    sheet_layout_svg.rb               pure Phase 4B stock-sheet SVG renderer
    sheet_layout_exporter.rb          Phase 4C printable HTML and placement CSV
    sheet_optimization_dialog_html.rb Vietnamese Phase 4C maps/results/export UI
    sheet_optimization_dialog.rb      saved settings, optimization, and export controller
    cost_estimator.rb                 pure Phase 3C pricing and allocation rules
    cost_estimate_dialog_html.rb      Vietnamese price form and quotation preview
    cost_estimate_dialog.rb           saved catalog and pricing dialog controller
    cost_estimate_csv_exporter.rb     Phase 3C quotation CSV writer
    cut_list_dialog_html.rb           Vietnamese board/hardware report markup
    cut_list_dialog.rb                HtmlDialog and native fallback controller
    machining_rules.rb                pure Phase 5B presets and validation
    machining_planner.rb              pure Phase 5A–5B panel/operation planning
    machining_exporter.rb             safe Phase 5C per-face DXF and CSV package
    machining_preview_html.rb         Vietnamese Step 5 panel maps and validation UI
    machining_preview_dialog.rb       selected/model cabinet collection and dialog
    tool.rb                           click-to-place cabinet envelope preview
    commands.rb                       reload-safe furniture menu commands
    icons/                             dashboard toolbar SVGs
    test/commands_toolbar_test.rb      toolbar order, tooltip, and icon checks
    test/dashboard_state_test.rb       dashboard state/action regression suite
    test/dashboard_html_test.rb        dashboard markup/callback regression suite
    test/machining_planner_test.rb      Phase 5A–5B coordinate/validation suite
    test/machining_rules_test.rb        Phase 5B presets and input validation
    test/machining_exporter_test.rb     Phase 5C DXF/CSV and overwrite safety suite
    test/machining_preview_html_test.rb Step 5 SVG/escaping/UI regression suite
    test/machining_preview_dialog_test.rb selection/model scope regression suite
    test/specification_test.rb        SketchUp-free layout regression suite
    test/cut_list_test.rb              SketchUp-free Phase 3A report regression suite
    test/cut_list_csv_exporter_test.rb SketchUp-free Phase 3B export regression suite
    test/cost_estimator_test.rb        Phase 3C calculation regression suite
    test/cost_estimate_dialog_html_test.rb Phase 3C form/report HTML regression suite
    test/cost_estimate_csv_exporter_test.rb Phase 3C quote export regression suite
    test/sheet_optimizer_test.rb       Phase 4A packing and constraint regression suite
    test/sheet_layout_svg_test.rb       Phase 4B SVG rendering regression suite
    test/sheet_layout_exporter_test.rb  Phase 4C export regression suite
    test/sheet_optimization_dialog_html_test.rb Phase 4C HTML regression suite
    test/sketchup_runtime_smoke.rb     disposable real-SketchUp smoke harness
  dogbone_joinery/
    commands.rb                      commands, toolbar, selection workflow
    dialog.rb                        parsing, validation, settings conversion
    dialog_html.rb                   HtmlDialog HTML/CSS/JavaScript
    geometry.rb                      profile and solid construction
    vertical_tbone_geometry.rb       shared pure vertical T-bone cutter measurements
    tool.rb                          selected-face local coordinate frame
    automatic_planning/             read-only world-space joint analysis and plans
      geometry_values.rb            pure points, vectors, faces, boards, transforms
      joint_layout.rb               unit-agnostic fit validation and shared positions
      joint_dimensions.rb           per-male-board resolved thickness contract
      preview_plan.rb               immutable/copy-on-write preview representation
      contact_analysis.rb           planar overlap, classification, assignment, planner
      sketchup_adapter.rb           read-only nested Group/ComponentInstance scanner
      preview_settings.rb           strict Vietnamese mm input and unit boundary
      preview_state.rb              UI state, recalculation, persistence, readiness
      preview_primitives.rb         pure overlay primitives from shared joint plans
      preview_session.rb            HtmlDialog/tool/observer lifecycle controller
      ui/                            local Vietnamese HTML/CSS/JavaScript dialog
      README.md                     architecture, limits, and executor boundary
      SKETCHUP_2023_PREVIEW_SMOKE_TEST.md manual runtime checklist
    automatic_execution/            finalized-plan validation and atomic geometry
      entity_registry.rb            identity/transform checks and shared-instance isolation
      transform_adapter.rb          world-to-parent placement conversion
      geometry_adapter.rb           bridge to existing manual geometry formulas
      executor.rb                   deterministic one-operation orchestration
      README.md                     execution policy and repeated-run limitation
    icons/                            production icons
    test/geometry_test.rb             SketchUp-free regression suite
    test/automatic_planning_test.rb   pure automatic detection/planning regression suite
    test/automatic_preview_test.rb    UI state/controller/asset regression suite
    test/automatic_execution_test.rb  atomic executor and fixed-geometry regression suite
```

`main.rb` defines dependency order. Runtime startup calls
`SonVu::CNCPlugins.load_extension`, which registers commands. Reload guards in
`Commands` prevent duplicate menu and toolbar registration.

## 3. End-to-end data flow

```text
Customer selects one SketchUp::Face
        ↓
Commands.open_dialog(mode)
        ↓
Dialog.selected_face_context
  - local face width and height
  - model depth normal to the face
        ↓
DialogHTML or native inputbox
        ↓
Dialog.parse_hash → Dialog.validate → Dialog.to_settings_hash
  - converts millimetres to SketchUp model units
        ↓
PlacementTool / integrate_tenons_on_face
  - mortise displays a cursor-following outline and uses the clicked point as
    the profile centre
  - builds local X/Y/Z transformation
  - tenon integration closes one edit-context level and moves into the solid's
    parent context
        ↓
Geometry.create_templates / Geometry.union_tenons_into_solid
  - starts one undoable SketchUp operation
  - mortise creates a tagged group
  - tenon creates a temporary group and unions it into the owning solid
```

Do not bypass dialog validation when adding a UI parameter. Geometry must also
perform critical validation because it may be called independently.

## 4. Selected-face coordinate system

All feature geometry is authored in a local frame and transformed onto the
selected face:

```text
X = direction of the longest selected-face edge
Y = face normal × X; lies within the selected face
Z = outward normal of the selected face
```

Mortise placement projects the cursor onto the selected face and uses that
point as the centre of the complete dog-bone profile. Tenon placement remains
anchored and distributed along the selected edge face.

The outward normal is inferred primarily from the selected face versus the
bounds centre of connected geometry. A ray test is a fallback for ambiguous
planar geometry.

`Dialog.face_dimensions` projects face vertices onto local X/Y. It does not use
world-axis bounding-box width or height.

`Dialog.face_model_depth` projects connected-geometry vertices onto the face
normal and uses the projection span as available depth. This fits normal
board-like solids. Stepped or locally varying thickness will eventually need
local inward ray sampling at the generated profile.

## 5. Mortise contract

Important settings keys after conversion to model units:

```ruby
:mortise_width
:mortise_height
:mortise_depth
:mortise_face_width
:mortise_face_height
:mortise_model_depth
:cutter_radius
:dogbone_style
```

Current defaults:

```text
width = 20 mm
height = 20 mm
depth = 10 mm
style = Ngang (T-bone)
```

Geometry invariants:

- The dog-bone profile lies in local XY.
- The complete profile bounding box is centred on the cursor placement point.
- A green live preview indicates that the sampled outline is fully contained
  by the selected face; an invalid outline is red and cannot be placed.
- The surface is exactly `Z = 0`.
- Recessed vertices are explicitly created at `Z = -mortise_depth`.
- Do not replace this with signed `Face#pushpull`; face winding can invert the
  result and raise the mortise above the surface.

Validation requires a selected face, measurable width/height/depth, depth no
greater than model depth, and the entire relieved profile fitting inside the
face at the clicked position. Profile loops must be normalized before face
creation to avoid `Duplicate points in array`.

Mortise cutter radius and dog-bone style belong only to the mortise workflow.

## 6. Tenon contract

Important settings keys:

```ruby
:tenon_width
:tenon_height           # selected face thickness before clearance
:tenon_face_width       # available length along local X
:tenon_projection       # outward distance along local Z
:tenon_cutter_radius    # independent shoulder-relief radius
:tenon_count
:tenon_edge_offset      # symmetric margin at both X ends
:clearance
:tenon_relief_enabled
```

Current defaults:

```text
width = 40 mm
projection = 10 mm
cutter radius = 3 mm
count = 2
symmetric end margin = 20 mm
clearance = 0.2 mm
```

Geometry invariants:

- The relieved shoulder outline lies in local XZ.
- Local Z starts at the selected face and extends outward.
- The outline is extruded through local Y by selected-face thickness after
  clearance.
- Both shoulder reliefs use `tenon_cutter_radius` directly.
- Mortise cutter radius must not affect tenon relief geometry.
- Every tenon is a closed shell inside the generated tenon group.
- For CNC output, the temporary tenon group is boolean-unioned with the solid
  that owns the selected face. The result retains the board name/material/tag
  where possible and is not marked as a cleanup template.
- A 0.1 mm internal overlap is added behind the attachment plane so SketchUp
  sees a true volume intersection. The outward visible projection is preserved.

Finished dimensions:

```text
finished width  = requested width - total clearance
finished height = selected face height - total clearance
Y inset         = total clearance / 2
```

### Multiple-tenon distribution

For face width `L`, finished tenon width `W`, count `N`, and symmetric end
margin `M`:

```text
N = 1: first offset = (L - W) / 2; gap = 0

N > 1:
gap = (L - 2M - NW) / (N - 1)
x(i) = M + i(W + gap), i = 0...(N - 1)
```

The dialog displays the calculated clear gap. Reject count below one, negative
margins, or layouts where `2M + NW > L`.

### Solid-owner and union workflow

The customer must open a solid group/component for editing and select an
internal face. `Commands.selected_tenon_target` resolves the last instance in
`Model#active_path` and requires `manifold?`, `transformation`, and `union`
support. Group backups use `Group#copy`; component backups add another instance
of the component's unique definition because `ComponentInstance` has no `copy`
method in SketchUp 2023.

While still inside the edit context, `PlacementTool` calculates the face-local
frame. It composes that frame with the target instance transformation, closes
one edit level, creates the temporary tenon solid beside the target, then calls
`Geometry.union_tenons_into_solid`.

The union operation:

1. validates the target solid;
2. creates a hidden, tagged backup copy;
3. creates and transforms the temporary tenon solid with a tiny overlap;
4. unions both solids;
5. verifies the result is manifold;
6. clears the disposable generated attribute from the result;
7. selects the CNC-ready result and commits one operation.

On any exception, abort the operation. Never allow cleanup to identify the
union result as a generated tenon template because that would delete the board.

## 7. Dialog synchronization checklist

The extension supports HtmlDialog and a native inputbox fallback. Adding or
renaming a setting normally requires changes in all these places:

1. `Dialog::PROMPTS`
2. `Dialog::NUMERIC_DEFAULTS_MM`
3. `Dialog::DEFAULTS`
4. `Dialog::LISTS`
5. `Dialog#defaults_for_mode` indexes
6. `Dialog#parse_input` indexes
7. `Dialog#parse_hash`
8. feature-specific validation
9. `Dialog#to_settings_hash`
10. `DialogHTML` field definitions
11. JavaScript payload and live calculations
12. labels and tests

Prefer replacing positional arrays in a future refactor, but keep the native
fallback synchronized until then. `DEFAULT_DOGBONE_STYLE` is authoritative; do
not use `DEFAULTS[index]` in HTML because indexes change when fields are added.

## 8. Generated entities and undo safety

Generated top-level groups are named and tagged with:

```ruby
CNCPlugins::ATTRIBUTE_DICTIONARY
CNCPlugins::GENERATED_GROUP_ATTRIBUTE
```

Cleanup removes only groups with both an expected name and the generated
attribute. Do not broaden deletion to name-only matching.

All model-changing entry points must remain one atomic operation:

```ruby
model.start_operation(...)
begin
  # changes
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end
```

## 9. Testing

The suite supplies small SketchUp geometry stubs so profile mathematics,
validation, face measurement, HTML generation, and topology can run in standard
Ruby.

Run from the SketchUp Plugins directory:

```powershell
ruby sonvu_cnc_plugins\dogbone_joinery\test\geometry_test.rb
ruby sonvu_cnc_plugins\dogbone_joinery\test\automatic_planning_test.rb
ruby sonvu_cnc_plugins\dogbone_joinery\test\automatic_preview_test.rb
ruby sonvu_cnc_plugins\dogbone_joinery\test\automatic_execution_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\commands_toolbar_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\dashboard_state_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\dashboard_html_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\machining_planner_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\machining_rules_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\machining_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\machining_preview_html_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\machining_preview_dialog_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\specification_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cut_list_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cut_list_csv_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimator_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimate_dialog_html_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimate_csv_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_optimizer_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_layout_svg_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_layout_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_optimization_dialog_html_test.rb
ruby -c sonvu_cnc_plugins.rb
Get-ChildItem sonvu_cnc_plugins -Recurse -Filter *.rb | ForEach-Object { ruby -c $_.FullName }
```

To exercise the real SketchUp geometry API in a disposable blank model, launch
SketchUp interactively with:

```powershell
& 'C:\Program Files\SketchUp\SketchUp 2023\SketchUp.exe' `
  -RubyStartup "$PWD\sonvu_cnc_plugins\furniture_builder\test\sketchup_runtime_smoke.rb"
Get-Content "$env:TEMP\sonvu_furniture_builder_runtime_smoke.json"
```

The harness checks carcass/front/drawer-box/hardware component solids, linked
owner metadata, unified dashboard counts/actions, Phase 5A–5B rule operations,
read-only preview, Phase 5C in-memory DXF/CSV documents, Phase 3A read-only counts,
Phase 3B in-memory CSV contracts,
Phase 3C project/cabinet totals and quotation CSV, Phase 4A read-only sheet
packing, Phase 4B SVG maps, Phase 4C in-memory export documents, safe rebuild, preserved
transformation, preserved unrelated entities, and Undo, then closes the blank
model without saving. It must not be run against a customer model.

Tests should cover these invariants:

- no duplicate face points;
- dashboard counts/actions reflect the report, selection, and license without
  writing to the model;
- furniture wizard tabs expose Phase 1, 2A, 2B, and 2C and support direct
  opening on a requested section;
- mortise vertices never rise above surface Z;
- tenon reliefs lie in XZ and extrusion lies along Y;
- clearance is applied exactly once;
- rotated face measurements remain correct;
- invalid depth and layouts are rejected;
- one tenon centres and multiple tenons distribute evenly;
- HTML exposes every required feature-specific field.
- legacy Phase 1 furniture settings do not gain fronts during edit;
- legacy Phase 2A furniture settings do not gain drawer boxes during edit;
- legacy Phase 2B furniture settings do not gain hardware during edit;
- overlay/inset fronts respect perimeter and internal gaps;
- drawer fronts fill the available front domain without overlap;
- front material, grain, four-edge banding, and `part_kind` metadata persist.
- every enabled drawer creates exactly five panels linked to its front;
- slide clearance is applied once per side and automatic drawer depth respects
  the front and rear setbacks;
- impossible drawer width, depth, and height settings are rejected.
- handles follow front orientation and fit within their owner front;
- hinge counts distribute automatically or use the requested count;
- every enabled drawer slide pair shares the drawer index and owner front key;
- impossible handle, hinge-cup, and slide sizes are rejected.
- selected SonVu cabinets take precedence over whole-model Phase 3A scanning;
- aggregation never combines different material, dimension, grain, or edge data;
- invalid production metadata is skipped with a Vietnamese warning;
- report HTML escapes model-provided names and separates boards from hardware.
- both Phase 3B documents begin with a UTF-8 BOM and use CRLF CSV rows;
- commas, quotes, and Vietnamese model text survive CSV round-tripping;
- model-provided cells beginning like spreadsheet formulas are apostrophe-prefixed;
- export creates separate board and hardware files without stale temp files.
- material area applies waste exactly once while edge/hardware quantities do not;
- aggregated costs allocate back to cabinet occurrences and sum to project total;
- invalid percentages and negative/non-numeric prices are rejected in Vietnamese;
- quotation CSV contains line items, cabinet totals, and project subtotals.
- sheet SVG coordinates match Phase 4A placements and escape all model text;
- trim, rotation, and grain direction remain visible in every Phase 4B map.
- Phase 4C HTML is self-contained and its CSV includes placed/unplaced parts;
- formula-like model text is neutralized in every spreadsheet export.

Pure Ruby tests cannot prove SketchUp boolean behavior, actual face winding, or
toolbar appearance. Perform a manual SketchUp smoke test after geometry or
placement changes.

## 10. Manual SketchUp smoke test

1. Restart SketchUp to clear old command registrations. Confirm the `SonVu Nội
   thất` toolbar and its cabinet icon appear.
2. Open `Thiết kế nội thất > Trung tâm nội thất`. Confirm its counts refresh
   after changing selection, unavailable actions are disabled, license state is
   visible, and Bước 5 opens `Xem trước gia công CNC` when boards are available.
3. From the dashboard, create a cabinet and confirm the wizard has four tabs:
   Bước 1 for the carcass, then three Bước 2 sections for fronts, drawers, and
   hardware. No customer-facing screen should display `Phase` or `Giai đoạn`.
   Confirm Back/Next navigation and the direct edit buttons open the intended tab.
4. Open `Thiết kế nội thất > Tạo tủ nội thất`, exercise all four Vietnamese
   presets, and place each cabinet at a clicked point.
5. In Entity Info and Outliner, confirm the cabinet is one group and its panels
   are individually named components. Check rear panel, shelves divided by
   vertical partitions, plinth position, material, and grain/edge attributes.
   Exercise every Vietnamese front layout; confirm overlay/inset gaps, separate
   front material, automatic grain, four-edge metadata, and negative local-Y
   placement for overlay fronts versus flush-front placement for inset fronts.
   For drawer layouts, enable `Tạo hộp ngăn kéo` and confirm every drawer has
   two sides, an inner front, a back, and a bottom; confirm the separate drawer
   material and the same `drawer_index` on the front and its five box panels.
   Enable the Phase 2C options and confirm one handle per front, circular hinge
   cup templates on hinged doors/flaps, and one left/right slide pair per drawer.
   Confirm hardware uses its own material and carries `owner_part_key`. Open
   Bước 5, verify hinge cups appear on Mặt B with valid X/Y/diameter/depth, and
   confirm refreshing or closing the preview does not change model entities.
   Click `Xuất gói CNC`, confirm one DXF per displayed panel face plus
   `nguyen_cong.csv`, inspect the millimetre coordinates in a DXF viewer, and
   verify a plan with red `Cần kiểm tra` operations cannot be exported. Export
   again to confirm replacement, then choose an existing unrelated `_cnc`
   folder and confirm the plugin refuses to replace it.
6. Select one or more cabinets and run `Danh sách chi tiết`. Confirm only the
   selected cabinets are counted, board and hardware tables are separate, and
   identical parts have the expected quantity. Clear the selection and rerun to
   confirm all SonVu cabinets in the model are counted.
7. Click `Xuất CSV`, choose `cong_trinh.csv`, and confirm the output names are
   `cong_trinh_chi_tiet_van.csv` and `cong_trinh_phu_kien.csv`. Open both in
   Excel, verify Vietnamese text and columns, then export again and verify the
   overwrite confirmation appears.
8. Click `Dự toán chi phí`, enter material prices per m², waste percentage,
   edge price per metre, and hardware unit prices. Calculate and verify the
   material/edge/hardware subtotals, each cabinet total, and project total.
   Reopen the dialog to confirm prices persist, then export and open the
   quotation CSV in Excel.
9. Click `Tối ưu cắt ván`, calculate a layout, and confirm each material and
   thickness has separate sheet tabs. Verify colored parts, trim boundary,
   grain arrows, hover details, zoom controls, and the collapsible coordinate
   table. Change the stock size to force multiple sheets and confirm navigation.
   Click `Xuất phương án`, confirm both `_phuong_an_cat.html` and
   `_toa_do_cat.csv` are created, print the HTML to PDF, open the CSV in Excel,
   then export again and verify overwrite confirmation.
10. Move and rotate a generated cabinet, select it, run `Chỉnh sửa tủ đã chọn`,
   change dimensions, and confirm the transform is preserved. Add an unrelated
   entity inside the cabinet group before editing and confirm it is preserved.
11. Undo once and confirm the whole creation or edit operation is reverted.
12. Create a rectangular board and select exactly one face.
13. Create a mortise and confirm edge offsets, flush surface, inward depth, and
   excessive-depth rejection.
14. Open a solid group/component for editing, select an edge face, and create
   tenons. Confirm outward projection, requested shoulder radius,
   single-tenon centring, equal multi-tenon gaps/margins, and a single manifold
   union result.
15. Confirm a hidden backup exists and the union result keeps the original part
   name where possible.
16. Undo once and confirm the complete union operation is removed.
17. Run cleanup and confirm the CNC board result is not deleted.

## 11. Customer RBZ packaging

The RBZ is a ZIP archive with a `.rbz` extension. Required root structure:

```text
sonvu_cnc_plugins.rb
sonvu_cnc_plugins/
  main.rb
  ...
```

Before distribution:

1. Run tests and syntax checks.
2. Stage the loader and plugin folder without altering the development tree.
3. Exclude nested `.git/`, `dogbone_joinery/test/`,
   `furniture_builder/test/`, staging artifacts, `shared/licensing/test/`, and
   `shared/licensing/tools/`.
4. Inspect archive paths. Compressing individual files can flatten directories
   and break `require_relative` and icon paths.
5. Calculate and publish SHA-256.

The artifact under `dist/` is not a source-of-truth replacement for development
files.

## 12. Adding a feature

Create a dedicated subfolder under `sonvu_cnc_plugins/` and namespace it below
`SonVu::CNCPlugins`. A feature normally contains commands, dialog, geometry,
optional placement tool, icons, and tests.

Then:

1. Add feature loading in `main.rb`.
2. Register commands through one reload-safe entry point.
3. Define local-coordinate and unit contracts before geometry implementation.
4. Keep calculations testable without SketchUp wherever possible.
5. Tag generated groups and use an atomic model operation.
6. Update this guide whenever architecture or invariants change.

## 13. Known limitations and refactoring candidates

- Furniture Builder Phase 2C creates simplified handle, hinge-cup, and drawer-
  slide templates. Phase 5A converts hinge cups to validated preview operations
  but does not drill/cut panels. Handle and slide drilling requires future
  manufacturer templates. Door profiles and room/wall placement remain later work.
- Phase 5C exports controller-neutral per-face DXF and an operation manifest.
  It does not select tools, calculate feeds/speeds, mirror for machine setup,
  emit G-code, or provide controller-specific postprocessors.
- Phase 4C exports layout reports and coordinates only. It does not calculate
  saw-cut sequences, reuse offcuts, optimize across different stock sizes, or
  emit CNC toolpaths. Those outputs remain later phases.
- New furniture uses the model axes. Arbitrary wall-aligned placement and a
  rotation preview are not yet implemented.
- Shelves are distributed equally by row. Per-compartment custom shelf heights
  are not yet implemented.
- Native inputbox configuration is positional and easy to desynchronize.
- Model depth uses total connected-geometry projection, not local thickness at
  every mortise corner.
- Complex concave faces are bounded mainly through projected dimensions; future
  support should classify every profile point against the actual face.
- Boolean cutting needs more SketchUp-version and editing-context testing before
  promotion to a primary workflow.
- Version metadata is duplicated between the root loader and `version.rb`; a
  release build should eventually source one value.

## 14. Furniture Builder Phase 1, 2A, 2B, and 2C contract

Production code lives in `SonVu::CNCPlugins::FurnitureBuilder`. Presets and
`Specification` use millimetres only. `Geometry` is the conversion boundary to
SketchUp internal lengths.

Local cabinet coordinates are:

```text
X = cabinet width, left to right
Y = cabinet depth, front to back
Z = cabinet height, bottom to top
```

Overlay fronts occupy negative local Y so their rear face is flush with the
carcass front plane at `Y = 0`. Inset fronts begin at `Y = 0` and extend into
the cabinet, leaving their front face flush with the carcass. Overlay fronts use
a perimeter gap around the cabinet width and the usable height above the
plinth. Inset fronts additionally move inside the side/top/bottom panel
thickness. Adjacent doors and drawer fronts use exactly one internal
`front_gap_mm`.

The cabinet is a tagged top-level group. Each generated board is an individual
component instance with the same SonVu attributes on both its instance and
definition. Stable metadata keys include cabinet ID, part key, Vietnamese part
name, part role, finished length/width/thickness in millimetres, material, grain
direction, `grain_axis`, and four edge-banding flags. `grain_axis` is `length`
or `width` and states which finished dimension must follow the sheet grain.

Phase 2A front components use `part_kind = front`, their own material and grain
settings, and all four edge-banding flags when requested. Door fronts use
vertical automatic grain; drawer and flap fronts use horizontal automatic
grain. Saved Phase 1 settings without any Phase 2A keys normalize to
`front_layout = khong_canh`, preventing unexpected geometry when old cabinets
are edited.

Phase 2B drawer boxes are enabled only for layouts containing drawer fronts.
Every drawer creates five `part_kind = drawer_box` components: left side, right
side, inner front, back, and bottom. Box outer width is the cabinet's inner
width minus twice `drawer_side_clearance_mm`; this setting is explicitly the
clearance for one side. The box begins at `drawer_front_setback_mm`. A depth of
zero means automatic depth:

```text
drawer depth = usable cabinet depth - front setback - rear clearance
```

The face front and all five box panels share a one-based `drawer_index`.
Drawer-box panels use their own material setting and retain finished dimensions
in millimetres. Saved Phase 2A settings without drawer keys normalize with
`include_drawer_boxes = false`, preventing unexpected boxes when old cabinets
are edited.

Phase 2C hardware uses `part_kind = hardware` and a separate material. One
handle is generated per front: vertical on opening doors and horizontal on
drawer/flap fronts. Hinge cups use explicit circular prism geometry along local
Y; they are positioned from the hinge edge and distributed between the two end
offsets. `hinge_count = 0` selects 2–5 hinges according to door height (flaps
use two). Drawer slides are generated as left/right box templates inside the
per-side slide clearance; `drawer_slide_length_mm = 0` follows drawer depth.

Every hardware component stores `hardware_type`, `owner_part_key`, and, when
applicable, the same one-based `drawer_index` as its drawer front. Hardware is
non-destructive: it never drills, cuts, or unions with a board. Saved Phase 2B
settings without hardware keys normalize all three hardware switches to false,
preventing unexpected accessories when old cabinets are edited.

The stored JSON settings are authoritative for editing. Rebuild operations erase
only component instances tagged as SonVu furniture panels; they must not clear
the cabinet group's other entities. Creation and rebuild remain single atomic
SketchUp operations.

## 15. Furniture Builder Phase 3A cut-list contract

`CutList` is read-only and must never open a model operation or write entity
attributes. Scope resolution first searches the current selection recursively.
When that search finds no tagged SonVu cabinet, it recursively searches the
model root. A found cabinet is treated as one physical occurrence and traversal
stops at its boundary so user-added nested geometry is not counted.

Only direct component instances carrying `furniture_panel = true` inside a
tagged cabinet are reportable. Instance attributes take precedence, with the
component definition as a compatibility fallback. Entries missing a positive
finished length, width, or thickness are skipped and reported as Vietnamese
warnings rather than crashing the whole report.

Board aggregation keys are kind, rounded finished dimensions, material, grain,
grain axis, and all four edge-banding flags. Hardware aggregation uses kind, canonical
hardware type, rounded dimensions, material, and geometry shape. Left/right
drawer slides share the canonical `Ray ngăn kéo` type. Aggregation may combine
identical parts across cabinets, while the row retains all cabinet names and
IDs. The dialog renders boards and hardware in separate tables and escapes all
model-provided text. Phase 3A does not export files; that boundary is reserved
for Phase 3B.

## 16. Furniture Builder Phase 3B CSV contract

CSV export is initiated only by the user from the cut-list dialog. The save
panel accepts a base name such as `cong_trinh.csv`; the exporter removes that
final extension and writes exactly two sibling files:

```text
cong_trinh_chi_tiet_van.csv
cong_trinh_phu_kien.csv
```

Both documents use standard comma-separated quoting, CRLF row endings, and a
UTF-8 BOM so Vietnamese text is detected correctly by Excel. The board file
contains category, name, quantity, finished dimensions, material, grain, grain
axis, four edge flags, cabinet names, and cabinet IDs. The hardware file contains name,
quantity, finished dimensions, material, cabinets, cabinet IDs, drawer indices,
and owner part keys.

Model-provided text beginning with `=`, `+`, `-`, or `@` (including after
leading spaces/tabs) is prefixed with an apostrophe to prevent spreadsheet
formula injection when customers open the export.

`CutListCSVExporter` first produces both payloads and temporary sibling files,
then moves them to their final paths. The dialog must ask before replacing any
existing output. Export never changes the SketchUp model or opens a model
operation. Native `.xlsx`, costing, optimization, and CNC output are outside
the Phase 3B contract.

## 17. Furniture Builder Phase 3C costing contract

Phase 3C consumes the aggregated Phase 3A report. Board material is priced by
finished rectangular area in square metres with `waste_percent` applied exactly
once. Edge length maps the `front` and `back` flags to finished length and the
`left` and `right` flags to finished width. Edge banding is priced per metre.
Hardware is priced per item. All prices are VND and must be finite,
non-negative numbers; waste must remain between 0% and 100%.

Aggregation retains `cabinet_breakdown` by physical cabinet occurrence. Each
row cost is linear per item, so its total is allocated back according to the
quantity owned by each occurrence. The sum of cabinet totals must equal the
project total. Repeated component occurrences may share a cabinet ID but retain
separate occurrence keys for correct allocation.

The catalog stores waste, edge price, material prices, and hardware prices in
SketchUp preferences only after the user calculates. It must not write pricing
into model entities. The costing dialog is opened explicitly from the Phase 3A
report and displays board, hardware, cabinet, and project totals.

Quotation export is one UTF-8 BOM CSV containing cost line items, totals by
cabinet, material/edge/hardware subtotals, and the project total. It follows the
same CRLF, quoting, overwrite-confirmation, temporary-file, and spreadsheet-
formula-safety rules as Phase 3B. Labor, tax, discounts, native `.xlsx`, sheet
nesting, and CNC output remain outside Phase 3C.

## 18. Furniture Builder Phase 4A sheet-optimization contract

`SheetOptimizer` consumes only `board_rows` from the Phase 3A report and never
opens a model operation or writes SketchUp entities. Each aggregated row is
expanded by quantity, then grouped by exact material name and rounded thickness.
Hardware never enters the optimizer.

The stock sheet uses millimetres. Configurable values are sheet length/width,
equal trim on all four edges, saw kerf, minimum part spacing, 90-degree rotation,
and grain enforcement. The effective gap between parts is the larger of kerf
and requested spacing. Every placed rectangle must stay inside the trimmed
usable area and every pair must remain separated by that gap.

When grain enforcement is enabled, a grained part with `grain_axis = length`
keeps its finished length along the sheet length. A `width` axis requires the
90-degree orientation; it is reported as unplaced if rotation is disabled.
Ungrainable or legacy rows default to the length axis. Disabling grain
enforcement permits normal rotation where enabled.

Packing is deterministic: items are ordered by descending area and dimension,
then placed through a MaxRects-style best-fit free-rectangle search. Identical
reports and settings must produce identical sheet assignments and coordinates.
The result contains group/sheet totals, placements, utilization, waste area,
and Vietnamese reasons for unplaced parts. This is a practical heuristic, not
a guarantee of the mathematical minimum number of sheets.

Settings are persisted in SketchUp preferences only after successful
calculation. The Phase 4A engine does not render or export layouts and never
writes the model; Phase 4B consumes its result for display.

## 19. Furniture Builder Phase 4B visualization contract

`SheetLayoutSVG` is a pure renderer. It receives one finalized Phase 4A sheet
and the normalized stock settings, then emits one self-contained SVG whose
`viewBox` uses the stock dimensions in millimetres. Part rectangles use the
optimizer's `x`, `y`, `placed_length_mm`, and `placed_width_mm` without further
packing or coordinate changes. The dashed usable-area boundary represents the
equal edge trim.

Every rendered part has a deterministic color, its stable expanded item ID,
rotation state, an escaped tooltip, and—when space permits—an escaped name and
finished dimensions. Grained parts show an arrow along the original
`grain_axis` after applying the placement's 90-degree rotation. Tiny parts may
omit visible labels or arrows, but their tooltip and rectangle must remain.

The Phase 4B dialog provides material/thickness groups, sheet tabs, 50–250%
client-side zoom, a reset-to-fit control, hover highlighting, a Vietnamese
legend, and the Phase 4A coordinate table in a collapsible section. The first
sheet in each group is visible initially; changing tabs or zoom never calls
Ruby and never changes optimization data.

All model-provided names are HTML-escaped in both SVG and surrounding markup.
The renderer and dialog remain read-only: no SketchUp operation, entity write,
file export, network request, or external JavaScript dependency is permitted.
Layout export, printable reports, saw sequencing, and CNC files remain outside
Phase 4B.

## 20. Furniture Builder Phase 4C export contract

Export is available only after a successful optimization and only when the
user explicitly clicks `Xuất phương án`. A chosen base path has a final `.html`,
`.htm`, or `.csv` extension removed, then produces exactly two sibling files:

```text
<base>_phuong_an_cat.html
<base>_toa_do_cat.csv
```

The dialog must list existing targets and obtain overwrite confirmation before
writing either file. Both payloads are built first and written through unique
temporary sibling files before being moved to their targets. Temporary files
are removed on success or failure where possible. Export never opens a model
operation or changes SketchUp entities.

The HTML document is UTF-8, self-contained, dependency-free, and printable on
A4 landscape. It embeds one Phase 4B SVG per sheet plus project settings,
summary totals, material/thickness headings, per-sheet coordinate tables, and
all unplaced-part warnings. Model-provided text must be HTML-escaped. Its only
scripted action is the local `window.print()` button.

The placement document uses quoted comma-separated fields, CRLF rows, and a
UTF-8 BOM for Excel. Every expanded item appears exactly once, including
unplaced items. Fields include status, material group, stock settings, sheet,
item ID/name/category, original size, placement coordinates and size, rotation,
grain direction/axes, cabinet names, and unplaced reason. Model-provided cells
that look like spreadsheet formulas use the Phase 3B apostrophe protection.

The pair is a production handoff, not CNC machine code. Saw sequencing, offcut
inventory, DXF, G-code, and router toolpaths remain outside Phase 4C.

## 21. Furniture Builder unified UI contract

`DashboardState` is pure Ruby. It converts the current Phase 3A report, exact
editable selection, license view, and plugin version into display metrics and
action enablement. `Dashboard` performs the SketchUp inspection and renders
`DashboardHTML`; opening or refreshing it must not start a model operation or
change entities. Every callback delegates to an existing licensed command, so
the command remains the final authorization and validation boundary even when
the displayed dashboard state is stale.

The dashboard is available from the first item of the `Thiết kế nội thất`
submenu. The `SonVu Nội thất` toolbar presents Dashboard, Create, Edit, Cut
List, Cost Estimate, Sheet Optimization, and CNC Preview in workflow order, with separators
between navigation, modeling, and production commands. Every command has its
own SVG icon and Vietnamese tooltip. Registration must be reload-safe. The
dashboard remains visible without a valid license so the user can see status
and open license management; all production actions are then disabled. Step 5
is enabled only when the licensed report contains board parts.

The create/edit `DialogHTML` contains four client-side sections: `carcass`,
`fronts`, `drawers`, and `hardware`. All fields remain in one form and one
submission payload, preserving the existing specification and geometry
contracts. `initial_section` only controls the initially visible tab. Unknown
values normalize to `carcass`. Phase 1–4 report, costing, optimization, and
export dialogs remain separate focused dialogs and the legacy menu commands
remain available.

## 22. Furniture Builder Phase 5A machining-preview contract

`MachiningPlanner` is pure Ruby and machine-independent. It rebuilds the saved
`Specification.parts` for each selected cabinet, or every cabinet when none is
selected. Every non-hardware part receives finished dimensions, cabinet-local
source origin, and explicit length/width/thickness axes. Front panels use
length=Z, width=X, thickness=Y. CNC preview coordinates use X along finished
length and Y along finished width, measured from the lower-left production
origin without postprocessor mirroring.

Only `hinge_cup` is a supported machining operation in Phase 5A. Its circular
pocket is assigned to Face B (the rear/max-Y face of a front), with center X/Y,
diameter, and depth in millimetres. Validation rejects non-positive diameter or
depth, depth beyond panel thickness, and any circle crossing a panel boundary.
Handles and drawer slides remain placement references and produce Vietnamese
warnings because their manufacturer-specific hole spacing is unknown.

`MachiningPreviewHTML` renders only panels containing operations as self-
contained SVG maps and an auditable coordinate table. Model text is escaped.
Planning, opening, and refreshing the preview are read-only: they must never
start a SketchUp operation, alter entities, write files, or contact a network
service. DXF, G-code, tool selection, feeds/speeds, drilling cycles, and
controller-specific coordinate transforms remain outside Phase 5A.

## 23. Furniture Builder Phase 5B machining-rule contract

`MachiningRules` provides Vietnamese production presets plus normalized custom
millimetre settings. The standard 18 mm preset enables dowel holes, cam
pockets, 32 mm shelf-pin rows, and back grooves. A dowel-only preset disables
cam pockets; a hinge-only preset preserves the Phase 5A view. Valid settings
are saved to SketchUp preferences only after a successful recalculation.

Rule-derived face operations use the same panel coordinate frames as Phase 5A:

- dowel holes are placed on the inner faces of left/right sides at top and
  bottom joint centers, using configurable front/rear offsets;
- cam pockets are placed on the inner faces of top/bottom panels near both side
  edges and at matching front/rear offsets;
- shelf-pin rows use configurable diameter, depth, pitch, margins, and
  front/rear offsets. Side panels receive their inner face; dividers receive
  both Face A and Face B;
- back grooves run along the finished length of both sides, top, and bottom,
  with configurable width, depth, and rear offset.

Circular and rectangular operations must remain inside finished panel bounds
and cannot exceed panel thickness. Circular operations from opposite faces are
also compared: if their projected circles overlap and combined depths exceed
the panel thickness, both operations are invalid and a Vietnamese warning is
shown. This is especially important for aligned shelf-pin rows on thin
dividers.

The Step 5 dialog renders a separate map/table for every machined panel face,
shows per-operation-type totals, and accepts rule recalculation through one
JSON callback. It remains read-only with respect to the SketchUp model. Edge
boring, mating-hole generation, manufacturer hardware catalogs, DXF, G-code,
feeds/speeds, and controller postprocessors remain outside Phase 5B.

## 24. Furniture Builder Phase 5C neutral-export contract

`MachiningExporter` accepts only a non-empty project whose operations are all
`ready`. If even one operation is invalid, the entire package is rejected so a
partial job cannot silently reach production. It is a pure document builder
until the user explicitly clicks `Xuất gói CNC`; neither document generation
nor file writing starts a SketchUp operation or mutates model entities.

The selected base path produces one plugin-owned `<base>_cnc` directory. Each
machined panel face receives a deterministic, ASCII-safe, indexed `.dxf` file.
DXF files declare `$INSUNITS=4`, use the preview's lower-left X/Y millimetre
frame without mirroring, include a closed `PANEL_OUTLINE` polyline, and encode
circles or rectangular grooves on operation layers containing type, diameter
or width, and depth. The package also contains `nguyen_cong.csv` with a UTF-8
BOM, quoted fields, CRLF rows, and one row per ready operation. Formula-like
model text receives the same apostrophe protection as other CSV exports.

A private marker identifies directories created by this exporter. Replacement
requires an explicit confirmation and is allowed only when that exact marker
is present. The replacement is staged in a unique sibling directory and the
previous owned directory is backed up until the staged package is moved into
place. Unmarked directories and existing non-directory paths are never
replaced.

The package is intentionally controller-neutral. It contains no G-code,
tool/feed/speed choices, drilling cycles, work-offset selection, setup
mirroring, or postprocessor assumptions.

## 25. Dogbone automatic-planning contract

`DogboneJoinery::AutomaticPlanning` is a read-only sibling of the existing
manual mortise/tenon workflow. It never opens a SketchUp operation, writes an
attribute, generates a group, cuts a solid, or calls the manual geometry
generators. The existing manual command paths in `Commands`, together with
`Dialog`, `PlacementTool`, and `Geometry`, remain behaviorally unchanged and
authoritative for customer-triggered geometry.

`SketchupBoardScanner` accepts only visible, valid Groups and
ComponentInstances. It recursively descends assemblies, composes nested and
active-path transformations, and emits world-space `BoardDescriptor` values.
Instance paths and persistent IDs remain distinct even when component
definitions are shared. Direct loose Faces and Edges are ignored.

Bounding boxes are broad-phase only. `ContactDetector` requires coplanar face
polygons and calculates their actual projected intersection. Only
edge-face-to-broad-face overlap is supported. Edge-to-edge, broad-to-broad,
line-only, point-only, below-tolerance, and non-contact cases are diagnostics,
not proposed connections.

Geometry is the default assignment source: the edge-face board is male and the
broad-face board is female. Reliable `part_role` metadata may produce a
separate suggestion, especially for cabinet backs, but never silently changes
the default. T joints are interior contacts; L joints touch the receiving broad
face boundary and are reversible when the swapped receiver can accept the
requested joint thickness.

`JointLayoutSpecification` is unit-agnostic. Its caller must convert UI
millimetres to model units before analysis. `JointLayoutCalculator` preserves
the requested count, reports maximum feasible count, and creates no partial
joint instances for an invalid connection. Both mating sides use the same
axis starts, ends, and center objects.

`PreviewPlan` and its child values remain immutable or copy-on-write so a
future advanced workflow can reuse them. The compact bulk UI does not expose
per-connection enablement, joint enablement, selection, or assignment reversal.
`BulkPreviewAnalyzer` filters the core analyzer result into valid connection
plans plus lightweight skipped records. A failed connection never produces a
partial joint list and never blocks unrelated valid connections.

The `Tạo mộng tự động` menu/toolbar command resolves the current selection and
opens one `UI::HtmlDialog` session per model. The JavaScript layer performs no
layout calculations; explicit JSON callbacks delegate every recalculation to
the existing `Analyzer`. All user-facing dimensions are millimetres and are
converted only by `PreviewSettingsParser`/`PreviewStateSerializer` at the UI
boundary.
The dialog never accepts one global joint thickness. `JointDimensionResolver`
stores the detected male-board thickness, resolved tenon thickness, matching
mortise opening, total fit clearance and shared local thickness axis in every
joint plan. Mixed 17/18 mm boards therefore remain distinct through preview and
execution.

`PreviewOverlayTool` uses only `View#draw` and renders every valid connection at
once. Solid-line blue tenon prisms and dashed orange mortise cavities remain
distinguishable without per-joint labels. Invalid and unsupported contacts are
absent from the viewport and represented only by grouped skipped counts.
`PreviewDisplaySettings` contains only global tenon, mortise, contact-region,
and legend visibility.

A model observer and transformation snapshots mark the plan stale after model/edit
context changes. Closing the dialog, pressing Escape, changing tools, or
closing the model removes the observer/tool/overlay. `Tạo mộng` snapshots the
validated plan and settings, disables the dialog, and synchronously calls
`AutomaticJointGeometryExecutor`.

The executor does not rerun analysis. It validates model identity, persistent
IDs, stored transformations, settings, placements and duplicates before model
mutation. It sorts connection/joint IDs, makes only shared selected instances
and shared active edit contexts unique, maps the stored world placements into
the solids' parent contexts, then delegates tenon union and mortise subtraction
to `dogbone_joinery/geometry.rb`. The batch owns one operation; delegated
geometry uses `manage_operation: false`. Success commits and closes the preview;
any unexpected failure aborts the whole batch and marks the preview stale.

Automatic mortises are fixed to the existing manual vertical T-bone profile.
The compact dialog and automatic settings contain no mortise/tenon style
selector. `VerticalTBoneGeometry` centralizes cutter offset and feasibility for
the manual profile, board-local preview relief markers, and per-connection
planning skips. Legacy style fields are accepted as unknown payload data and
are not persisted. Manual mortise choices are unchanged.

Repeated-run detection is not implemented. See
`dogbone_joinery/automatic_execution/README.md` and run the adjacent developer
SketchUp 2023 checklist manually before release.
