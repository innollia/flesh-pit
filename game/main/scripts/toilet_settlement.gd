class_name FPToiletSettlement
extends Node

## Toilet settlement (spec 03-restroom 6, 04-economy). No numbers, no shop
## screen: the player vomits into the bowl, then must press the lever by
## hand. Until the lever is pressed nothing is settled (teeth 0, no hair).
## On the lever: teeth drop into the tank (a rattle whose length follows the
## amount; a whole tumor makes it much longer) and hairs grow on the arm.
## Main wires the camera and input; this node owns the bowl and the rattle.

signal lever_pulled(teeth_gain: int, hair_gain: int)
signal tank_rattle_started(duration: float, tumor: bool)
signal tank_rattle_finished

## Rattle length: a short base clatter plus per tooth, capped. A tumor adds
## a long extra run ("훨씬 길다").
const RATTLE_BASE := 0.5
const RATTLE_PER_TOOTH := 0.06
const RATTLE_MAX := 3.0
const RATTLE_TUMOR_EXTRA := 3.5
const SHAKE_AMPLITUDE := 0.004

## Flesh units lying in the bowl, waiting for the lever.
var bowl_flesh: float = 0.0
## Whole tumors lying in the bowl, waiting for the lever.
var bowl_tumors: Array[String] = []
var rattle_left: float = 0.0
var last_rattle: float = 0.0
## Node shaken during the rattle (the tank art); optional.
var tank_node: Node3D
var _tank_rest: Vector3
var _t: float = 0.0

func has_contents() -> bool:
    return bowl_flesh > 0.0 or not bowl_tumors.is_empty()

## Vomit into the bowl. Nothing is gained yet.
func vomit_into(amount: float) -> void:
    bowl_flesh += maxf(amount, 0.0)

## Throw every carried tumor into the bowl: the hands are free at once,
## but teeth and the codex entry only come with the lever.
func throw_tumors(prog: FPProgression) -> int:
    var n := 0
    for kind in prog.tumors._carried.duplicate():
        bowl_tumors.append(String(kind))
        n += 1
    prog.tumors._carried.clear()
    return n

## The lever, pressed by hand. Settles the bowl: teeth into the tank and
## hairs onto the arm. Returns {teeth, hairs, tumors, rattle}.
func press_lever(prog: FPProgression) -> Dictionary:
    var tumor_teeth := 0
    var tumor_n := 0
    for kind in bowl_tumors:
        prog.tumors._codex[kind] = true
        prog.teeth += FPProgression.TUMOR_TOOTH_PAYOUT
        tumor_teeth += FPProgression.TUMOR_TOOTH_PAYOUT
        tumor_n += 1
    bowl_tumors.clear()
    var got := prog.settle(bowl_flesh)
    bowl_flesh = 0.0
    var teeth_gain: int = int(got["teeth"]) + tumor_teeth
    var dur := rattle_duration(teeth_gain, tumor_n)
    _start_rattle(dur, tumor_n > 0)
    lever_pulled.emit(teeth_gain, int(got["hairs"]))
    return {"teeth": teeth_gain, "hairs": int(got["hairs"]), "tumors": tumor_n, "rattle": dur}

static func rattle_duration(teeth_gain: int, tumor_count: int) -> float:
    if teeth_gain <= 0 and tumor_count <= 0:
        return 0.0
    var d := minf(RATTLE_BASE + RATTLE_PER_TOOTH * teeth_gain, RATTLE_MAX)
    if tumor_count > 0:
        d += RATTLE_TUMOR_EXTRA
    return d

func is_rattling() -> bool:
    return rattle_left > 0.0

func _start_rattle(dur: float, tumor: bool) -> void:
    last_rattle = dur
    if dur <= 0.0:
        return
    if rattle_left <= 0.0 and tank_node != null:
        _tank_rest = tank_node.position
    rattle_left = dur
    tank_rattle_started.emit(dur, tumor)

func _process(delta: float) -> void:
    tick(delta)

func tick(delta: float) -> void:
    if rattle_left <= 0.0:
        return
    _t += delta
    rattle_left -= delta
    if tank_node != null:
        if rattle_left > 0.0:
            var a := SHAKE_AMPLITUDE
            tank_node.position = _tank_rest + Vector3(sin(_t * 71.0) * a, absf(sin(_t * 53.0)) * a, cos(_t * 67.0) * a)
        else:
            tank_node.position = _tank_rest
    if rattle_left <= 0.0:
        rattle_left = 0.0
        tank_rattle_finished.emit()