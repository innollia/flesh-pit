class_name FPFisheyeView
extends CanvasLayer

## T5 fish eye (docs/spec/05-mutations.md 4): the eyes move to the sides of
## the head and the view becomes a 200-degree fisheye that bends the world.
## A perspective camera cannot reach past 180 degrees, so five square
## 90-degree cameras follow the player's camera (front, right, left, up,
## down) and fp_fisheye.gdshader maps them onto one equidistant fisheye.
## It sits right above the 3D view, under the PS1 post (20) and every HUD.
## While it draws, the player's own camera renders nothing (cull mask 0 for
## that frame only), so the cost is the five faces, not six views. Aim, reach
## and the hands still follow the player's camera; only the picture changes.

const FACE_SIZE := 320 ## px per face; the PS1 post pixelates to 240 lines anyway
## Under T5 the player camera keeps the settings FOV (FPSettings.base_fov).
## Anything that narrows that camera (the crush squeeze, a hand pose)
## narrows the fisheye by the same ratio; the settings FOV itself does not.
const FACES := {
	"front": Basis.IDENTITY,
	"right": Basis(Vector3.UP, -PI * 0.5),
	"left": Basis(Vector3.UP, PI * 0.5),
	"up": Basis(Vector3.RIGHT, PI * 0.5),
	"down": Basis(Vector3.RIGHT, -PI * 0.5),
}

var source: Camera3D
var fov_deg := 200.0
var cameras := {}
var _rect: ColorRect
var _mat: ShaderMaterial
var _saved_mask := -1

func _init() -> void:
	layer = -10
	name = "FisheyeView"

func setup(cam: Camera3D) -> void:
	source = cam
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://main/scripts/fp_fisheye.gdshader")
	for face in FACES:
		var vp := SubViewport.new()
		vp.name = "Face_" + face
		vp.size = Vector2i(FACE_SIZE, FACE_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.audio_listener_enable_3d = false
		add_child(vp)
		var c := Camera3D.new()
		c.fov = 90.0
		c.keep_aspect = Camera3D.KEEP_HEIGHT
		vp.add_child(c)
		cameras[face] = c
		_mat.set_shader_parameter("face_" + face, vp.get_texture())
	_rect = ColorRect.new()
	_rect.name = "Fisheye"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)
	set_active(false)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_draw)
		RenderingServer.frame_post_draw.disconnect(_after_draw)
	_after_draw()

func set_active(on: bool, fov: float = 200.0) -> void:
	fov_deg = fov
	visible = on
	for c in cameras.values():
		(c.get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		_after_draw()

func is_active() -> bool:
	return visible

## Full horizontal angle drawn this frame.
func live_fov() -> float:
	if source == null or not is_instance_valid(source):
		return fov_deg
	return fov_deg * source.fov / maxf(1.0, FPSettings.base_fov(source))

## Face cameras take the player camera's final pose for this frame (after
## main's terrain eye guard, which is connected earlier) and its layers.
func sync_cameras() -> void:
	if source == null or not is_instance_valid(source):
		return
	var t := source.global_transform
	var mask := _saved_mask if _saved_mask >= 0 else source.cull_mask
	for face in FACES:
		var c: Camera3D = cameras[face]
		c.global_transform = Transform3D(t.basis * FACES[face], t.origin)
		c.force_update_transform()
		c.near = source.near
		c.far = source.far
		c.cull_mask = mask
		c.environment = source.environment
		c.attributes = source.attributes
	var size := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	_mat.set_shader_parameter("fov_deg", live_fov())

func _before_draw() -> void:
	if not visible or source == null or not is_instance_valid(source):
		return
	# the settlement / ending cameras take over the screen: no fisheye there
	_rect.visible = source.is_current()
	if not _rect.visible:
		return
	sync_cameras()
	if _saved_mask < 0:
		_saved_mask = source.cull_mask
		source.cull_mask = 0

func _after_draw() -> void:
	if _saved_mask >= 0 and source != null and is_instance_valid(source):
		source.cull_mask = _saved_mask
	_saved_mask = -1
