# Changelog

## 0.3.0

- Textured PS1 look (docs/tone-and-manner.md), replacing flat vertex-colour
  low-poly: FDKPs1Settings (one global on/off + tuning), FDKPs1Material
  (shared nearest-filtered textured material with per-vertex snap-to-grid
  wobble and the chew-press deformation), FDKPs1ScreenPost (screen-space
  post shader: pixelation to a low internal resolution, 4x4 Bayer ordered
  dithering with reduced colour depth, grain). FDKLowPoly.planar_uv_mesh()
  adds planar UVs to any vertex-colour-only mesh so it can wear a texture.
  Terrain now emits one mesh surface per tissue id with world-aligned UVs.
  Textures baked by tools/bake_ps1_textures.py (64/128 px) from this
  project's own generated source pool under assets/3d/textures, or
  procedurally with numpy/PIL when no source exists.
## 0.2.0

- Terrain meshing rewritten as true surface nets: slanted faceted walls
  (one flat normal per triangle, stable per-vertex jitter), vertex colours
  by tissue plus a depth tone, seamless chunk borders (neighbour corners are
  read and shared corners are dug in every chunk that stores them).
- Terrain field: density/tissue samplers for endless generation,
  generate_region(), remesh_all(), per-frame remesh budget, tissue_at(),
  density_at(), is_edible_at() with `inedible_tissues`.
- Chewer refuses inedible tissue and digs through the field (no seams).
- New low-poly hands (FDKHandsRig): palm with thenar pad, fused 4-finger
  block with 3 joints, separate 3-joint thumb with opposition; idle / grab
  (joints curl in order) / chew pull + tremble / tear jerk with torn chunk /
  release / carry pile; walking sway from footstep_bob; joint limits.
- FDKNerveStalk: wriggling yellow nerve that hides when its base is eaten.
- FDKLowPoly mesh helpers and a view-model shader (hands never clip into
  nearby walls).

## 0.1.0

- Initial release: chunked density-grid terrain with low-poly surface-nets
  meshing and tissue vertex coloring, dig/regenerate, concentric-shell
  depth_at().
- Chewing/stomach system: hold-to-tear timing, overfill slowdown, vomit.
- First-person controller: mouse+keyboard look, keyboard-only look
  fallback, crouch, climb, footstep bob, low-poly hand rig.
- Standalone demo scene (addons/flesh_dig_kit/demo/).
