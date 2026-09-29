class_name FDKPs1ScreenPost
extends CanvasLayer

## Full-screen PS1 post-process using SCREEN_TEXTURE (no SubViewport
## reparenting needed): pixelation to a low internal resolution, ordered
## (Bayer) dithering with reduced colour depth, and subtle grain. Instance
## this once anywhere in the scene tree; it reads whatever the 3D viewport
## already rendered above it. Toggle the whole effect off via
## FDKPs1Settings.active.enabled = false (removes/hides this node's effect).

@export var settings: FDKPs1Settings = FDKPs1Settings.active

var _rect: ColorRect
var _mat: ShaderMaterial
var _time: float = 0.0

func _ready() -> void:
    layer = 20
    _rect = ColorRect.new()
    _rect.name = "Blit"
    _rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _mat = ShaderMaterial.new()
    _mat.shader = load("res://addons/flesh_dig_kit/common/fdk_ps1_post.gdshader")
    _rect.material = _mat
    add_child(_rect)
    _apply_settings()

func _apply_settings() -> void:
    visible = settings.enabled
    _mat.set_shader_parameter("internal_height", float(settings.internal_height) if settings.internal_height > 0 else 480.0)
    _mat.set_shader_parameter("dither_levels", settings.dither_levels)
    _mat.set_shader_parameter("grain_amount", settings.grain_amount)

func _process(delta: float) -> void:
    _time += delta
    _mat.set_shader_parameter("time_seed", _time)
