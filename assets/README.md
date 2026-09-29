# assets

Godot project root. Everything under here is imported by Godot automatically.

The top level is the pipeline split from [docs/asset-scope-2d-3d.md](../docs/asset-scope-2d-3d.md):

| Folder | Pipeline | What lives there |
| --- | --- | --- |
| `2d/` | 2D | UI, illustrations, sprite and flipbook effects |
| `3d/` | 3D | textures consumed by 3D materials, models, shader inputs, in-engine effects |

`3d/textures/*` holds files that are **produced** as flat images but **consumed** by a
3D material. The `2D-TEX` row in the scope CSV is that bucket.

## Layout

```
assets/
  2d/
    ui/
      hud/          STO  stomach gauge
      hud/hands/    HND  hand portraits, stage icons, belly overlay
      icons/        ICO  tissue icons, legend, colour-blind atlas
      codex/        CDX  codex chrome
      menu/         MNU  menu, settings, widgets, font
      prompts/      TUT  tutorial prompts
      panels/       DTH  death and recovery
      acc/          ACC  accessibility variants
    fx/             VFX sprite strips, flesh chunks, decals, gradients
    art/
      depth/        BAND depth band cards
      loading/      LDG loading screens
      codex/        CDX specimen portrait packs
    brand/          BRD logo, capsules, achievements
  3d/
    textures/
      shells/       per shell flesh albedo / normal / roughness
      tissue/       T01..T10 tissue detail, masks, flow maps
      restroom/     the clean white surfaces
      infra/        embedded infrastructure maps
      utility/      noise, flow, grunge
    fx/
      decals/       TEX-309..313
      effects/      VFX strips that are really in-engine effects
    materials/      TEX-107/108/115/117 shader inputs
    models/
      characters/   3D-RIG: hands, canary   (empty, nothing generated)
      props/        3D-MODEL: ladder, hatch, conduit, lift, shell  (empty)
```

`models/` is intentionally empty. A PNG cannot stand in for a rigged hand or a
rusted ladder, so the generator does not fake one. See the scope doc.

## Godot notes

- **Normal maps use OpenGL convention (X+, Y+, Z+).** Godot expects this; a
  DirectX map needs its green channel inverted on import. The generator already
  emits OpenGL style, so do not flip.
- Turn on **Detect 3D** for `3d/textures/**` so Godot picks VRAM compression and
  mipmaps automatically. Leave it off for `2d/**`.
- Texture repeat is on by default. Every file in `3d/textures/` is generated
  seamless, so it tiles without a visible seam.
- Roughness, mask and flow maps are data, not colour. They ship as RGB here and
  get repacked in the import preset.
- 9-slice frames in `2d/ui/**` have their border recorded in the asset list. Set
  it on the `NinePatchRect` node, not in the import preset, so one file can be
  reused at two sizes.

## Two renderers write into this tree

| Renderer | Reads | Style |
| --- | --- | --- |
| `tools/artgen/` | `docs/asset-list.md` | procedural, generated |
| `tools/build_*.py` + `tools/fleshkit/` | hardcoded per group | hand-tuned |

They use different filenames so neither overwrites the other. `fleshkit` does
not read the asset list, so when the design changes the two will drift. Pick one
as canonical before adding new assets.

## Three sets of files live in this tree

| Set | Where | Count | How to tell |
| --- | --- | --- | --- |
| artgen, generated | `2d/`, `3d/` | 338 | listed in `docs/asset-manifest.csv` |
| artgen, 3D shape reference | `2d/art/concept/3d-reference/` | 46 | not assets, see below |
| fleshkit, hand tuned | `ui/`, `vfx/`, `icons/`, `textures/`, `art/`, `brand/`, and 12 PNGs at the root | 258 | everything not in the manifest |

The fleshkit set predates this folder scheme. It has not been moved, because it
is not ours to move. When you are ready, the same scheme applies to it:

| fleshkit | goes to |
| --- | --- |
| `ui/hud/`, `ui/icons/`, `ui/menu/`, `ui/prompts/`, `ui/panels/` | `2d/ui/<same>/` |
| `vfx/` | `2d/fx/` or `3d/fx/effects/`, split by the scope CSV |
| `icons/` | `2d/ui/icons/` |
| `textures/` | `3d/textures/<kind>/` |
| `brand/`, root PNGs | `2d/brand/` |

## `2d/art/concept/3d-reference/`

Not assets. 46 procedurally drawn hands, a canary, ladders, hatches and flipbook
strips that cover rows the scope CSV classes as 3D. The generator stopped
emitting these because a generated picture of a rigged hand looks finished,
which is worse than an empty folder.

Keep them as shape reference for whoever models and rigs the real thing.

## Regenerating

```powershell
python tools\artgen\build.py                    # everything, into this layout
python tools\artgen\build.py --only STO,ICO     # one group
python tools\artgen\build.py --index-only      # refresh the manifest only
```

Output is deterministic: the seed comes from the asset id, so a re-run is
byte-identical. `docs/asset-manifest.csv` lists every file with its size.
