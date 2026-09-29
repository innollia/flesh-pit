class_name FDKDeathDrop
extends Node3D

## On-death belongings drop (docs/spec/07-danger-navigation.md). Holds the dropped inventory at
## the death location; the player can return and recover it. No severe
## penalty for failing to recover -- just the drop itself. Navigation only
## preserves the LAST KNOWN location (no live tracking, no marker update
## after the drop): if the surrounding tissue moves/regenerates and pushes
## the drop, the marker stays where the drop WAS placed, not where it drifts
## to (docs/spec/07-danger-navigation.md: "if the item drifts, the player must search from that
## stale location").
##
## Presentation (marker mesh, on-screen indicator) is frontend scope; this
## node is state + a `carried_along` displacement behaviour only.

signal recovered(items: Dictionary)

## Items dropped on death (game-defined shape; opaque to this node).
var items: Dictionary = {}
## Where the marker points (stays fixed at the moment of death, per
## docs/spec/07-danger-navigation.md -- never updated after drop() is called).
var last_known_position: Vector3 = Vector3.ZERO
## The drop's actual current position, which CAN drift as tissue moves
## (docs/spec/07-danger-navigation.md: "no fixed displacement cap").
var current_position: Vector3 = Vector3.ZERO
var active: bool = false

## The one mark left for the player (07-danger-navigation.md 2): a bent
## steel stake with a dim red lamp, standing where they died. top_level, so
## it stays put while the drop itself is pushed around by the flesh.
var marker: Node3D

func drop(at: Vector3, dropped_items: Dictionary) -> void:
	items = dropped_items.duplicate(true)
	last_known_position = at
	current_position = at
	position = at
	active = true
	_place_marker()

func _place_marker() -> void:
	if marker == null:
		marker = _build_marker()
		add_child(marker)
	marker.top_level = true
	marker.position = last_known_position # top_level: position is world space
	marker.visible = true

func marker_position() -> Vector3:
	return marker.position if marker != null else last_known_position

static func _build_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "LastKnownMarker"
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.4, 0.38)
	steel.roughness = 0.7
	var stake := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.028
	cm.height = 0.7
	cm.radial_segments = 5
	stake.mesh = cm
	stake.material_override = steel
	stake.position = Vector3(0, 0.1, 0)
	stake.rotation_degrees = Vector3(0, 0, 9)
	root.add_child(stake)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.09
	sm.radial_segments = 6
	sm.rings = 3
	lamp.mesh = sm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.9, 0.12, 0.08)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.15, 0.08)
	glow.emission_energy_multiplier = 2.5
	lamp.material_override = glow
	lamp.position = Vector3(-0.05, 0.46, 0)
	root.add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.12)
	light.light_energy = 0.9
	light.omni_range = 2.4
	light.position = lamp.position
	root.add_child(light)
	return root

## Call each tick with the world-space displacement tissue moved this frame
## at the drop's current position (e.g. a chunk regenerating/shifting under
## it). There is deliberately no cap -- docs/spec/07-danger-navigation.md allows unbounded
## drift -- and last_known_position is NOT updated, so the marker goes stale.
func carry_along(displacement: Vector3) -> void:
	if not active:
		return
	current_position += displacement
	position = current_position

## Player recovers the drop by reaching current_position (not the stale
## marker) within pickup_radius. Returns the items, or an empty Dictionary
## if out of range or already recovered.
func try_recover(player_pos: Vector3, pickup_radius: float = 1.2) -> Dictionary:
	if not active:
		return {}
	if player_pos.distance_to(current_position) > pickup_radius:
		return {}
	var out := items.duplicate(true)
	active = false
	if marker != null:
		marker.visible = false
	recovered.emit(out)
	return out

func serialize() -> Dictionary:
	return {
		"version": 1,
		"active": active,
		"items": items.duplicate(true),
		"last_known_position": [last_known_position.x, last_known_position.y, last_known_position.z],
		"current_position": [current_position.x, current_position.y, current_position.z],
	}

func deserialize(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	items = (data.get("items", {}) as Dictionary).duplicate(true)
	var lk: Array = data.get("last_known_position", [0.0, 0.0, 0.0])
	last_known_position = Vector3(float(lk[0]), float(lk[1]), float(lk[2]))
	var cp: Array = data.get("current_position", [0.0, 0.0, 0.0])
	current_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	position = current_position
	if active:
		_place_marker()
	elif marker != null:
		marker.visible = false
