class_name FPEchoView
extends MeshInstance3D

## T1 echolocation picture (fp_echo.gdshader): a dark lidar-like filter over
## the normal view, with a sphere of line spreading out from the body on each
## tongue click. FPMutationApply starts a pulse and hands over the spots the
## pulse sorted; this only draws. The quad fills every camera that renders its
## layer: the player's eye and the T5 fisheye faces (they copy its mask), never
## the mirror's reflection camera (it leaves HANDS_ROOM_LAYER out).

const LAYER := FPMirrorReflection.HANDS_ROOM_LAYER
const SPEED := 9.0 ## m/s the front travels
const MAX_RADIUS := 10.0
const PERIOD := 1.2 ## s between clicks (FPMutationApply)
const MAX_MARKS := 48
## Order in which sorted spots get the limited mark slots: the rare and
## dangerous first, thin walls (there are many) last.
const PRIORITY := [4, 3, 2, 1, 0] ## TUMOR, NERVE, SQUEEZE, REGROW, THIN

var age := 99.0
var marks_shown := 0
var _mat: ShaderMaterial

func _init() -> void:
	name = "EchoView"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://main/scripts/fp_echo.gdshader")
	_mat.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = _mat
	layers = LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	# never frustum culled: the vertex shader puts it over the whole view
	custom_aabb = AABB(Vector3.ONE * -1.0e5, Vector3.ONE * 2.0e5)
	visible = false

func set_kind_colors(colors: Dictionary) -> void:
	var arr: Array[Color] = []
	for k in range(5):
		arr.append(colors.get(k, Color.WHITE))
	_mat.set_shader_parameter("kind_colors", arr)

## A new click from `origin`.
func pulse(origin: Vector3) -> void:
	age = 0.0
	_mat.set_shader_parameter("origin", origin)
	set_marks([])

## Spots the pulse sorted so far ([{pos, kind}]); the scan runs over a few
## frames, so this is called again as it finds more.
func set_marks(found: Array) -> void:
	var picked: Array[Vector4] = []
	for kind in PRIORITY:
		for e in found:
			if picked.size() >= MAX_MARKS:
				break
			if int(e.kind) == kind:
				var p: Vector3 = e.pos
				picked.append(Vector4(p.x, p.y, p.z, float(kind)))
	marks_shown = picked.size()
	while picked.size() < MAX_MARKS:
		picked.append(Vector4.ZERO)
	_mat.set_shader_parameter("marks", picked)
	_mat.set_shader_parameter("mark_count", marks_shown)

func radius() -> float:
	return minf(age * SPEED, MAX_RADIUS)

func step(delta: float, active: bool) -> void:
	visible = active
	if not active:
		return
	age += delta
	_mat.set_shader_parameter("radius", radius())
	_mat.set_shader_parameter("fade", clampf(1.0 - age / PERIOD, 0.0, 1.0))
