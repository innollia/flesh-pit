# STATUS

Single entry point for progress and validation. Updated after every step.

## Step 0-1: skeleton + terrain + eat + player scripts

- Created `game/` git repo (no push, local only).
- project.godot: renderer forced to gl_compatibility (Compatibility).
- addons/flesh_dig_kit/: plugin.cfg + plugin.gd stub (no editor UI yet).
- terrain/: FDKTerrainConfig, FDKChunk (density grid + naive surface-nets
  meshing with unshared per-face vertices for flat low-poly shading,
  vertex color by tissue id), FDKTerrainField (chunk management,
  world<->cell conversion, dig_at/regenerate_all, depth_at() for concentric
  shells, carve_sphere/fill_box_uniform for initial room+wall generation,
  serialize/deserialize).
- eat/: FDKStomachConfig, FDKStomach (fill/overfill/vomit, signals),
  FDKChewer (hold-to-chew timing scaled by overfill, cell_torn signal).
- player/: FDKPlayerConfig, FDKInputActions (registers fdk_move_*,
  fdk_look_* keyboard-only look, fdk_crouch, fdk_eat, fdk_jump in code),
  FDKFirstPersonController (mouse+keyboard look, keyboard-only look
  fallback, crouch, climb via jump/crouch+eat combo, footstep bob signal),
  FDKHandsRig (two low-poly hand meshes, chew-reach animation hook).

## Validation so far

- Not yet run through Godot (scenes not created yet). No exit-code
  verification recorded until the demo scene and test runner exist.

## Next

- Build FDKFirstPersonController.tscn (CharacterBody3D + CollisionShape3D +
  CameraPivot/Camera3D/HandsRig) and the kit demo scene.
- Write the self-test runner (tests/run_tests.gd) and first terrain/stomach
  unit tests.
- Then import/run through Godot with a real exit-code check.

## Holds / questions for 형님

(none yet)
