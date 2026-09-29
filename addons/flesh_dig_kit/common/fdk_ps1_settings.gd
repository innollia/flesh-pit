class_name FDKPs1Settings
extends Resource

## Global PS1 look toggle + tuning for the whole kit. One instance is shared
## via FDKPs1Settings.active; set enabled = false to fall back to clean
## rendering (useful for editor work or a "modern" toggle later).

static var active: FDKPs1Settings = FDKPs1Settings.new()

@export var enabled: bool = true
## Vertex snapping grid, in pseudo-pixels of a virtual low-res framebuffer.
@export var vertex_snap_precision: float = 130.0
## Internal render resolution the SubViewport renders at before nearest-
## neighbour upscale (0 = use viewport size unscaled).
@export var internal_height: int = 240
@export var dither_levels: float = 40.0
@export var grain_amount: float = 0.05
@export var fog_distance: float = 11.0
@export var affine_warp: float = 0.6
