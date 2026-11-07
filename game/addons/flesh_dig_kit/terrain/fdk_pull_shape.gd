class_name FDKPullShape
extends RefCounted

## The shape of the flesh pulled toward the hands (2026-11-08 "살점을 팔때
## *처럼 살 잡아당겨지는게 1인칭에서 안예쁨"). fdk_terrain_surface.gdshader
## draws exactly this; the GDScript copy exists so headless tests can measure
## the shape the shader draws. Change both together.
##
## The old pull gathered every vertex sideways into the grip (an in-plane
## pinch) inside a tight cone and painted 17 radial red fibres round it: on
## the low-poly faces this read as a star of creases from the first-person
## camera. The pull is now one rounded, wet dome drawn out along the shared
## direction toward the eater: no sideways motion (no creases), a bell that
## is flat at its top and at its rim (no point, no step), and strain shading
## that depends on distance alone (no rays).

## Dent depth at the start of the press and the height of the drawn-out dome.
const DENT := 0.16
const LIFT := 0.30
## The dome is narrower than the press (rounded, not a wide sheet).
const DOME_SCALE := 0.7
## Whole-dome quiver as the flesh nears its tear (same phase everywhere, so
## it never makes rings or rays).
const QUIVER := 0.012

## Smooth bell of x = distance / radius: 1 at the centre, 0 at and past the
## rim, zero slope at both ends.
static func bell(x: float) -> float:
	var t := clampf(1.0 - x * x, 0.0, 1.0)
	return t * t

static func dent_amount(amount: float) -> float:
	return sin(clampf(amount / 0.55, 0.0, 1.0) * 1.5708) * (1.0 - smoothstep(0.55, 0.9, amount))

static func pull_amount(amount: float) -> float:
	return smoothstep(0.45, 1.0, amount)

## Offset of a surface point `rel` (from the press centre) for press
## `amount`, `toward` the eater, press `radius`, at shader time `time`.
static func offset(rel: Vector3, toward: Vector3, amount: float, radius: float, time: float) -> Vector3:
	var pn := (toward + Vector3(0.0, 1e-5, 0.0)).normalized()
	var d := rel.length()
	var wide := bell(d / radius)
	var dome := bell(d / (radius * DOME_SCALE))
	var pull := pull_amount(amount)
	# one bell at every moment: the wide dent narrows into the dome, so the
	# two never meet as a ring-shaped trough
	var shape := lerpf(wide, dome, pull)
	var h := (-DENT * dent_amount(amount) + LIFT * pull) * shape
	h += QUIVER * pull * pull * shape * sin(time * 47.0)
	return pn * h

## 0..1 strain of the stretched skin at `rel` (taut, pale and glossy toward
## the top of the dome).
static func strain(rel: Vector3, amount: float, radius: float) -> float:
	return smoothstep(0.3, 1.0, amount) * bell(rel.length() / radius)
