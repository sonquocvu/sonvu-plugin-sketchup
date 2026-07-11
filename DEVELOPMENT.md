# SonVu CNC Plugins — Development Guide

This is the primary technical reference for future Codex sessions and human
developers. It describes the current implementation, not an aspirational API.

## 1. Product scope

The extension provides CNC woodworking template generators for SketchUp.
Customer-facing commands are intentionally separate:

- **Tạo mộng âm** creates a recessed dog-bone mortise template on one selected
  model face.
- **Tạo mộng dương** creates one or more outward tenons and unions them into the
  solid owning the selected edge face so CNC exporters see one part.
- **Xóa mẫu mộng đã tạo** deletes groups created and tagged by the plugin.

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
  dogbone_joinery/
    commands.rb                      commands, toolbar, selection workflow
    dialog.rb                        parsing, validation, settings conversion
    dialog_html.rb                   HtmlDialog HTML/CSS/JavaScript
    geometry.rb                      profile and solid construction
    tool.rb                          selected-face local coordinate frame
    icons/                            production icons
    test/geometry_test.rb             SketchUp-free regression suite
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
ruby -c sonvu_cnc_plugins.rb
Get-ChildItem sonvu_cnc_plugins -Recurse -Filter *.rb | ForEach-Object { ruby -c $_.FullName }
```

Tests should cover these invariants:

- no duplicate face points;
- mortise vertices never rise above surface Z;
- tenon reliefs lie in XZ and extrusion lies along Y;
- clearance is applied exactly once;
- rotated face measurements remain correct;
- invalid depth and layouts are rejected;
- one tenon centres and multiple tenons distribute evenly;
- HTML exposes every required feature-specific field.

Pure Ruby tests cannot prove SketchUp boolean behavior, actual face winding, or
toolbar appearance. Perform a manual SketchUp smoke test after geometry or
placement changes.

## 10. Manual SketchUp smoke test

1. Restart SketchUp to clear old command registrations.
2. Create a rectangular board and select exactly one face.
3. Create a mortise and confirm edge offsets, flush surface, inward depth, and
   excessive-depth rejection.
4. Open a solid group/component for editing, select an edge face, and create
   tenons. Confirm outward projection, requested shoulder radius,
   single-tenon centring, equal multi-tenon gaps/margins, and a single manifold
   union result.
5. Confirm a hidden backup exists and the union result keeps the original part
   name where possible.
6. Undo once and confirm the complete union operation is removed.
7. Run cleanup and confirm the CNC board result is not deleted.

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
3. Exclude nested `.git/`, `dogbone_joinery/test/`, and staging artifacts.
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

- Native inputbox configuration is positional and easy to desynchronize.
- Model depth uses total connected-geometry projection, not local thickness at
  every mortise corner.
- Complex concave faces are bounded mainly through projected dimensions; future
  support should classify every profile point against the actual face.
- Boolean cutting needs more SketchUp-version and editing-context testing before
  promotion to a primary workflow.
- Version metadata is duplicated between the root loader and `version.rb`; a
  release build should eventually source one value.
