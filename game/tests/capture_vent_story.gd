extends SceneTree

## The vent being across a first meeting and the visits after it, played
## through Main's own entry points with real time passing (isolated save).
## Prints a timeline: each player step, then every line actually voiced
## (id | subtitle), so the run reads like a script. No pass/fail: it is
## for reading whether the being makes sense.
##   godot_console --headless --path game --script res://tests/capture_vent_story.gd

var m: Node3D
const SAVE := "user://capture-vent-story.bin"
var _t := 0.0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func wait(seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in range(n):
		await process_frame
		_t += 1.0 / 60.0

func step(what: String) -> void:
	print("\n[%5.1fs] >> %s" % [_t, what])

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func stand_at(p: Vector3, look: Vector3) -> void:
	m.player.global_position = p
	await wait(0.05)
	look_at_point(look)
	await wait(0.05)

func _run() -> void:
	await wait(0.1)
	m.finish_opening()
	m.vent.line_spoken.connect(func(id): print("[%5.1fs]    \"%s\"  (%s)" % [_t, FPSubtitles.line_text(id), id]))
	m.restroom.set_door_open(false, true)
	var vent: Vector3 = FPRestroom.VENT_CENTER
	var under_vent := Vector3(vent.x - 0.5, 0.95, vent.z - 0.5)
	var at_toilet: Vector3 = m.restroom.toilet.global_position + Vector3(0.75, 0.95, 0.0)
	var tank: Vector3 = m.restroom.tank_art.to_global(Vector3(0, 0.3, 0))

	# --- first expedition home: vomit 60 units, flush
	step("first return: vomit into the bowl")
	m.stomach.add_flesh(60.0)
	await stand_at(at_toilet, tank)
	m.request_vomit()
	await wait(4.0)
	step("first flush (R over the bowl)")
	m.flush()
	print("           (teeth in the tank: %d)" % m.progression.teeth)
	await wait(14.0)
	step("ignored it a while; open the vent (empty hands, teeth in the tank)")
	await stand_at(under_vent, vent)
	m.use_vent()
	await wait(6.0)
	step("go to the tank, take the lid off")
	await stand_at(at_toilet, tank)
	await wait(2.0)
	var picked: bool = m.tank_lid.pick()
	await wait(2.5)
	look_at_point(at_toilet + Vector3(0.6, -1.0, -0.6))
	await wait(0.05)
	m.tank_lid.drop()
	look_at_point(tank)
	print("           (lid picked %s, on tank %s, held %s, right hand '%s', carried %.1f)" % [picked, m.tank_lid.on_tank, m.tank_lid.held, m.progression.hands.right, m.carried_flesh])
	await wait(1.0)
	step("scoop every tooth")
	while m.scoop_teeth() > 0:
		await wait(0.12)
	await wait(2.0)
	step("walk to the vent with the teeth (%d)" % m.progression.teeth_in_hand)
	await stand_at(under_vent, vent)
	await wait(2.0)
	step("put them on the lip one by one")
	while m.place_tooth_at_vent():
		await wait(0.12)
	await wait(4.0)
	step("offers: %s; look a while, then take one with F" % [m.vent.offers])
	await wait(5.0)
	look_at_point(m.vent.offer_center())
	m.use_vent()
	await wait(4.0)
	step("close the vent")
	look_at_point(vent)
	m.use_vent()
	await wait(3.0)

	# --- second visit
	step("second visit: vomit, flush, open the vent at once")
	m.stomach.add_flesh(40.0)
	await stand_at(at_toilet, tank)
	m.request_vomit()
	await wait(3.0)
	m.flush()
	await wait(0.5)
	await stand_at(under_vent, vent)
	m.use_vent()
	await wait(5.0)
	step("close with nothing, open again empty-handed twice")
	m.use_vent()
	await wait(1.5)
	m.use_vent()
	await wait(3.0)
	m.use_vent()
	await wait(7.0)
	m.use_vent()
	await wait(3.0)
	m.use_vent()
	await wait(4.0)

	# --- third visit: a small handful, then leave the offer
	step("third visit: only 3 teeth on the lip")
	m.progression.teeth_in_hand = 3
	if not m.vent.is_open:
		m.use_vent()
	await wait(2.0)
	while m.place_tooth_at_vent():
		await wait(0.12)
	await wait(4.0)
	step("offers %s; walk out of the room without taking" % [m.vent.offers])
	await stand_at(Vector3(0.0, 0.95, FPRestroom.HALF.z + 1.2), vent)
	await wait(4.0)
	step("come back")
	await stand_at(under_vent, vent)
	await wait(4.0)
	await wait(5.0)
	step("take one with F")
	look_at_point(m.vent.offer_center())
	m.use_vent()
	await wait(4.0)

	# --- a visit full of other things
	step("fourth visit: flush with teeth, vent left shut; wander instead")
	m.stomach.add_flesh(40.0)
	await stand_at(at_toilet, tank)
	m.request_vomit()
	await wait(2.0)
	m.flush()
	await wait(3.0)
	if m.vent.is_open:
		m.vent.close()
	step("open it, then wash hands at the sink")
	await stand_at(under_vent, vent)
	m.use_vent()
	await wait(3.0)
	await stand_at(m.sink_point() + Vector3(0.5, 0.0, 0.0), m.sink_point())
	await wait(2.0)
	m.wash_hands()
	await wait(4.0)
	step("look in the mirror, sit on the toilet, stand at the door")
	m.vent.notice("mirror")
	await wait(4.0)
	await stand_at(at_toilet, tank)
	m.sit_down()
	await wait(4.0)
	m.stand_up()
	await stand_at(Vector3(0.0, 0.95, FPRestroom.HALF.z - 0.6), Vector3(0.0, 1.0, FPRestroom.HALF.z + 1.0))
	await wait(4.0)
	print("           (door flag %s, open %s, offers %s, wants %s, spoken tail %s)" % [m._vent_flags.get("door"), m.vent.is_open, m.vent.offers, m.vent._wants_teeth(), m.vent.spoken.slice(-4)])
	step("stand idle under the open vent for 14 s")
	await stand_at(under_vent, vent)
	await wait(14.0)
	step("toggle the grate 5 times fast")
	for i in range(5):
		m.use_vent()
		await wait(0.6)
		m.use_vent()
		await wait(0.6)
	await wait(4.0)
	step("open again after it hid; put a hand in")
	await wait(20.0)
	if not m.vent.is_open:
		m.use_vent()
	await wait(3.0)
	m.reach_into_vent()
	await wait(4.0)
	step("spray into the vent")
	m.vent.notice("spray")
	await wait(5.0)
	quit(0)
