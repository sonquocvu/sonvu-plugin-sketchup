# AGENTS.md — SonVu CNC Plugins

This file applies to all work inside `sonvu_cnc_plugins/`. Read
`DEVELOPMENT.md` before changing geometry, placement, dialog parameters, or
packaging.

## Non-negotiable architecture rules

1. Keep production code inside `SonVu::CNCPlugins`.
2. Keep dog-bone code inside `SonVu::CNCPlugins::DogboneJoinery`.
3. Do not add global methods or plugin-owned global constants.
4. Keep mortise and tenon commands, dialogs, parameters, validation, and
   geometry independent. Shared face-basis code may be reused.
5. Public model mutations must be wrapped in `start_operation`,
   `commit_operation`, and `abort_operation` on error.
6. Mortise normally creates a tagged grouped template. Tenon intentionally
   modifies the selected solid through a confirmed union workflow with a hidden
   backup and atomic Undo. Do not make any other workflow destructive without
   equally explicit authorization and safeguards.
7. UI dimensions are millimetres; convert through `CNCPlugins::Units`.
8. Never infer extrusion direction from `Face#pushpull` winding. Build CNC
   volumes explicitly in the documented local axes.
9. Normalize polygon loops before `Entities#add_face`; repeated closing points
   cause `Duplicate points in array` in SketchUp.
10. Do not reintroduce a combined mortise-and-tenon toolbar command. Customers
    use separate mortise and tenon icons.

## Geometry contracts

- Placement local X follows the longest selected-face edge.
- Local Y lies on the selected face and is perpendicular to X.
- Local Z is the outward face normal.
- Mortise: profile in XY, recess from `Z = 0` to negative Z.
- Tenon: relieved shoulder profile in XZ, extruded through selected-face
  thickness along positive Y.
- CNC-ready tenons are unioned into the solid owning the selected face. Never
  tag the union result as a disposable generated template.
- Mortise and tenon both use the UI term and value semantics `Bán kính dao`.
  Their radius settings remain independent.
- Multiple tenons use a count and symmetric end margin; internal clear gaps are
  calculated automatically and equally.

## Required workflow after code changes

1. Add or update regression tests in
   `dogbone_joinery/test/geometry_test.rb`.
2. Run:

   ```powershell
   ruby sonvu_cnc_plugins\dogbone_joinery\test\geometry_test.rb
   ruby -c sonvu_cnc_plugins.rb
   Get-ChildItem sonvu_cnc_plugins -Recurse -Filter *.rb | ForEach-Object { ruby -c $_.FullName }
   ```

3. Summarize changed files, changed behavior, and manual SketchUp test steps.
4. If refreshing the customer RBZ, preserve this exact archive structure:

   ```text
   sonvu_cnc_plugins.rb
   sonvu_cnc_plugins/...
   ```

   Exclude `.git/`, tests, staging directories, and other development files.

## Change discipline

- Prefer named constants and hash keys over positional array indexes.
- When native `UI.inputbox` arrays change, assert that `PROMPTS`, `DEFAULTS`,
  and `LISTS` have equal lengths and update every parse index.
- When HTML fields change, update field definitions, payload generation,
  defaults, Ruby parsing, validation, settings conversion, labels, and tests as
  one atomic change.
- Keep backward-compatible geometry parameter fallbacks only when they do not
  make mortise and tenon settings depend on each other.
