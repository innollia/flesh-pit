# artgen

Procedural generator for every image asset in [docs/asset-list.md](../../docs/asset-list.md).

The markdown table is the single source of truth. Add a row there, re-run, and the
asset appears. Nothing is hardcoded per-asset in a way that a new row cannot reach.

## Run

```powershell
python tools\artgen\build.py                    # render all 384 files
python tools\artgen\build.py --only STO,ICO     # one or more id groups
python tools\artgen\build.py --report           # list assets on the fallback recipe
python tools\artgen\build.py --index-only      # rewrite the manifest from disk, no render
python tools\artgen\build.py --contact          # also write contact sheets
python tools\artgen\build.py --clean            # wipe assets/ first (destructive)
python tools\artgen\build.py --contact-only     # rebuild contact sheets only
```

`--index-only` is the fast one: it rescans the manifest and contact sheets in a
couple of seconds without touching a pixel. Use it after a partial render.

Requires Python 3.11+, `pillow`, `numpy`. Nothing else, no network.

## Outputs

| Path | What |
| --- | --- |
| `assets/ui/hud/` | stomach, depth, compass, canary HUD |
| `assets/ui/icons/` | tissue icons and legend |
| `assets/ui/codex/` | codex UI |
| `assets/ui/menu/` | menu and settings |
| `assets/ui/prompts/` | tutorial prompts |
| `assets/ui/panels/` | death, restroom panels |
| `assets/ui/acc/` | accessibility variants |
| `assets/art/hands/` | first person hands |
| `assets/art/band-cards/` | depth band cards |
| `assets/art/codex/` | codex specimen portraits |
| `assets/art/loading/` | loading screens |
| `assets/textures/{flesh,tissue,restroom,infra,utility}/` | world maps |
| `assets/vfx/` | flipbook strips |
| `assets/brand/` | logo, capsules, achievements |
| `docs/asset-manifest.csv` | id, group, priority, recipe, file, width, height |
| `docs/asset-manifest.json` | same, grouped, used by the contact sheets |
| `tools/artgen/contact/` | one contact sheet per group, plus `_all.png` |

Contact sheets composite over a checkerboard so transparency is visible.

## Modules

| File | Responsibility |
| --- | --- |
| `palette.py` | colour tokens. Every value traces to a line in the docs |
| `noise.py` | tileable value noise, fbm, worley, ridged, gradients, sobel normals |
| `specs.py` | parses `asset-list.md` into `Asset` records, resolves sizes, frames, 9-slice borders |
| `materials.py` | world surfaces: albedo + height + roughness from one field set |
| `recipes.py` | UI, hands, key art, VFX, brand. `RECIPES` maps name to function, `BY_ID` maps asset id to recipe |
| `build.py` | dispatch, file layout, PNG writing, contact sheets, manifest |

## How an asset is routed

1. group `TEX` and id present in `materials.TEX_MAP` -> a world surface, rendered
   as albedo / normal / roughness / mask / flow from the same height field
2. otherwise `recipes.pick_recipe` -> explicit hit in `recipes.BY_ID`
3. otherwise group `VFX` -> flipbook
4. otherwise the keyword-driven `generic` fallback

`--report` prints every id that landed on the fallback. Those are the ones worth
promoting into `BY_ID` when the art direction firms up.

### Adding a bespoke recipe

```python
def r_my_widget(a):
    w, h = a.w, a.h
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ...                                    # draw with PIL or numpy
    return _to_np(img)                     # -> float RGBA, 0..255
```

Register it in `RECIPES`, then point an id at it in `BY_ID`. Return RGBA, or RGB
for something that is genuinely opaque. Build fills alpha with 255 for you.

## Rules baked into the generator

These come from the canon and should not be quietly relaxed:

- no baked text in UI art. The only assets that contain lettering are the
  brand assets (`BRD-01`, `BRD-02`, `BRD-24`, `BRD-25`), which are the wordmark
- the restroom stays clean and white. The tile branch of `r_texture` is the
  only place white surfaces are generated, and `TEX-206` is the deliberate
  dirty counterpart kept visually distinct from `RST-04`
- nerves are the loudest element. `nerve` in `palette.py` is the highest
  chroma colour in the project and nerve icons get a keyline and a halo
- cosmetic-only assets are marked as such in the source table and must never
  grow a gameplay readout: `TEX-116`, `TEX-313`, `VFX-15`

## Determinism

Every field is seeded from the asset id, so re-running produces byte-identical
output. Change `SURFACES[...]["seed"]` or a `SCALE_OVERRIDE` and only the assets
that depend on it change.
