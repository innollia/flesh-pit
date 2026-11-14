extends SceneTree

## Hair left on a dead body (decision 0017). A death leaves half the coloured
## hairs grown since the restroom on the body; reaching it gives them all
## back, at stake again until the restroom. The body shows them: a mat of
## dark hair on its back and one stalk for every hair to take back.
## Hair numbers are worked out from FPProgression's constants, never written
## in. Real Main; save and key files are this suite's own.

const CorpseArt := preload("res://main/art/fp_corpse_art.gd")
const SAVE := "user://corpse_hair_test_save.bin"

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_corpse_hair.json"
	m.save_path = SAVE
	get_root().add_child(m)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

## Coloured hairs `units` of flesh grow in shell `k`, from a clean carry.
func grown(units: float, k: int) -> int:
	var mult := float(FPProgression.SHELL_MULTIPLIER[FPProgression.BIOMES[k]])
	return int(floor(units * mult / FPProgression.FLESH_PER_BIOME_HAIR + 1e-6))

## Of those, the ones a death leaves on the body.
func left(units: float, k: int) -> int:
	return int(floor(float(grown(units, k)) * FPProgression.DEATH_HAIR_SHARE + 1e-6))

func verts(n: Node) -> int:
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return 0
	return (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

func named(body: Node, part: String) -> int:
	var n := 0
	for c in body.get_children():
		if String(c.name) == part:
			n += 1
	return n

func lamps(n: Node) -> int:
	var out := 1 if n is OmniLight3D else 0
	for c in n.get_children():
		out += lamps(c)
	return out

func _run() -> void:
	for i in range(5):
		await process_frame
	if m.save_path == "user://save.bin":
		m.save_path = SAVE
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	_rules()
	await _bodies()
	_dormant()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("--- corpse hair: %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)

# --- the rule, on a progression of its own ---------------------------------------

func _rules() -> void:
	var common := FPProgression.COMMON
	for k in range(FPProgression.BIOMES.size()):
		var b: String = FPProgression.BIOMES[k]
		var pk := FPProgression.new()
		pk.on_flesh_eaten(k, 100.0)
		var g := grown(100.0, k)
		var ck: int = pk.hairs(common)
		check(g > 0 and pk.hairs(b) == g and int(pk.expedition_hairs.get(b, 0)) == g, "%s: 100 flesh grows %d coloured hairs, all at stake" % [b, g])
		check(not pk.expedition_hairs.has(common), "%s: common hairs are never at stake" % b)
		var pay := pk.take_death_payload(100.0)
		var nk := left(100.0, k)
		check(nk > 0 and int((pay["hairs"] as Dictionary).get(b, 0)) == nk and FPProgression.payload_hairs(pay) == nk, "%s: a death leaves %d of %d on the body (got %s)" % [b, nk, g, str(pay["hairs"])])
		check(pk.hairs(b) == g - nk and pk.hairs(common) == ck, "%s: the player keeps %d, and every common hair" % [b, g - nk])
		check(pk.expedition_hairs.is_empty(), "%s: nothing is at stake after the death" % b)
		check(not FPProgression.payload_empty({"hairs": pay["hairs"]}), "%s: a body with hairs on it is not empty" % b)
		# a saved body comes back with float counts
		var saved: Dictionary = JSON.parse_string(JSON.stringify(pay))
		pk.restore_death_payload(saved)
		check(pk.hairs(b) == g and int(pk.expedition_hairs.get(b, 0)) == nk, "%s: reaching the body gives all %d back, at stake again" % [b, nk])
		check(FPProgression.payload_hairs(saved) == 0 and FPProgression.payload_empty(saved), "%s: and the body is empty" % b)
		# the same flesh in single cells grows the same hair
		var q := FPProgression.new()
		for i in range(50):
			q.on_flesh_eaten(k, 2.0)
		check(q.hairs(b) == g and int(q.expedition_hairs.get(b, 0)) == g, "%s: fifty bites of 2 grow the same %d" % [b, g])
	# what reached the restroom is safe; only what grew after it drops
	var p := FPProgression.new()
	p.on_flesh_eaten(0, 100.0)
	p.bank_expedition_hairs()
	var home: int = p.hairs("core")
	var little := FPProgression.FLESH_PER_BIOME_HAIR / FPProgression.DEATH_HAIR_SHARE - 1.0
	p.hair_carry["core"] = 0.0
	p.on_flesh_eaten(0, little)
	var before: int = p.hairs("core")
	var payload := p.take_death_payload(0.0)
	check(FPProgression.payload_hairs(payload) == 0 and p.hairs("core") == before and before >= home, "hairs that reached the restroom never drop (and one new hair is too few to halve)")
	p = FPProgression.new()
	p.on_flesh_eaten(1, 100.0)
	p.bank_expedition_hairs()
	p.hair_carry["mantle"] = 0.0
	p.on_flesh_eaten(1, 100.0)
	payload = p.take_death_payload(0.0)
	check(FPProgression.payload_hairs(payload) == left(100.0, 1) and p.hairs("mantle") == 2 * grown(100.0, 1) - left(100.0, 1), "after a visit home only the new hairs are halved")
	# never more than are still worn
	p = FPProgression.new()
	p.on_flesh_eaten(0, 100.0)
	p.mutation_tree.add_points("core", -(grown(100.0, 0) - 1))
	payload = p.take_death_payload(0.0)
	check(FPProgression.payload_hairs(payload) == mini(left(100.0, 0), 1) and p.hairs("core") >= 0, "a death never takes more hairs than are worn")
	# saved with the run
	p = FPProgression.new()
	p.on_flesh_eaten(2, 100.0)
	var data: Dictionary = bytes_to_var(var_to_bytes(p.serialize()))
	# a count read back from text is a float
	(data["expedition_hairs"] as Dictionary)["surface"] = float(p.expedition_hairs["surface"])
	var r := FPProgression.new()
	r.deserialize(data)
	check(r.expedition_hairs == p.expedition_hairs and typeof(r.expedition_hairs["surface"]) == TYPE_INT, "hairs at stake are saved and loaded as whole numbers (%s)" % str(r.expedition_hairs))
	r = FPProgression.new()
	data.erase("expedition_hairs")
	r.deserialize(data)
	check(r.expedition_hairs.is_empty() and r.hairs("surface") == p.hairs("surface"), "a save without the key loads with nothing at stake and every hair")
	# the stalks: one per hair, a share each past the cap
	check(CorpseArt.stalk_pools({"hairs": {}}).is_empty() and CorpseArt.stalk_pools({}).is_empty(), "no hairs, no stalks")
	check(CorpseArt.stalk_pools({"hairs": {"surface": 2.0, "core": 1.0}}) == (["core", "surface", "surface"] as Array[String]), "one stalk per hair, in shell order")
	var many := CorpseArt.stalk_pools({"hairs": {"core": 58, "mantle": 1, "surface": 1}})
	check(many.size() == CorpseArt.MAX_STALKS and many.has("mantle") and many.has("surface") and many.count("core") == CorpseArt.MAX_STALKS - 2, "past the cap every pool keeps a stalk (%d)" % many.size())
	check(is_equal_approx(CorpseArt.thickness(3), 1.0) and is_equal_approx(CorpseArt.thickness(CorpseArt.MAX_STALKS * 3 / 2), 1.5) and is_equal_approx(CorpseArt.thickness(1000), CorpseArt.MAX_THICKEN), "more hairs than stalks only thicken them, twice at most")

# --- bodies in the world ------------------------------------------------------------

func _bodies() -> void:
	var prog: FPProgression = m.progression
	var c: Vector3 = m.RESTROOM_CENTER
	# standing in the restroom banks; a rest container does not
	prog.on_flesh_eaten(1, 100.0)
	var at_stake: Dictionary = prog.expedition_hairs.duplicate()
	m.player.global_position = m.rest_points[1]
	m.bank_hairs_at_home()
	check(m.in_rest(m.player.global_position) and prog.expedition_hairs == at_stake and not at_stake.is_empty(), "standing in a rest container keeps the hairs at stake")
	m.stomach.add_flesh(40.0)
	m.vomit_at_rest_point(1)
	m.bank_hairs_at_home()
	check(prog.expedition_hairs == at_stake, "vomiting into its bucket does not free them either")
	m.rest_teeth[1] = 0
	m.player.global_position = m.START_POS
	m.bank_hairs_at_home()
	check(prog.expedition_hairs.is_empty(), "standing in the restroom does")
	var safe: int = prog.hairs("mantle")
	m.player.global_position = c + Vector3(6.0, 0.0, 12.0)
	m.die("tissue")
	check(FPProgression.payload_hairs(m.death_drop.items) == 0 and prog.hairs("mantle") == safe, "dying after a visit home drops none of the hairs that were home")
	check(CorpseArt.stalk_count(m.death_drop) == 0 and named(m.death_drop.get_node("Body"), "Fuzz") == 1 and named(m.death_drop.get_node("Body"), "Stalks") == 0, "that body has its hair mat and no stalk")
	var bare: FDKDeathDrop = m.death_drop
	var bare_fuzz := verts(bare.get_node("Body/Fuzz"))
	check(bare_fuzz > 0, "the mat is real geometry (%d vertices)" % bare_fuzz)
	# a death out in the mantle: half the new hairs lie on the body as stalks
	m.player.global_position = m.START_POS
	prog.hair_carry["mantle"] = 0.0
	prog.on_flesh_eaten(1, 100.0)
	var worn: int = prog.hairs("mantle")
	var common: int = prog.hairs(FPProgression.COMMON)
	var spot := c + Vector3(-7.0, 0.5, 12.0)
	m.player.global_position = spot
	m.stomach.add_flesh(30.0)
	m.die("tissue")
	var body: FDKDeathDrop = m.death_drop
	var n := left(100.0, 1)
	check(int((body.items["hairs"] as Dictionary).get("mantle", 0)) == n and prog.hairs("mantle") == worn - n and prog.hairs(FPProgression.COMMON) == common, "a mantle death leaves %d hairs on the body, none of them common" % n)
	check(CorpseArt.stalk_count(body) == mini(FPProgression.payload_hairs(body.items), CorpseArt.MAX_STALKS) and CorpseArt.stalk_count(body) == n, "one stalk per hair to take back (%d)" % CorpseArt.stalk_count(body))
	var flesh := body.get_node("Body") as MeshInstance3D
	var cap := flesh.mesh as CapsuleMesh
	var skin := flesh.material_override as StandardMaterial3D
	check(cap != null and is_equal_approx(cap.radius, 0.17) and is_equal_approx(cap.height, 1.05) and skin != null and skin.albedo_color.is_equal_approx(Color(0.78, 0.6, 0.52)), "the body is the same skin coloured lump as before")
	check(named(flesh, "Fuzz") == 1 and named(flesh, "Stalks") == 1 and named(flesh, "Tips") == 1, "one mat, one set of stalks, one set of buds")
	check(lamps(body) == 1, "the stake's lamp is the only light on a body (%d)" % lamps(body))
	var stalk_verts := verts(flesh.get_node("Stalks"))
	var tip_verts := verts(flesh.get_node("Tips"))
	check(stalk_verts > 0 and tip_verts > 0 and stalk_verts % n == 0 and tip_verts % n == 0, "every stalk and bud is the same amount of geometry (%d, %d for %d)" % [stalk_verts, tip_verts, n])
	var per_stalk := stalk_verts / n
	var colours := (flesh.get_node("Tips") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var arm_hair := load("res://main/art/fp_arm_hair.gd") as GDScript
	var bud: Color = (arm_hair.get_script_constant_map()["COLORS"] as Dictionary)["mantle"]
	# mesh colours are stored in 8 bits
	check(colours.size() > 0 and absf(colours[0].r - bud.r) < 0.01 and absf(colours[0].g - bud.g) < 0.01 and absf(colours[0].b - bud.b) < 0.01, "a bud has its hair's colour (%s)" % str(colours[0] if colours.size() > 0 else Color()))
	CorpseArt.dress(body)
	CorpseArt.dress(body)
	check(named(flesh, "Fuzz") == 1 and named(flesh, "Stalks") == 1 and named(flesh, "Tips") == 1 and CorpseArt.stalk_count(body) == n, "dressing a body again leaves one of each")
	await process_frame
	check(flesh.get_child_count() == 3, "and nothing else under the lump (%d)" % flesh.get_child_count())
	# the mat is the same whatever lies on the body
	var fuzz := verts(flesh.get_node("Fuzz"))
	var kept: Dictionary = (body.items["hairs"] as Dictionary).duplicate()
	for count in [0, 3, CorpseArt.MAX_STALKS, 60]:
		body.items["hairs"] = {"surface": count} if count > 0 else {}
		CorpseArt.dress(body)
		check(verts(flesh.get_node("Fuzz")) == fuzz, "%d hairs: the mat does not change" % count)
		check(CorpseArt.stalk_count(body) == mini(count, CorpseArt.MAX_STALKS), "%d hairs: %d stalks" % [count, mini(count, CorpseArt.MAX_STALKS)])
		if count > 0:
			check(verts(flesh.get_node("Stalks")) == per_stalk * mini(count, CorpseArt.MAX_STALKS), "%d hairs: the stalks drawn are the stalks counted" % count)
	# without the mat the stalks stand alone
	CorpseArt.show_fuzz = false
	CorpseArt.dress(body)
	check(named(flesh, "Fuzz") == 0 and CorpseArt.stalk_count(body) == CorpseArt.MAX_STALKS and named(flesh, "Tips") == 1, "with the mat switched off the stalks and buds stay")
	CorpseArt.show_fuzz = CorpseArt.SHOW_FUZZ
	body.items["hairs"] = kept
	CorpseArt.dress(body)
	# two bodies, each with its own; a save keeps both as they look
	check(m.death_drops.size() == 2 and m.death_drops.has(bare) and FPProgression.payload_hairs(bare.items) == 0 and FPProgression.payload_hairs(body.items) == n, "two deaths, two bodies, each with its own hairs")
	prog.on_flesh_eaten(2, 10.0)
	var stake_saved: Dictionary = prog.expedition_hairs.duplicate()
	var data: Dictionary = m.serialize()
	m.deserialize(data)
	await process_frame
	prog = m.progression
	var loaded: FDKDeathDrop = m.death_drop
	check(m.death_drops.size() == 2 and loaded.last_known_position.is_equal_approx(spot), "both bodies are loaded")
	check(prog.expedition_hairs == stake_saved, "the hairs at stake are loaded (%s)" % str(prog.expedition_hairs))
	check(loaded.items.get("hairs", {}) == kept and CorpseArt.stalk_count(loaded) == n, "the body's hairs and its %d stalks are loaded" % n)
	check(verts(loaded.get_node("Body/Fuzz")) == fuzz and verts(loaded.get_node("Body/Stalks")) == stalk_verts, "and it looks the same")
	var other: FDKDeathDrop = m.death_drops[0] if m.death_drops[0] != loaded else m.death_drops[1]
	check(CorpseArt.stalk_count(other) == 0 and verts(other.get_node("Body/Fuzz")) == bare_fuzz, "the bare body is loaded bare")
	# reaching it: everything back, the body gone
	prog.bank_expedition_hairs()
	worn = prog.hairs("mantle")
	m.player.global_position = loaded.current_position
	m._step_death_drop(0.016)
	check(prog.hairs("mantle") == worn + n and int(prog.expedition_hairs.get("mantle", 0)) == n, "within reach of the body every hair comes back, at stake again")
	check(not m.death_drops.has(loaded) and not loaded.active, "an emptied body is gone")
	check(m.stomach.fill >= 30.0, "with the stomach it held")
	# a body the hands cannot empty stays, without stalks
	m.player.global_position = m.START_POS
	m.bank_hairs_at_home()
	m.stomach.vomit()
	prog.hair_carry["surface"] = 0.0
	prog.on_flesh_eaten(2, 100.0)
	prog.barriers = FPProgression.MAX_BARRIERS
	m.player.global_position = c + Vector3(8.0, 0.5, 21.0)
	m.die("tissue")
	var full: FDKDeathDrop = m.death_drop
	var n2 := left(100.0, 2)
	check(CorpseArt.stalk_count(full) == n2 and n2 > 0, "a surface death: %d stalks" % n2)
	prog.barriers = FPProgression.MAX_BARRIERS
	worn = prog.hairs("surface")
	m.player.global_position = full.current_position
	m._step_death_drop(0.016)
	check(prog.hairs("surface") == worn + n2 and full.active and m.death_drops.has(full) and int(full.items.get("barriers", 0)) == FPProgression.MAX_BARRIERS, "full hands: the hairs come back and the barriers stay on the body")
	check(CorpseArt.stalk_count(full) == 0 and named(full.get_node("Body"), "Stalks") == 0 and named(full.get_node("Body"), "Fuzz") == 1, "that body keeps its mat and has no stalk left")
	m.player.global_position = m.START_POS
	m.bank_hairs_at_home()

# --- M29: a crush death that only sleeps ------------------------------------------

func _dormant() -> void:
	var prog: FPProgression = m.progression
	prog.mutation_tree._purchased["M29"] = true
	prog.hair_carry["core"] = 0.0
	prog.on_flesh_eaten(0, 100.0)
	var worn := {}
	for b in FPProgression.BIOMES:
		worn[b] = prog.hairs(b)
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0.5, 0.0, 6.5)
	m.die("crush")
	var same := true
	for b in FPProgression.BIOMES:
		same = same and prog.hairs(b) == int(worn[b])
	check(m.mutation_apply.is_dormant() and same, "M29: waking from a crush, every hair is still worn")
	check(not m.death_drop.active, "M29: no body is left out there")
	m.bank_hairs_at_home()
	check(prog.expedition_hairs.is_empty(), "M29: and the hairs are home with the sleeper")
