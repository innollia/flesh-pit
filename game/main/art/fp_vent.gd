extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")

## Ceiling vent (the shop). Local frame: the vent face lies on y=0 and the
## duct goes UP (+Y), so it is seen from below. Grate hinges down on its -X
## edge. Nothing of the being shows in the dark duct (no eyes, user
## 2026-11-03); when it offers, one slender arm per offered item comes down
## out of the black and holds its item out close in front of the player's
## eye, lying on the open, upturned palm.
## Public: set_open(0..1), play_open(), play_offer(), play_withdraw(),
## set_offer_items(kinds), take_item(i), item_node(i), hand_count(),
## begin_look(eye), end_look(), look_pose() (the head in under the vent),
## set_pile(n), play_spill(kinds, floor_y). set_eyes(), blink() and set_eye_mood() stay callable for the
## vent logic: the eyes never show, the mood only makes the fingers fidget.

const SIZE := 0.26
var _black_cover: MeshInstance3D
var _grate: Node3D
var _offers: Array = []
var _mood := 0.0
var _time := 0.0

func _ready() -> void:
    var metal := K.mat("tex_chrome_128.png", 0.2, false)
    # flange frame, 4 bevelled bars
    var st := K.begin()
    var c := Color(0.78, 0.8, 0.8)
    var ce := Color(0.95, 0.96, 0.96)
    K.rbox(st, K.T(Vector3(0, -0.01, SIZE + 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(0, -0.01, -SIZE - 0.03)), Vector3(SIZE + 0.06, 0.015, 0.03), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.03, -0.01, 0)), Vector3(0.03, 0.015, SIZE), 0.012, c, ce)
    # screws
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.lathe(st, K.T(Vector3(sx * (SIZE + 0.03), -0.028, sz * (SIZE + 0.03)), Vector3(180, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.01, 0.006), Vector2(0.0, 0.008)], 6, [Color(0.6, 0.6, 0.62)])
            # slotted screw heads
            K.rbox(st, K.T(Vector3(sx * (SIZE + 0.03), -0.037, sz * (SIZE + 0.03)), Vector3(0, 45, 0)), Vector3(0.011, 0.0015, 0.0018), 0.0005, Color(0.2, 0.2, 0.21))
    # inner sleeve covering the seam between flange and duct walls
    K.rbox(st, K.T(Vector3(0, 0.012, SIZE + 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(0, 0.012, -SIZE - 0.004)), Vector3(SIZE + 0.008, 0.026, 0.005), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(SIZE + 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
    K.rbox(st, K.T(Vector3(-SIZE - 0.004, 0.012, 0)), Vector3(0.005, 0.026, SIZE), 0.003, c, ce)
    K.add_mesh(self, "Flange", K.finish(st, 6.0), metal)
    # duct: inward-facing walls going up into black
    st = K.begin()
    var dark := Color(0.12, 0.12, 0.13)
    var black := Color(0.01, 0.01, 0.01)
    var hgt := 0.7
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        var a := Vector3(-SIZE, 0, -SIZE)
        var b := Vector3(SIZE, 0, -SIZE)
        K.quad(st, t, a, b, b + Vector3(0, 0.25, 0), a + Vector3(0, 0.25, 0), Vector3(0, 0, 1), dark)
        K.quad(st, t, a + Vector3(0, 0.25, 0), b + Vector3(0, 0.25, 0), b + Vector3(0, hgt, 0), a + Vector3(0, hgt, 0), Vector3(0, 0, 1), black)
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, hgt, -SIZE), Vector3(SIZE, hgt, -SIZE), Vector3(SIZE, hgt, SIZE), Vector3(-SIZE, hgt, SIZE), Vector3.DOWN, black)
    K.add_mesh(self, "Duct", K.finish(st, 4.0), K.mat("tex_fixture_64.png", 0.1, false))
    # A closed vent reads as a clean black opening behind the grille.
    st = K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, -SIZE), Vector3(SIZE, 0.01, SIZE), Vector3(-SIZE, 0.01, SIZE), Vector3.DOWN, Color.BLACK)
    _black_cover = K.add_mesh(self, "BlackOpening", K.finish(st), K.glow(Color.BLACK))
    # grate on a hinge
    _grate = K.pivot(self, "GrateHinge", Vector3(-SIZE, -0.02, 0))
    st = K.begin()
    var gc := Color(0.86, 0.87, 0.86)
    K.rbox(st, K.T(Vector3(SIZE, 0, SIZE - 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(SIZE, 0, -SIZE + 0.015)), Vector3(SIZE, 0.012, 0.015), 0.006, gc)
    K.rbox(st, K.T(Vector3(0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    K.rbox(st, K.T(Vector3(2 * SIZE - 0.015, 0, 0)), Vector3(0.015, 0.012, SIZE), 0.006, gc)
    for i in range(9):
        var x := 0.05 + i * (2 * SIZE - 0.1) / 8.0
        K.rbox(st, K.T(Vector3(x, 0.005, 0), Vector3(0, 0, 38)), Vector3(0.004, 0.018, SIZE - 0.02), 0.002, Color(0.8, 0.81, 0.8), Color(0.95, 0.95, 0.95))
    # centre brace so the long slats do not read as loose sticks
    K.rbox(st, K.T(Vector3(SIZE, 0.012, 0)), Vector3(SIZE - 0.02, 0.006, 0.01), 0.003, gc)
    # hinge knuckles on the -X edge so the grate visibly hangs from something
    for hz in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, hz * (SIZE - 0.09)), Vector3(0, 0, hz * (SIZE - 0.03))], [0.009, 0.009], 6, [Color(0.7, 0.71, 0.7)], true)
    K.add_mesh(_grate, "Grate", K.finish(st, 8.0), metal)
    # offered items: the being only ever shows the arms that hold them out
    # (docs/spec/03-restroom.md §7), one hand per item. The player picks
    # one up by hand, the others go back up.
    _build_pile()
    _build_glint()
    _arms = K.pivot(self, "BeingArm")
    _arms.visible = false
    set_offer_items(["spray_cheap", "barrier", "junk"])
    set_offer_extend(0.0)

# --- the being's hands ---------------------------------------------------------

## The hands are held out this far in front of the player's eye (level
## distance, toward the vent) and this much above it, so the items read up
## close (user 2026-11-03: "가까이서 보게"); right under the vent they stay
## higher so they do not hang in the face. The arms reach at most REACH_MAX
## from the lip.
const HAND_AHEAD := 0.46
const HAND_LIFT := 0.08
const HAND_LIFT_UNDER := 0.4
const REACH_MAX := 1.4
## Lip height of the opening (the arm leaves the black here) and the lowest
## the hand cluster's middle may hang above it.
const LIP_Y := -0.03
const BELOW_LIP := 0.32
## Hands side by side (metres between wrists) and rows of at most ROW_MAX.
const SPACING := 0.16
const ROW_GAP := 0.21
const ROW_MAX := 5
## Each hand past the third pushes the fan this much further out, so a wide
## offer still fits the view without the hands crowding each other.
const AHEAD_PER_HAND := 0.035
## The arm (user 2026-11-09 "팔을 일자로만 뻗어서 이상함"): a shoulder up in
## the dark of the duct, the upper arm coming down out of the opening to a
## softly bent elbow, a forearm of a real length sloping down toward the
## player and turning the palm up, and the wrist lifting the hand back a
## little to offer. FOREARM is elbow to wrist (shorter only on a short reach);
## SHOULDER_UP is the shoulder above the lip.
const FOREARM := 0.255
## Inside angle at the elbow (radians; pi is a straight arm), each arm its
## own by up to ELBOW_VARY, the elbow pointing away from the eye and out.
const ELBOW_ANGLE := 2.45
const ELBOW_VARY := 0.14
const SHOULDER_UP := 0.12
## The wrist never bends further than this from the forearm line (a soft
## extension, comfortable, never a broken-back wrist).
const WRIST_MAX := 0.62
## The palm turns up to the eye: its normal is the way up weighted by
## PALM_UP plus the way to the eye, so the item lies in it and the eye sees
## into the palm.
const PALM_UP := 0.72
## Share of the offer tween spent coming straight down out of the duct
## before the forearm swings out toward the player.
const DROP_PHASE := 0.42
## Where the item sits (hand frame: fingers down -Y, palm +Z, thumb +X): in
## the hollow of the open palm a little below its middle, its bottom resting
## on the skin (user 2026-11-09 "물건이 손에 잘 안 올라가있음").
const SEAT := Vector2(0.001, -0.058)
## The item presses this far into the soft palm, so it reads as lying on it.
const SEAT_SINK := 0.0012
## Offered items at this share of their real size (they are what the hand
## then carries to the belt), so the hand still shows round them.
const ITEM_SCALE := 0.62
## Longest and shortest side (item units, before ITEM_SCALE) an item may
## have across the palm; bigger ones are shrunk to fit.
const ITEM_SPAN := 0.15
const ITEM_BREADTH := 0.11
## Bright porcelain skin with living warmth: rosy knuckles and fingertips, a
## cooler shade in the creases at the finger roots, and glossy almond nails
## in a soft rose (user 2026-11-03, 11-08 "손이 아직 덜 예뻐"): a hand that
## makes you expect a very beautiful person.
const SKIN := Color(1.0, 0.885, 0.83)
const SKIN_SHADE := Color(0.95, 0.8, 0.76)
const SKIN_BLUSH := Color(1.0, 0.815, 0.775)
const SKIN_CREASE := Color(0.95, 0.79, 0.76)
## The knuckles only a breath warmer than the skin round them.
const SKIN_KNUCKLE := Color(1.0, 0.85, 0.805)
## The palm side, which is what the eye sees once the hand has turned over:
## a living flush over the whole palm and the fingers' undersides, a little
## deeper in the fingertip pads and the ball of the thumb. Colour only: no
## veins, creases or marks (a blush, never a bruise).
const SKIN_PALM := Color(1.0, 0.868, 0.842)
const SKIN_PAD := Color(1.0, 0.82, 0.80)
## Nails carry alpha below 1: the being's shader gives them a glossy sheen.
const NAIL := Color(0.85, 0.44, 0.5, 0.7)
const NAIL_MOON := Color(0.95, 0.66, 0.68, 0.72)
const NAIL_TIP := Color(0.93, 0.56, 0.6, 0.7)
## Hand proportions from photo references of slim women's hands, drawn a
## little toward the hand-model ideal (user 2026-11-08): back of the hand
## (wrist to knuckle) 0.076 m, middle finger from its knuckle about 1.22 of
## that; index 0.93, ring 0.95, little 0.77, thumb 0.66 of the middle finger.
## The palm tapers from a slim wrist (0.67 of the knuckle breadth) and
## rounds into the knuckles, which the finger bases fill edge to edge, so
## the outline runs from wrist to fingertips with no shelf (11-09: the palm
## read as a box). Hand frame: wrist at 0, fingers down -Y, palm +Z, thumb +X.
const PALM_LEN := 0.086
const PALM_HALF := 0.0282
const WRIST_HALF := 0.0222
## The knuckle (MCP) sits this far inside the finger root line.
const MCP_IN := 0.01
## Fingers index to little: x, finger root height (share of the palm
## length: the knuckles run in a gentle arc, the middle furthest), length
## from the knuckle, base radius, sideways splay (degrees), curl share
## (each finger toward the little one curls a little more).
const FINGERS := [
    [0.0197, 0.958, 0.0858, 0.0064, -4.5, 0.8],
    [0.0066, 1.0, 0.0928, 0.0066, -0.8, 1.0],
    [-0.0066, 0.972, 0.0882, 0.0062, 2.2, 1.12],
    [-0.0188, 0.89, 0.0712, 0.0053, 8.0, 1.36],
]
const PHALANX := [0.45, 0.28, 0.27]
const TAPER := 0.72
const THUMB_LEN := 0.062
## The thumb leaves the thenar mound here and lies relaxed, open from the
## index (degrees: forward toward the palm, out from the fingers, and its own
## turn so the nail faces out to the side).
const THUMB_ROOT := Vector3(0.0272, -0.04, 0.0066)
const THUMB_POSE := Vector3(-24, 0, 34)
const THUMB_TWIST := -62.0
## Curl offering (the fingers rise softly round the item), up close, and
## when gripping on the take; per joint the middle (PIP) bends most.
const CURL_REST := 0.5
const CURL_GRIP := 1.2
const JOINT_SHARE := [0.42, 1.0, 0.62]
## Build B: the same lengths on a hand 8-10 % broader (palm, wrist, fingers,
## thumb, arm), kept beside the approved slim build A for the user to pick
## from a side-by-side (docs/tracking/captures/R2_npc_hand). BUILD_B false
## is build A; `build_b` lets a capture switch before the vent is made.
const BUILD_B := false
static var build_b := BUILD_B
const PALM_HALF_B := 0.0305
const WRIST_HALF_B := 0.0236
const FINGERS_X_B := [0.0213, 0.0071, -0.0071, -0.0203]
const FINGERS_R_B := [0.0070, 0.0072, 0.0068, 0.0058]
const TAPER_B := 0.75
const THUMB_R := [0.0078, 0.0071, 0.0057]
const THUMB_R_B := [0.0085, 0.0077, 0.0062]
const THUMB_ROOT_X_B := 0.0294
const WIDE_B := 1.08

static func _palm_half() -> float:
    return PALM_HALF_B if build_b else PALM_HALF

static func _wrist_half() -> float:
    return WRIST_HALF_B if build_b else WRIST_HALF

static func _finger_x(i: int) -> float:
    return float(FINGERS_X_B[i]) if build_b else float(FINGERS[i][0])

static func _finger_r(i: int) -> float:
    return float(FINGERS_R_B[i]) if build_b else float(FINGERS[i][3])

static func _taper() -> float:
    return TAPER_B if build_b else TAPER

static func _thumb_r() -> Array:
    return THUMB_R_B if build_b else THUMB_R

static func _thumb_root() -> Vector3:
    return Vector3(THUMB_ROOT_X_B, THUMB_ROOT.y, THUMB_ROOT.z) if build_b else THUMB_ROOT

## Sideways scale of the hand-drawn palm, thenar and arm outlines.
static func _wide() -> float:
    return WIDE_B if build_b else 1.0

## The offer's motion (2026-11-14). The hand comes down showing its back and
## nails, and turns over about its own fingers (thumb leading toward the
## eye, the way a forearm supinates) through this share of the swing.
const FLIP_FROM := 0.25
const FLIP_TO := 0.9
## Each hand out from the middle of the row starts this much later (share of
## the offer), so they do not move as one machine.
const HAND_DELAY := 0.09
const HAND_DELAY_MAX := 0.36
## The item's weight: over the last of the swing the wrist dips this far
## and comes back.
const SETTLE_FROM := 0.85
const SETTLE_DIP := 0.012
## The fingers hang this much more curled until the palm has come up.
const FOLLOW_CURL := 0.25
## After the take the hand only closes this far and draws back at its ease;
## a frantic being (mood 1) still snatches (grip 1, the old times).
const TAKE_GRIP := 0.45
const TAKE_GRIP_SECS := 0.28
const TAKE_RISE_SECS := 0.55
## Up close the hands hold side by side, every palm and its fingers toward
## the eye. They do not open out like a fan from the one opening (tried
## 2026-11-14; user: "부채 싫어").
##
## Candidates for a prettier hand, each behind one switch and all off
## until the user has picked from the side-by-side in
## docs/tracking/captures/R3_npc_hand/pick_variants.jpg. The look or pose of
## this hand only becomes the default after the user has seen before/after
## pictures in the game's own view and chosen (docs/design/vent-npc.md).
## The static copies let a capture switch before the vent is made.
## TONE: colour and shading only, so the form reads against the white tiles.
const HAND_TONE := false
static var hand_tone := HAND_TONE
## GRACE: the fingers each at their own height, the thumb drawn in, the
## wrist a touch toward the little finger, the hands at uneven heights. On
## its own it read no better than the hand as it is up close, so the pick
## sheet only shows it together with ANGLE.
const HAND_GRACE := false
static var hand_grace := HAND_GRACE
## ANGLE: up close the palm lies flatter and every hand runs the same way
## across the view, its little-finger edge to the eye.
const HAND_ANGLE := false
static var hand_angle := HAND_ANGLE
## THUMB: the thumb drawn in beside the index, its tip toward the middle
## finger, in place of lying out to the side from under the item (which read
## as a crab's claw up close). Its own switch: it goes with any of the three.
const HAND_THUMB := false
static var hand_thumb := HAND_THUMB
## The hand coming down back first and turning over (FLIP_FROM..FLIP_TO),
## on since 2026-11-14; off, it comes down palm first as before. Kept
## switchable for the user's pick (pick_flip.jpg). Half way through the turn
## the palm is edge on to the eye: the open fingers read as a rake and the
## item stands on its side beside the hand. Gathering the fingers and
## closing the thumb on the item for the turn was tried and did not mend
## it (the item still stands on edge), so off is what is proposed.
const HAND_FLIP := true
static var hand_flip := HAND_FLIP
## A modeled hand in place of the hand built from tubes (user 2026-11-14:
## every tube hand "구리다"; a modeled one was asked for, and long sculpted
## nails are to go on it later). 0: the hand as it is. 1: the CC0 Godot XR
## Tools hand (MakeHuman based). 2: the slender hand scripted in Blender
## (slender_hand_r.glb). 3: the hand built to this file's own proportions by
## tools/vent_hand_model/build_hand.py (vent_hand.glb). A
## candidate like the others: off until the user has picked from
## docs/tracking/captures/R4_npc_hand_model/pick_models.jpg. The arm, the
## side by side offer, the timing and the item seat are the same for all
## three; only the palm and fingers are swapped (see _attach_model).
const HAND_MODEL := 0
static var hand_model := HAND_MODEL

## TONE: the skin a shade deeper and peachier (multiplied in the shader),
## the light range lower so the open palm is not one flat white, the key
## light from the left of the view and a little above (view space: from
## higher up the bent elbow lit as a cuff) so each finger has a lit and a
## shaded side, and a warm darker edge at the silhouette in place of the
## pale rim. The shade painted into the arm's vertex colours (elbow, finger
## roots) is dropped: with real light and shade it showed as a hard band.
const TONE_TINT := Color(1.0, 0.968, 0.945)
const TONE_WRAP := Vector2(0.7, 1.0)
const TONE_KEY_VIEW := Vector3(-0.6, 0.3, 0.74)
const TONE_EDGE := Color(0.93, 0.7, 0.66)
const TONE_EDGE_AMOUNT := 0.58
## Up the forearm the light and shade even out to one level (TONE_ARM_LEVEL
## of the wrap, reached at the elbow; the arm meshes carry how far up the
## arm each ring is in UV.x): the forearm, the elbow ball and the upper arm
## each turned to the light their own way and the joint showed as a darker
## band across the arm.
const TONE_ARM_LEVEL := 0.6

## GRACE: knuckle, middle and tip joint (degrees) of the index, middle, ring
## and little finger at the offering rest: the index nearly straight, the
## middle and ring curving in under the item, the little finger lifted
## again; no two fingers alike, none of them straight.
## The tip joints bend the most, so the fingertips lift and the nails turn
## to the eye.
const GRACE_FLEX := [[7.0, 12.0, 16.0], [13.0, 19.0, 20.0], [13.0, 22.0, 22.0], [9.0, 17.0, 19.0]]
## Fingers apart but not spread (degrees, index to little): 4 degrees
## between neighbours, the index no further out than the others.
const GRACE_SPLAY := [-4.0, 0.0, 4.0, 8.0]
## THUMB (and GRACE, which always has it, and ANGLE up close, where the
## open palm shows the thumb most): the thumb lies along the index
## with a little air between, lifted a touch toward the palm, and its tip
## bends in toward the middle finger's second joint.
const TUCK_THUMB_POSE := Vector3(-10, 0, 7)
const TUCK_THUMB_TIP := -30.0
## The wrist turns the hand this far toward its little finger (radians).
const GRACE_ULNAR := 0.14
## Neighbouring hands stand this far above and below the row.
const GRACE_STEP := 0.016

## ANGLE (only while the head is in): the palm's normal weighs the way up
## this much (PALM_UP otherwise), the elbows all lean ANGLE_LEAN to the one
## side and the fingers turn ANGLE_TURN (radians) to the other in the palm's
## plane, so every hand lies along the same diagonal; each arm's own turn is
## cut to ANGLE_YAW of it so the hands stay parallel. All are right hands.
const ANGLE_PALM_UP := 0.82
const ANGLE_LEAN := 0.4
const ANGLE_TURN := 0.35
const ANGLE_YAW := 0.3
## The fingers lying across the view each need their own line: knuckle,
## middle and tip joint (degrees, index to little) from a nearly straight
## index to a softly bent little finger, and 6 degrees between neighbours.
const ANGLE_FLEX := [[3.0, 7.0, 5.0], [7.0, 12.0, 8.0], [10.0, 17.0, 11.0], [13.0, 22.0, 14.0]]
const ANGLE_SPLAY := [-9.0, -3.0, 3.0, 9.0]
## The item lies further down the palm, in front of the middle and ring
## finger roots (SEAT otherwise): from the side the old seat read as the
## item resting on the wrist.
const ANGLE_SEAT := Vector2(-0.001, -0.067)
## The elbow opens to this inside angle (ELBOW_ANGLE otherwise) and the
## forearm stays slim further up (breadth at 0.2, 0.5, 0.8 and 1.0 of its
## length, shares of the wrist half-breadth; 1.14, 1.3, 1.34, 1.26
## otherwise), so arm, wrist and hand run in one soft line.
const ANGLE_ELBOW := 2.82
const ANGLE_FOREARM := [1.05, 1.14, 1.22, 1.2]
## A single hand comes this much nearer the eye, so it shows as large as
## the hands of a row of three, and this much higher, so its fingers stay
## clear of the being's line of speech at the bottom of the view.
const ANGLE_ONE_NEAR := 0.08
const ANGLE_ONE_LIFT := 0.01
## Each hand along the row stands this much higher than the one before it
## (metres per metre along the row, less when the row is long: the ends
## stay within ANGLE_RISE of the middle), so no hand's fingers lie over the
## next; the whole row sits ANGLE_SHIFT to the side the wrists are on
## (ANGLE_SHIFT_WIDE with more than three hands, where the ends also only
## stand ANGLE_RISE_WIDE from the middle) and ANGLE_DROP lower (higher when
## negative), so the fingers and the labels stay in the frame.
const ANGLE_STAIR := 0.3
const ANGLE_RISE := 0.045
const ANGLE_RISE_WIDE := 0.025
const ANGLE_SHIFT := 0.06
const ANGLE_SHIFT_WIDE := -0.02
## More than three hands hold this much further from the eye, so the ends
## of the row stay in the frame.
const ANGLE_AHEAD_WIDE := 0.1
const ANGLE_DROP := -0.02

var _arms: Node3D
## One rig per hand: {root, upper, fore, elbow, hand, palm, slot, fingers, thumb, chir, ...}.
var _rigs: Array = []
var _count := 0
## Something is on offer (false once taken or cleared: the arms only go up).
var _wanted := false
var _extend := 0.0
## The offer is on its way back up (the last change of _extend went down).
var _retreat := false
var _curl := 0.0
var _hand_tw: Tween
## Smoothed middle of the hand cluster (vent frame), snapped on first show.
var _center := Vector3(0, -0.6, 0.3)
var _side := Vector3(0, 0, 1)
var _snap := true
var _meshes: Dictionary = {}
var _skin_mat: Material
## Height of the palm's skin under the item seat (hand frame z), and under
## the ANGLE candidate's seat.
var _seat_z := 0.012
var _angle_seat_z := 0.012

## The being's own soft skin (user 2026-11-03: the low-poly facets should
## not show; 11-08: still not pretty enough): smooth shared-vertex normals
## from _tube(), a wrapped (half-Lambert) key light so the shade side never
## goes hard, a warm subsurface-like glow where the light wraps into shade,
## at the thin silhouette and in the flushed fingertips and knuckles, a soft
## moisturised sheen, a faint cool rim, and a glossy coat on the nails
## (vertex alpha below 1 marks them). Above the lip of the opening the arm
## fades into the dark of the duct. Unshaded like the body's skin pipeline,
## so the bright ceiling lamp cannot blow it out; the player's skin material
## (FDKSkinMaterial) is not touched.
const SKIN_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 key_dir = vec3(0.35, 0.85, 0.4);
uniform vec3 fill_dir = vec3(-0.6, -0.2, 0.5);
uniform vec3 warm : source_color = vec3(1.0, 0.5, 0.42);
uniform float wrap_lo = 0.66;
uniform float wrap_hi = 1.04;
uniform float sss = 0.24;
uniform float rim = 0.12;
uniform float sheen = 0.05;
uniform float nail_gloss = 0.7;
uniform float lip_y = 1000.0;
// the TONE candidate (0 off, 1 on)
uniform float tone = 0.0;
uniform vec3 tone_tint = vec3(1.0);
uniform vec2 tone_wrap = vec2(0.6, 1.0);
uniform vec3 tone_key_view = vec3(-0.5, 0.6, 0.5);
uniform vec3 tone_edge = vec3(0.9, 0.6, 0.55);
uniform float tone_edge_amount = 0.6;
uniform float tone_arm_level = 0.6;
varying vec3 wn;
varying float wy;
varying float up_arm;
void vertex() {
    up_arm = UV.x;
    // the forearm is stretched along its length: the normal matrix keeps it round
    wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
    vec3 n = normalize(wn);
    if (!FRONT_FACING) { n = -n; }
    vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    vec3 l = normalize(key_dir);
    if (tone > 0.5) {
        // lit from the upper left of the view, so the form turns from light to shade
        l = normalize((INV_VIEW_MATRIX * vec4(tone_key_view, 0.0)).xyz);
    }
    float ndl = dot(n, l);
    float wrap = pow(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), 1.3);
    float fill = clamp(dot(n, normalize(fill_dir)) * 0.5 + 0.5, 0.0, 1.0);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    // TONE: up the arm the light evens out, so the elbow is no band
    float even = tone * smoothstep(0.0, 1.0, up_arm);
    wrap = mix(wrap, tone_arm_level, even);
    fill = mix(fill, 0.5, even);
    ndv = mix(ndv, max(ndv, 0.75), even);
    float fres = pow(1.0 - ndv, 2.4);
    vec3 base = COLOR.rgb;
    float nail = clamp((1.0 - COLOR.a) * 4.0, 0.0, 1.0);
    // flushed skin (fingertips, knuckles) lets more warm light through
    // TONE: the painted shade (red below the skin's own) goes back to plain skin
    float painted = tone * (1.0 - smoothstep(0.955, 0.99, base.r)) * (1.0 - nail);
    base = mix(base, vec3(1.0, 0.885, 0.83), painted);
    float flush = clamp((base.g < 0.86 ? 0.86 - base.g : 0.0) * 14.0, 0.0, 1.0) * (1.0 - nail);
    base = mix(base, base * tone_tint, tone * (1.0 - nail));
    vec3 col = base * mix(mix(wrap_lo, tone_wrap.x, tone), mix(wrap_hi, tone_wrap.y, tone), wrap) * mix(0.97, 1.03, fill);
    // light passing through thin skin: warm where it wraps into shade and at the silhouette
    col += base * warm * (sss + 0.1 * flush) * (1.0 - wrap * (1.0 - 0.5 * flush)) * (1.0 - nail);
    col = mix(col, col * mix(vec3(1.0), warm * 1.3, 0.55), fres * 0.4 * (1.0 - nail));
    col += vec3(0.92, 0.95, 1.0) * rim * fres * wrap * (1.0 - tone);
    // TONE: a warm darker edge, so the outline holds against a white wall
    col = mix(col, col * tone_edge, tone * tone_edge_amount * pow(1.0 - ndv, 1.7) * (1.0 - nail));
    vec3 h = normalize(l + v);
    float nh = max(dot(n, h), 0.0);
    // skin: a broad soft sheen; nails: a tight lacquer highlight and a reflection at grazing angles
    col += vec3(1.0, 0.97, 0.95) * pow(nh, 14.0) * sheen * (1.0 - nail);
    col += vec3(1.0) * (pow(nh, 70.0) * nail_gloss + pow(nh, 12.0) * 0.12 + fres * 0.3) * nail;
    // the arm comes out of the black of the duct
    col *= 1.0 - 0.985 * smoothstep(lip_y - 0.03, lip_y + 0.22, wy);
    ALBEDO = col;
}
"""

func _skin() -> Material:
    if _skin_mat == null:
        var sh := Shader.new()
        sh.code = SKIN_SHADER
        var m := ShaderMaterial.new()
        m.shader = sh
        # under a modeled hand the arm takes the same lower, edge-darkened
        # light as the model's own shader, so wrist and hand are one skin
        if hand_tone or _model_kind() > 0:
            m.set_shader_parameter("tone", 1.0)
            m.set_shader_parameter("tone_tint", Vector3(TONE_TINT.r, TONE_TINT.g, TONE_TINT.b))
            m.set_shader_parameter("tone_wrap", TONE_WRAP)
            m.set_shader_parameter("tone_key_view", TONE_KEY_VIEW)
            m.set_shader_parameter("tone_edge", Vector3(TONE_EDGE.r, TONE_EDGE.g, TONE_EDGE.b))
            m.set_shader_parameter("tone_edge_amount", TONE_EDGE_AMOUNT)
            m.set_shader_parameter("tone_arm_level", TONE_ARM_LEVEL)
        _skin_mat = m
    return _skin_mat

## Smooth tube for the being's arms and hands: rings of `sides` points round
## `pts` (mostly along Y), an ellipse rx across X and rz through Z, colours
## blended ring to ring, each end closed by a rounded dome `dome0`/`dome1`
## long (0 leaves it open). `arch` (per ring) lifts each point by arch * |x|
## on the little-finger side (-X) and a third of that on the index side, so
## the palm's knuckle line arches like the photos; `bend` (per ring) lets the
## X edges dip toward +Z (a nail's curve across the finger, the domed back
## of the hand). Vertices are shared and indexed, so generate_normals shades
## it round, with no facets.
static func _tube(st: SurfaceTool, base: int, pts: Array, rx: Array, rz: Array, cols: Array, sides: int, dome0: float = 0.0, dome1: float = 0.0, arch: Array = [], bend: Array = [], palm_cols: Array = [], up_arm: Array = []) -> int:
    # each ring: [centre, rx, rz, arch, bend, colour, palm-side colour, up the arm]
    var rs: Array = []
    var n := pts.size()
    # `up_arm` (per ring, the last repeating; 0 without) is how far up the
    # arm the ring is, 0 at the wrist and the hand, 1 from the elbow up
    var arm_at := func(i: int) -> float: return float(up_arm[mini(i, up_arm.size() - 1)]) if not up_arm.is_empty() else 0.0
    # `palm_cols` (per ring, the last repeating) tints the +Z half of each
    # ring: the palm side blushes, the back keeps the ring's own colour
    var col_at := func(i: int) -> Color: return cols[mini(i, cols.size() - 1)]
    var palm_at := func(i: int) -> Color: return palm_cols[mini(i, palm_cols.size() - 1)] if not palm_cols.is_empty() else col_at.call(i)
    var arch_at := func(i: int) -> float: return float(arch[i]) if i < arch.size() else 0.0
    var bend_at := func(i: int) -> float: return float(bend[i]) if i < bend.size() else 0.0
    if dome0 > 0.0:
        var d0: Vector3 = ((pts[0] as Vector3) - (pts[1] as Vector3)).normalized()
        for k in range(4):
            var t := (0.12 + 0.88 * float(k) / 4.0) * PI * 0.5
            rs.append([(pts[0] as Vector3) + d0 * dome0 * cos(t), float(rx[0]) * sin(t), float(rz[0]) * sin(t), arch_at.call(0), bend_at.call(0) * sin(t), col_at.call(0), palm_at.call(0), arm_at.call(0)])
    for i in range(n):
        rs.append([pts[i], float(rx[i]), float(rz[i]), arch_at.call(i), bend_at.call(i), col_at.call(i), palm_at.call(i), arm_at.call(i)])
    if dome1 > 0.0:
        var d1: Vector3 = ((pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)).normalized()
        var cl: Color = col_at.call(n - 1)
        for k in range(1, 5):
            var t := (1.0 - 0.88 * float(k) / 4.0) * PI * 0.5
            rs.append([(pts[n - 1] as Vector3) + d1 * dome1 * cos(t), float(rx[n - 1]) * sin(t), float(rz[n - 1]) * sin(t), arch_at.call(n - 1), bend_at.call(n - 1) * sin(t), cl, palm_at.call(n - 1), arm_at.call(n - 1)])
    for r in rs:
        for j in range(sides):
            var a := TAU * float(j) / float(sides)
            st.set_color((r[5] as Color).lerp(r[6], smoothstep(0.0, 0.6, sin(a))))
            st.set_uv(Vector2(float(r[7]), 0.0))
            var x := cos(a) * float(r[1])
            var y := float(r[3]) * (-x if x < 0.0 else x * 0.33)
            var cx := cos(a)
            var z := sin(a) * float(r[2]) + float(r[4]) * cx * cx
            st.add_vertex((r[0] as Vector3) + Vector3(x, y, z))
    for i in range(rs.size() - 1):
        for j in range(sides):
            var k := (j + 1) % sides
            var a0 := base + i * sides + j
            var a1 := base + i * sides + k
            var b0 := base + (i + 1) * sides + j
            var b1 := base + (i + 1) * sides + k
            st.add_index(a0)
            st.add_index(b1)
            st.add_index(a1)
            st.add_index(a0)
            st.add_index(b0)
            st.add_index(b1)
    var count := rs.size() * sides
    # the poles: one vertex closing each dome
    if dome0 > 0.0:
        var d0: Vector3 = ((pts[0] as Vector3) - (pts[1] as Vector3)).normalized()
        st.set_color((col_at.call(0) as Color).lerp(palm_at.call(0), 0.5))
        st.set_uv(Vector2(arm_at.call(0), 0.0))
        st.add_vertex((pts[0] as Vector3) + d0 * dome0)
        for j in range(sides):
            st.add_index(base + count)
            st.add_index(base + j)
            st.add_index(base + (j + 1) % sides)
        count += 1
    if dome1 > 0.0:
        var d1: Vector3 = ((pts[n - 1] as Vector3) - (pts[n - 2] as Vector3)).normalized()
        st.set_color((col_at.call(n - 1) as Color).lerp(palm_at.call(n - 1), 0.5))
        st.set_uv(Vector2(arm_at.call(n - 1), 0.0))
        st.add_vertex((pts[n - 1] as Vector3) + d1 * dome1)
        var last := base + (rs.size() - 1) * sides
        for j in range(sides):
            st.add_index(base + count)
            st.add_index(last + (j + 1) % sides)
            st.add_index(last + j)
        count += 1
    return base + count

static func _smooth_begin() -> SurfaceTool:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    return st

static func _smooth_finish(st: SurfaceTool) -> ArrayMesh:
    st.generate_normals()
    # generate_normals hands back loose triangles: share the corners again
    st.index()
    return st.commit()

## The same mesh reflected across x = 0 (a left hand from a right one):
## positions and normals mirrored, the winding turned so it still faces out.
static func _mirrored(mesh: ArrayMesh) -> ArrayMesh:
    var arr: Array = mesh.surface_get_arrays(0)
    var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
    for i in range(vs.size()):
        vs[i] = Vector3(-vs[i].x, vs[i].y, vs[i].z)
    for i in range(ns.size()):
        ns[i] = Vector3(-ns[i].x, ns[i].y, ns[i].z)
    arr[Mesh.ARRAY_VERTEX] = vs
    arr[Mesh.ARRAY_NORMAL] = ns
    arr[Mesh.ARRAY_TANGENT] = null
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    for i in range(0, idx.size(), 3):
        var t := idx[i + 1]
        idx[i + 1] = idx[i + 2]
        idx[i + 2] = t
    arr[Mesh.ARRAY_INDEX] = idx
    var out := ArrayMesh.new()
    out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    return out

func _build_meshes() -> void:
    if not _meshes.is_empty():
        return
    # Silhouettes stay round (user 2026-11-03: the angles should not show):
    # 14-24 sided rings, more rings where the outline curves, shared
    # vertices so the shading runs smooth over the whole hand.
    var st := _smooth_begin()
    # forearm, built one unit long from the wrist (0) up to the elbow (1);
    # the rig stretches it along Y to the real length. Slim at the wrist,
    # swelling softly toward the elbow, a flat oval that turns with the hand.
    var wr := _wrist_half()
    var ph := _palm_half()
    var wd := _wide()
    var fw: Array = ANGLE_FOREARM if hand_angle else [1.14, 1.3, 1.34, 1.26]
    _tube(st, 0, [Vector3(0, -0.03, 0), Vector3(0, 0.06, 0), Vector3(0, 0.2, 0), Vector3(0, 0.5, 0), Vector3(0, 0.8, 0), Vector3(0, 1.0, 0)], [wr * 0.98, wr * 1.04, wr * float(fw[0]), wr * float(fw[1]), wr * float(fw[2]), wr * float(fw[3])], [wr * 0.64, wr * 0.68, wr * 0.8, wr * 1.0, wr * 1.06, wr * 1.06], [SKIN, SKIN, SKIN, SKIN, SKIN, SKIN_SHADE], 18, 0.0, 0.0, [], [], [], [0.0, 0.0, 0.15, 0.6, 0.95, 1.0])
    _meshes["fore"] = _smooth_finish(st)
    # upper arm, built one unit long from the elbow (0) up to the shoulder in
    # the duct (1); slim, round, a little fuller toward the shoulder
    st = _smooth_begin()
    _tube(st, 0, [Vector3(0, -0.02, 0), Vector3(0, 0.25, 0), Vector3(0, 0.6, 0), Vector3(0, 1.0, 0), Vector3(0, 1.3, 0)], [0.027 * wd, 0.03 * wd, 0.032 * wd, 0.033 * wd, 0.033 * wd], [0.026 * wd, 0.029 * wd, 0.031 * wd, 0.032 * wd, 0.032 * wd], [SKIN_SHADE, SKIN, SKIN, SKIN_SHADE, SKIN_SHADE], 18, 0.0, 0.0, [], [], [], [1.0])
    _meshes["upper"] = _smooth_finish(st)
    # the elbow, a soft round joint where the two meet
    st = _smooth_begin()
    _tube(st, 0, [Vector3(0, -0.01, 0), Vector3(0, 0.01, 0)], [0.0275 * wd, 0.0275 * wd], [0.027 * wd, 0.027 * wd], [SKIN_SHADE], 18, 0.017 * wd, 0.017 * wd, [], [], [], [1.0])
    _meshes["elbow"] = _smooth_finish(st)
    # wrist and palm: the slim wrist widening in a soft curve to the
    # knuckles, its end in a gentle arc down toward the little finger and
    # rounded off; the back of the hand domed, the palm side fuller. The
    # thenar mound carries the thumb out of the palm with a thin web to the
    # index root. No separate knuckle bumps: only a flush of colour there.
    st = _smooth_begin()
    var ys := [0.016, 0.006, -0.006, -0.019, -0.032, -0.045, -0.057, -0.066, -0.073, -0.079]
    var rx := [wr * 0.9, wr * 0.92, wr * 0.97, ph * 0.84, ph * 0.9, ph * 0.95, ph * 0.985, ph, ph * 0.985, ph * 0.94]
    var rz := [wr * 0.6, wr * 0.6, 0.0118, 0.0121, 0.0124, 0.0124, 0.012, 0.0114, 0.0107, 0.0099]
    var bend := [0.0, 0.0004, 0.0016, 0.0026, 0.0032, 0.0034, 0.0032, 0.0028, 0.0022, 0.0016]
    var arch := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.07, 0.16, 0.24]
    var pts: Array = []
    for k in range(ys.size()):
        pts.append(Vector3(0, float(ys[k]), 0.0005))
    var cols: Array = []
    var pcols: Array = []
    for k in range(ys.size()):
        cols.append(SKIN if k < ys.size() - 2 else SKIN_KNUCKLE)
        # the wrist stays pale; the palm blushes, most at its heel and under the knuckles
        pcols.append(SKIN if k < 2 else SKIN_PAD if k == 3 or k == ys.size() - 3 else SKIN_PALM)
    var vi := _tube(st, 0, pts, rx, rz, cols, 24, 0.0, 0.0065, arch, bend, pcols)
    # the thenar mound along the thumb's metacarpal, its ball the rosiest
    var tr := _thumb_root()
    vi = _tube(st, vi, [Vector3(0.008 * wd, -0.002, 0.003), Vector3(0.0145 * wd, -0.013, 0.0052), Vector3(0.0205 * wd, -0.025, 0.0064), Vector3(0.025 * wd, -0.034, 0.0066), tr], [0.0085, 0.0108, 0.0108, 0.0094, 0.0082], [0.0068, 0.0084, 0.0086, 0.0082, 0.0076], [SKIN], 16, 0.004, 0.004, [], [], [SKIN_PALM, SKIN_PAD, SKIN_PAD, SKIN_PALM, SKIN_PALM])
    # the web from the thumb's root to the index knuckle, thin and soft
    vi = _tube(st, vi, [tr + Vector3(0.001, -0.004, -0.0006), Vector3(0.0262 * wd, -0.054, 0.004), Vector3(0.0232 * wd, -0.066, 0.0026)], [0.0066, 0.0056, 0.0042], [0.0044, 0.0038, 0.0032], [SKIN], 14, 0.003, 0.003, [], [], [SKIN_PALM])
    _meshes["palm"] = _smooth_finish(st)
    _meshes["palm_l"] = _mirrored(_meshes["palm"])
    # the palm's skin under the item seat: the highest palm-side point there
    var top := -1.0
    var top_angle := -1.0
    for v in (_meshes["palm"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
        if absf(v.x - SEAT.x) < 0.009 and absf(v.y - SEAT.y) < 0.009:
            top = maxf(top, v.z)
        if absf(v.x - ANGLE_SEAT.x) < 0.009 and absf(v.y - ANGLE_SEAT.y) < 0.009:
            top_angle = maxf(top_angle, v.z)
    _seat_z = top if top > 0.0 else 0.012
    _angle_seat_z = top_angle if top_angle > 0.0 else _seat_z
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var r := _finger_r(i)
        var tp := _taper()
        var rm := lerpf(r, r * tp, 0.48)
        var rd := lerpf(r, r * tp, 0.78)
        # both ends of a joint share one radius (see _bone_mesh)
        _meshes["f%d_0" % i] = _bone_mesh(length * PHALANX[0], r, rm, false, SKIN_CREASE)
        _meshes["f%d_1" % i] = _bone_mesh(length * PHALANX[1], rm, rd, false, SKIN)
        _meshes["f%d_2" % i] = _bone_mesh(length * PHALANX[2], rd, r * tp, true, SKIN)
    var thr := _thumb_r()
    _meshes["thumb_p"] = _bone_mesh(THUMB_LEN * 0.53, float(thr[0]), float(thr[1]), false, SKIN)
    _meshes["thumb_d"] = _bone_mesh(THUMB_LEN * 0.47, float(thr[1]), float(thr[2]), true, SKIN)

## One finger segment hanging down -Y from its joint: a 16-sided tube a
## little wider than deep, tapering from r0 to r1, its far joint faintly
## flushed (the knuckle) and its root ring `root_col` (the crease at the
## finger root); the palm side blushes. Each joint is a ball: the two
## segments meeting there end in the same ring (r * 1.02 wide, r * 0.86
## deep) and each closes with a dome as long as that depth, centred on the
## pivot, so in the plane the joint bends in both ends are the same circle
## and a bent finger shows neither a notch on its back nor a step under it.
## The tip segment swells into a soft pad on the palm side, ends in a
## rounded tip and carries a rounded almond nail on its back (-Z): curved
## across the finger, a pale moon at the cuticle, the far 0.54 of the
## segment long, 0.88 of the fingertip wide, its free edge 1.8 mm past the
## tip.
func _bone_mesh(length: float, r0: float, r1: float, tip: bool, root_col: Color) -> ArrayMesh:
    var st := _smooth_begin()
    var d0 := 0.86
    if tip:
        var py := [0.0, -length * 0.3, -length * 0.62, -length * 0.85, -length]
        var px := [r0 * 1.02, lerpf(r0, r1, 0.4) * 1.01, r1 * 1.02, r1 * 0.94, r1 * 0.74]
        var pz := [r0 * d0, lerpf(r0, r1, 0.4) * d0, r1 * 0.9, r1 * 0.84, r1 * 0.66]
        var pts: Array = []
        for k in range(py.size()):
            # the pad: the tip's centre shifts toward the palm side
            pts.append(Vector3(0, float(py[k]), r1 * 0.12 * float(k) / float(py.size() - 1)))
        var vi := _tube(st, 0, pts, px, pz, [root_col, SKIN, SKIN, SKIN_BLUSH, SKIN_BLUSH], 16, r0 * d0, r1 * 0.62, [], [], [SKIN_PALM, SKIN_PALM, SKIN_PALM, SKIN_PAD, SKIN_PAD])
        # the nail: a rounded almond on the back of the tip, following its surface
        var w := r1 * 0.88
        var y_c := -length * 0.46
        var y_end := -length - r1 * 0.62 - 0.0018
        var ts := [0.0, 0.05, 0.1, 0.3, 0.55, 0.75, 0.9, 1.0]
        var ws := [0.66, 0.8, 0.92, 1.0, 0.99, 0.9, 0.7, 0.42]
        var npts: Array = []
        var nrx: Array = []
        var nrz: Array = []
        var nbend: Array = []
        var ncol: Array = []
        for k in range(ts.size()):
            var t: float = ts[k]
            var y := lerpf(y_c, y_end, t)
            # the finger's back surface under the nail (z < 0), the free edge
            # carrying on a touch past the round tip
            var surf := lerpf(lerpf(r0, r1, 0.4) * d0, r1 * 0.88, clampf(t * 1.6, 0.0, 1.0))
            if t > 0.7:
                surf = lerpf(r1 * 0.88, r1 * 0.5, (t - 0.7) / 0.3)
            npts.append(Vector3(0, y, -surf - 0.0004 + r1 * 0.12 * clampf(-y / length, 0.0, 1.0)))
            nrx.append(w * float(ws[k]))
            nrz.append(0.00055)
            nbend.append(w * 0.32 * float(ws[k]))
            ncol.append(NAIL_MOON if k <= 1 else NAIL_TIP if k >= ts.size() - 2 else NAIL)
        _tube(st, vi, npts, nrx, nrz, ncol, 14, 0.0012, 0.0008, [], nbend)
    else:
        var pts := [Vector3(0, 0.0, 0), Vector3(0, -length * 0.3, 0), Vector3(0, -length * 0.7, 0), Vector3(0, -length, 0)]
        _tube(st, 0, pts, [r0 * 1.02, lerpf(r0, r1, 0.3) * 0.96, lerpf(r0, r1, 0.7) * 0.96, r1 * 1.02], [r0 * d0, lerpf(r0, r1, 0.3) * d0 * 0.94, lerpf(r0, r1, 0.7) * d0 * 0.94, r1 * d0], [root_col, SKIN, SKIN, SKIN_KNUCKLE], 16, r0 * d0, r1 * d0, [], [], [SKIN_PALM])
    return _smooth_finish(st)

func _new_rig(index: int) -> Dictionary:
    _build_meshes()
    var skin := _skin()
    var root := K.pivot(_arms, "Hand%d" % index)
    var upper := K.add_mesh(root, "UpperArm", _meshes["upper"], skin)
    var fore := K.add_mesh(root, "Forearm", _meshes["fore"], skin)
    var elbow := K.add_mesh(root, "Elbow", _meshes["elbow"], skin)
    var hand := K.pivot(root, "Palm")
    var palm := K.add_mesh(hand, "Hand", _meshes["palm"], skin)
    var fingers: Array = []
    for i in range(FINGERS.size()):
        var f: Array = FINGERS[i]
        var length: float = f[2]
        var root_y := -PALM_LEN * float(f[1])
        var prox := K.pivot(hand, "Finger%d" % i, Vector3(_finger_x(i), root_y + MCP_IN, 0.0))
        K.add_mesh(prox, "Bone", _meshes["f%d_0" % i], skin)
        var mid := K.pivot(prox, "Mid", Vector3(0, -length * PHALANX[0], 0))
        K.add_mesh(mid, "Bone", _meshes["f%d_1" % i], skin)
        var tip := K.pivot(mid, "Tip", Vector3(0, -length * PHALANX[1], 0))
        K.add_mesh(tip, "Bone", _meshes["f%d_2" % i], skin)
        fingers.append([prox, mid, tip, float(f[5])])
    # the thumb leaves the thenar mound and lies open beside the item
    var tp := K.pivot(hand, "Thumb", _thumb_root())
    K.add_mesh(tp, "Bone", _meshes["thumb_p"], skin)
    var td := K.pivot(tp, "Tip", Vector3(0, -THUMB_LEN * 0.53, 0))
    K.add_mesh(td, "Bone", _meshes["thumb_d"], skin)
    var slot := K.pivot(hand, "Offer%d" % index, Vector3(SEAT.x, SEAT.y, _seat_z))
    # each hand its own relaxed cascade (index to little), so no two are clones
    var vary: Array = []
    for i in range(4):
        vary.append(sin(float(index) * 1.7 + float(i) * 2.9 + 0.6) * 0.14)
    var rig := {"root": root, "upper": upper, "fore": fore, "elbow": elbow, "hand": hand, "palm": palm, "slot": slot, "fingers": fingers, "thumb": [tp, td], "rot": Quaternion.IDENTITY, "chir": 0.0, "mirror": 1.0, "index": index, "turn": 1.0, "lag": 0.0,
        # each arm its own: forearm droop, its sideways turn, the palm's tilt
        "bend": ELBOW_ANGLE + sin(float(index) * 2.1 + 0.3) * ELBOW_VARY,
        "yaw": sin(float(index) * 1.37 + 1.1) * 0.35,
        "tilt": sin(float(index) * 2.9 + 0.7) * 0.12,
        "roll": sin(float(index) * 2.3 + 0.4) * 0.14, "vary": vary}
    if _model_kind() > 0:
        _attach_model(rig)
    _set_chirality(rig, 1.0)
    # render layers: set_offer_items, the only caller, tags every arm after
    return rig

## A right hand (thumb on +X, c = 1) or a left one (c = -1): the palm mesh
## and the finger and thumb roots reflected, so every thumb opens outward.
func _set_chirality(rig: Dictionary, c: float) -> void:
    if float(rig["chir"]) == c:
        return
    rig["chir"] = c
    (rig["palm"] as MeshInstance3D).mesh = _meshes["palm"] if c > 0.0 else _meshes["palm_l"]
    for i in range(FINGERS.size()):
        var prox: Node3D = rig["fingers"][i][0]
        prox.position.x = _finger_x(i) * c
    var tp: Node3D = rig["thumb"][0]
    var troot := _thumb_root()
    tp.position = Vector3(troot.x * c, troot.y, troot.z)
    var slot: Node3D = rig["slot"]
    slot.position.x = SEAT.x * c
    if rig.has("models"):
        for mc in rig["models"]:
            (rig["models"][mc]["node"] as Node3D).visible = float(mc) == c

## Mirror a rotation for a left hand (reflect across x = 0).
static func _mirror_basis(b: Basis, c: float) -> Basis:
    if c > 0.0:
        return b
    var m := Basis.from_scale(Vector3(-1, 1, 1))
    return m * b * m

## --- Modeled hands (HAND_MODEL 1, 2, 3) ---------------------------------------
## The model stands in for the palm, fingers and thumb only. It hangs on the
## same hand pivot (wrist at 0, fingers -Y, palm +Z, thumb +X on what this
## file calls a right hand), so the arm, the offer row, the flip and the
## item seat run exactly as for the tube hand, whose own meshes are hidden
## but still posed (captures and tests read their pivots). Each rig carries
## one model per chirality and shows the one in use.
## The files are read as they are with GLTFDocument (no import step, so a
## candidate needs no .import files). The one that is picked should become
## an imported scene: a file read this way is not in an exported build.
const MODEL_DIR := "res://main/art/vent_hand_models/"
## Per model: the file for each chirality, the basis that lays the model's
## axes on the hand frame (a mirrored one for the Blender hand's other
## side), the model point that goes to the wrist, the scale (the Blender
## hand to the tube hand's wrist-to-fingertip length; the broader XR hand a
## little under it, so three still fit the view), how far up the model's own
## arm stub is drawn (model +Z; the rest is cut away inside the being's
## forearm, which bends at the wrist where the stub cannot), the palm's normal in model space per
## chirality, and how curled the model stands at rest in units of the tube
## hand's curl (the XR hand rests about as curled as the open offer).
## XR Tools: fingers -Z, thumb +Y, the left hand's palm +X. By this file's
## handedness (thumb +X seen palm on, fingers down) its "L" file is c = 1.
## Blender: fingers -Z, back of the hand +Y, thumb -X.
## vent_hand.glb is built in this file's hand frame already (its arm stub
## runs up +Y: "cut_axis"). "own": the surface takes the model's vertex
## colours as they are (painted to this being's palette by its builder).
const MODELS := {
    1: {
        "files": {1.0: "godot_xr_tools_hands/Hand_Nails_low_L.gltf", -1.0: "godot_xr_tools_hands/Hand_Nails_low_R.gltf"},
        "basis": {1.0: [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], -1.0: [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]},
        "normal": {1.0: Vector3(1, 0, 0), -1.0: Vector3(-1, 0, 0)},
        "pivot": Vector3(0, -0.008, 0.02), "scale": 0.76, "rest_curl": 0.5, "cut": 0.02,
        "fingers": ["Index", "Middle", "Ring", "Little"], "joints": ["_Proximal", "_Intermediate", "_Distal"],
        "thumb": ["Thumb_Proximal", "Thumb_Distal"], "suffix": {1.0: "_L", -1.0: "_R"},
        "texture": "godot_xr_tools_hands/textures/caucasian_realistic_baseColor.png",
    },
    2: {
        "files": {1.0: "blender_made/slender_hand_r.glb", -1.0: "blender_made/slender_hand_r.glb"},
        "basis": {1.0: [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], -1.0: [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)]},
        "normal": {1.0: Vector3(0, -1, 0), -1.0: Vector3(0, -1, 0)},
        "pivot": Vector3(0, 0, 0.004), "scale": 0.95, "rest_curl": 0.35, "cut": 0.012,
        "fingers": ["index", "middle", "ring", "pinky"], "joints": ["_1", "_2", "_3"],
        "thumb": ["thumb_2", "thumb_3"], "suffix": {1.0: "", -1.0: ""},
        "texture": "",
    },
    3: {
        "files": {1.0: "blender_made/vent_hand.glb", -1.0: "blender_made/vent_hand.glb"},
        "basis": {1.0: [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], -1.0: [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]},
        "normal": {1.0: Vector3(0, 0, 1), -1.0: Vector3(0, 0, 1)},
        "pivot": Vector3.ZERO, "scale": 1.0, "rest_curl": 0.2, "cut": 0.012, "cut_axis": Vector3(0, 1, 0),
        "fingers": ["index", "middle", "ring", "little"], "joints": ["_1", "_2", "_3"],
        "thumb": ["thumb_2", "thumb_3"], "suffix": {1.0: "", -1.0: ""},
        "texture": "", "own": true,
    },
}
## Screen grid the model's vertices snap to, the kit's PS1 setting
## (FDKPs1Settings.vertex_snap_precision), and the side of the XR hand's
## skin texture after it is cut down to coarse texels.
const MODEL_SNAP := 130.0
const MODEL_TEXELS := 128
var _model_mats: Array = []
var _model_tex: ImageTexture
var _model_tex_mean := Vector3.ONE

## The model in use: HAND_MODEL when its files are there, else 0.
static func _model_kind() -> int:
    if not MODELS.has(hand_model):
        return 0
    for c in MODELS[hand_model]["files"]:
        if not FileAccess.file_exists(MODEL_DIR + str(MODELS[hand_model]["files"][c])):
            return 0
    return hand_model

## The model's skin: the vent being's own tones and soft wrapped light (the
## TONE candidate's range, so the open palm is not one white against the
## tiles, and its warm darker edge), unshaded like the arm. PS1 side: the
## vertices snap to the kit's screen grid and the XR hand's texture is cut to
## 128 texels, read unfiltered, as light and dark on the being's skin colour
## (its own orange is not used). The Blender hand's painted flush picks
## between the being's skin and pad colours; its nail surface takes the
## being's nail colour and lacquer.
const MODEL_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 skin = vec3(1.0, 0.885, 0.83);
uniform vec3 pad = vec3(1.0, 0.82, 0.80);
uniform vec3 nail_col = vec3(0.85, 0.44, 0.5);
uniform float nail = 0.0;
uniform float use_tex = 0.0;
uniform sampler2D detail : filter_nearest, repeat_disable;
uniform vec3 detail_mean = vec3(1.0);
uniform float detail_amount = 0.7;
uniform float use_paint = 0.0;
uniform vec2 paint_g = vec2(0.557, 0.369);
uniform float snap = 130.0;
uniform float facing = 1.0;
uniform float cut = 1000.0;
uniform vec3 cut_axis = vec3(0.0, 0.0, 1.0);
uniform float use_own = 0.0;
uniform vec3 fill_dir = vec3(-0.6, -0.2, 0.5);
uniform vec3 warm = vec3(1.0, 0.5, 0.42);
uniform float sss = 0.24;
uniform float sheen = 0.05;
uniform float nail_gloss = 0.7;
uniform float lip_y = 1000.0;
uniform vec3 tone_tint = vec3(1.0);
uniform vec2 tone_wrap = vec2(0.7, 1.0);
uniform vec3 tone_key_view = vec3(-0.6, 0.3, 0.74);
uniform vec3 tone_edge = vec3(0.93, 0.7, 0.66);
uniform float tone_edge_amount = 0.58;
varying vec3 wn;
varying float wy;
varying float up_stub;
void vertex() {
    wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
    up_stub = dot(VERTEX, cut_axis);
    vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
    if (clip.w > 0.0001) {
        vec2 ndc = floor(clip.xy / clip.w * snap + 0.5) / snap;
        clip.xy = ndc * clip.w;
    }
    POSITION = clip;
}
void fragment() {
    if (up_stub > cut) { discard; }
    // a mirrored model (facing -1) comes in with its faces the other way round
    vec3 n = normalize(wn) * facing;
    if (!FRONT_FACING) { n = -n; }
    vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    vec3 l = normalize((INV_VIEW_MATRIX * vec4(tone_key_view, 0.0)).xyz);
    float wrap = pow(clamp(dot(n, l) * 0.5 + 0.5, 0.0, 1.0), 1.3);
    float fill = clamp(dot(n, normalize(fill_dir)) * 0.5 + 0.5, 0.0, 1.0);
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.4);
    float flush = use_paint * clamp((paint_g.x - COLOR.g) / (paint_g.x - paint_g.y), 0.0, 1.0);
    vec3 base = mix(mix(skin, pad, flush), COLOR.rgb, use_own);
    if (use_tex > 0.5) {
        vec3 d = texture(detail, UV).rgb / detail_mean;
        base *= mix(vec3(1.0), clamp(d, 0.6, 1.25), detail_amount);
    }
    base = mix(base * tone_tint, nail_col, nail);
    vec3 col = base * mix(tone_wrap.x, tone_wrap.y, wrap) * mix(0.97, 1.03, fill);
    col += base * warm * (sss + 0.1 * flush) * (1.0 - wrap * (1.0 - 0.5 * flush)) * (1.0 - nail);
    col = mix(col, col * mix(vec3(1.0), warm * 1.3, 0.55), fres * 0.4 * (1.0 - nail));
    col = mix(col, col * tone_edge, tone_edge_amount * pow(1.0 - ndv, 1.7) * (1.0 - nail));
    vec3 h = normalize(l + v);
    float nh = max(dot(n, h), 0.0);
    col += vec3(1.0, 0.97, 0.95) * pow(nh, 14.0) * sheen * (1.0 - nail);
    col += vec3(1.0) * (pow(nh, 70.0) * nail_gloss + pow(nh, 12.0) * 0.12 + fres * 0.3) * nail;
    col *= 1.0 - 0.985 * smoothstep(lip_y - 0.03, lip_y + 0.22, wy);
    ALBEDO = col;
}
"""

## Material for a model surface (`is_nail`: the Blender hand's nail plates;
## `facing` -1 for the mirrored instance).
func _model_material(spec: Dictionary, is_nail: bool, facing: float) -> ShaderMaterial:
    var sh: Shader = _meshes.get("model_shader")
    if sh == null:
        sh = Shader.new()
        sh.code = MODEL_SHADER
        _meshes["model_shader"] = sh
    var m := ShaderMaterial.new()
    m.shader = sh
    m.set_shader_parameter("skin", Vector3(SKIN.r, SKIN.g, SKIN.b))
    m.set_shader_parameter("pad", Vector3(SKIN_PAD.r, SKIN_PAD.g, SKIN_PAD.b))
    m.set_shader_parameter("nail_col", Vector3(NAIL.r, NAIL.g, NAIL.b))
    m.set_shader_parameter("nail", 1.0 if is_nail else 0.0)
    m.set_shader_parameter("snap", MODEL_SNAP)
    m.set_shader_parameter("facing", facing)
    m.set_shader_parameter("cut", float(spec["cut"]))
    m.set_shader_parameter("cut_axis", spec.get("cut_axis", Vector3(0, 0, 1)))
    m.set_shader_parameter("use_own", 1.0 if spec.get("own", false) and not is_nail else 0.0)
    m.set_shader_parameter("tone_tint", Vector3(TONE_TINT.r, TONE_TINT.g, TONE_TINT.b))
    m.set_shader_parameter("tone_wrap", TONE_WRAP)
    m.set_shader_parameter("tone_key_view", TONE_KEY_VIEW)
    m.set_shader_parameter("tone_edge", Vector3(TONE_EDGE.r, TONE_EDGE.g, TONE_EDGE.b))
    m.set_shader_parameter("tone_edge_amount", TONE_EDGE_AMOUNT)
    var tex_file := str(spec["texture"])
    if tex_file != "" and not is_nail:
        if _model_tex == null:
            # read as bytes: the file needs no import, and the coarse copy is the texel look
            var img := Image.new()
            if img.load_png_from_buffer(FileAccess.get_file_as_bytes(MODEL_DIR + tex_file)) == OK:
                img.resize(MODEL_TEXELS, MODEL_TEXELS, Image.INTERPOLATE_BILINEAR)
                var sum := Vector3.ZERO
                for y in range(MODEL_TEXELS):
                    for x in range(MODEL_TEXELS):
                        var px := img.get_pixel(x, y)
                        sum += Vector3(px.r, px.g, px.b)
                _model_tex_mean = sum / float(MODEL_TEXELS * MODEL_TEXELS)
                _model_tex = ImageTexture.create_from_image(img)
        if _model_tex != null:
            m.set_shader_parameter("use_tex", 1.0)
            m.set_shader_parameter("detail", _model_tex)
            m.set_shader_parameter("detail_mean", _model_tex_mean)
    elif not is_nail:
        m.set_shader_parameter("use_paint", 1.0)
    _model_mats.append(m)
    return m

## Hang the model on the rig's hand pivot, one per chirality, and hide the
## tube hand. The item seat rises to the model's own palm skin.
func _attach_model(rig: Dictionary) -> void:
    var spec: Dictionary = MODELS[_model_kind()]
    var hand: Node3D = rig["hand"]
    var models := {}
    var seat_z := -1.0
    if not _meshes.has("model_skin1"):
        for facing in [1, -1]:
            _meshes["model_skin%d" % facing] = _model_material(spec, false, float(facing))
            _meshes["model_nail%d" % facing] = _model_material(spec, true, float(facing))
    for c in [1.0, -1.0]:
        var doc := GLTFDocument.new()
        var state := GLTFState.new()
        if doc.append_from_file(MODEL_DIR + str(spec["files"][c]), state) != OK:
            continue
        var scene := doc.generate_scene(state) as Node3D
        if scene == null:
            continue
        var found := scene.find_children("*", "Skeleton3D", true, false)
        if found.is_empty():
            scene.free()
            continue
        var skel := found[0] as Skeleton3D
        var ax: Array = spec["basis"][c]
        var b := Basis(ax[0], ax[1], ax[2]) * float(spec["scale"])
        scene.name = "Model" + ("R" if c > 0.0 else "L")
        scene.transform = Transform3D(b, -(b * (spec["pivot"] as Vector3)))
        var face := 1 if b.determinant() > 0.0 else -1
        hand.add_child(scene)
        for n in scene.find_children("*", "MeshInstance3D", true, false):
            var mi := n as MeshInstance3D
            for si in range(mi.mesh.get_surface_count()):
                var src := mi.mesh.surface_get_material(si)
                var is_nail := src != null and src.resource_name.contains("nail")
                mi.set_surface_override_material(si, _meshes["model_nail%d" % face] if is_nail else _meshes["model_skin%d" % face])
                if c > 0.0 and not is_nail:
                    for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
                        var hv: Vector3 = scene.transform * v
                        if absf(hv.x - SEAT.x) < 0.009 and absf(hv.y - SEAT.y) < 0.009:
                            seat_z = maxf(seat_z, hv.z)
        # each joint's bend axis in its own frame: across the bone, turning it toward the palm
        var bones: Array = []
        var normal: Vector3 = spec["normal"][c]
        var names: Array = []
        for f in spec["fingers"]:
            for j in spec["joints"]:
                names.append(str(f) + str(j) + str(spec["suffix"][c]))
        for t in spec["thumb"]:
            names.append(str(t) + str(spec["suffix"][c]))
        for bn in names:
            var bi := skel.find_bone(bn)
            if bi < 0:
                bones.append([])
                continue
            var g := skel.get_bone_global_rest(bi).basis.orthonormalized()
            # the bone's line: on to its child (the files disagree on which local axis that is)
            var along := g.y
            var kids := skel.get_bone_children(bi)
            if not kids.is_empty():
                along = skel.get_bone_global_rest(kids[0]).origin - skel.get_bone_global_rest(bi).origin
            var axis := along.normalized().cross(normal)
            axis = g.inverse() * (axis.normalized() if axis.length() > 0.001 else Vector3.RIGHT)
            bones.append([bi, skel.get_bone_rest(bi).basis.get_rotation_quaternion(), axis.normalized()])
        models[c] = {"node": scene, "skel": skel, "bones": bones}
    if models.is_empty():
        return
    rig["models"] = models
    rig["model_rest"] = float(spec["rest_curl"])
    (rig["palm"] as MeshInstance3D).visible = false
    for f in rig["fingers"]:
        (f[0] as Node3D).visible = false
    (rig["thumb"][0] as Node3D).visible = false
    if seat_z > 0.0:
        (rig["slot"] as Node3D).position.z = seat_z

## The tube hand's finger bends (rig["flex<i>"], set in _pose_fingers) laid
## on the model's bones, less the curl the model already stands in at rest;
## the thumb closes with the grip (`thumb_curl` 0..1).
func _pose_model(rig: Dictionary, thumb_curl: float) -> void:
    var rest: float = rig["model_rest"]
    for c in rig["models"]:
        var m: Dictionary = rig["models"][c]
        if not (m["node"] as Node3D).visible:
            continue
        var skel: Skeleton3D = m["skel"]
        var bones: Array = m["bones"]
        for i in range(4):
            var flex: Array = rig.get("flex%d" % i, [0.0, 0.0, 0.0])
            var k: float = float(FINGERS[i][5])
            for j in range(3):
                var bone: Array = bones[i * 3 + j]
                if bone.is_empty():
                    continue
                var ang := float(flex[j]) - rest * k * float(JOINT_SHARE[j])
                skel.set_bone_pose_rotation(int(bone[0]), (bone[1] as Quaternion) * Quaternion(bone[2] as Vector3, ang))
        for t in range(2):
            var tb: Array = bones[12 + t]
            if not tb.is_empty():
                skel.set_bone_pose_rotation(int(tb[0]), (tb[1] as Quaternion) * Quaternion(tb[2] as Vector3, 0.45 * thumb_curl))

func item_node(index: int) -> Node3D:
    return _offers[index] if index >= 0 and index < _offers.size() else null

## Hands out (or on their way) now.
func hand_count() -> int:
    return _count if _arms != null and _arms.visible else 0

## Item kinds: spray_cheap, spray_expensive, barrier, knife, blender_box,
## saw_box, canary_feed, tumor_bag, junk (FPItemArt models, the same the
## player's hand carries to the belt). One hand comes out per item, however
## many there are. An empty list sends the arms back up.
func set_offer_items(kinds: Array) -> void:
    _wanted = not kinds.is_empty()
    if _wanted:
        _beg = false
    if kinds.is_empty():
        if _extend > 0.0 and is_inside_tree():
            _hand_to(0.0, 0.3, Tween.EASE_IN)
        else:
            set_offer_extend(0.0)
        return
    while _rigs.size() < kinds.size():
        _rigs.append(_new_rig(_rigs.size()))
    _offers.clear()
    _count = kinds.size()
    for i in range(_rigs.size()):
        var rig: Dictionary = _rigs[i]
        var slot: Node3D = rig["slot"]
        for ch in slot.get_children():
            slot.remove_child(ch)
            ch.queue_free()
        (rig["root"] as Node3D).visible = i < _count
        rig["rot"] = Quaternion.IDENTITY
        rig["turn"] = 1.0
        slot.visible = i < _count
        if i < _count:
            var item := FPItemArt.make(str(kinds[i]), i)
            slot.add_child(item)
            # the same render layers as the rest of the vent (the restroom tags them)
            FPItemArt.set_layers(item, _black_cover.layers)
            # lying in the palm: its middle over the seat, its underside on the skin
            # big things come smaller, so each still fits the open palm
            # lying on its broad side, its thinnest way up out of the palm
            var box := _box_of(item)
            if box.size.z > box.size.y * 1.1:
                item.rotate_x(PI * 0.5)
                box = _box_of(item)
            var fit := minf(1.0, minf(ITEM_SPAN / maxf(box.size.x, box.size.y), ITEM_BREADTH / maxf(0.001, minf(box.size.x, box.size.y))))
            item.scale = Vector3.ONE * fit
            var mid := box.get_center()
            item.position = -Vector3(mid.x, mid.y, box.position.z) * fit - Vector3(0, 0, SEAT_SINK / ITEM_SCALE)
            slot.rotation_degrees = Vector3(0, 0, -5.0 + 4.0 * float(i % 3))
            slot.scale = Vector3.ONE * ITEM_SCALE
            _offers.append(slot)
    _set_curl(0.0)
    # new hands come out holding as they will be seen
    _look_w = 1.0 if looking() else 0.0
    var lit := _black_cover.layers
    for n in _arms.find_children("*", "VisualInstance3D", true, false):
        (n as VisualInstance3D).layers = lit
    _snap = true
    _place_hands(0.0)

## An item's outline turned as it lies (all its meshes, before it is moved
## or scaled into place).
static func _box_of(item: Node3D) -> AABB:
    var box := AABB()
    var first := true
    for n in item.find_children("*", "MeshInstance3D", true, false):
        var mi := n as MeshInstance3D
        var t := Transform3D.IDENTITY
        var p: Node = mi
        while p != item and p != null:
            t = (p as Node3D).transform * t
            p = p.get_parent()
        var b: AABB = Transform3D(item.basis, Vector3.ZERO) * t * mi.get_aabb()
        box = b if first else box.merge(b)
        first = false
    return box

## Take the item in `index` (the player's hand picks it); the others are
## pulled back into the dark at once.
func take_item(index: int) -> void:
    _wanted = false
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    var slot: Node3D = item_node(index)
    # the player's hand closes on it about 0.3 s in; then it is gone from the palm
    _hand_tw.tween_interval(0.3)
    if slot != null:
        _hand_tw.tween_callback(func(): slot.visible = false)
    # the fingers fold in over the empty palm and the arms draw back up: at
    # its ease when calm, a snatch only when the being is frantic
    _hand_tw.tween_method(_set_curl, 0.0, lerpf(TAKE_GRIP, 1.0, _mood), lerpf(TAKE_GRIP_SECS, 0.16, _mood))
    _hand_tw.tween_method(set_offer_extend, _extend, 0.0, lerpf(TAKE_RISE_SECS, 0.42, _mood)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _set_curl(c: float) -> void:
    _curl = clampf(c, 0.0, 1.0)
    _pose_fingers()

## Capture only: fingers straight and together, thumb at its rest splay,
## to lay the hand beside the flat reference photos.
var flat_pose := false

## The thumb's rest pose for a hand of chirality `c`, its tip bent `flex` degrees.
static func _thumb_basis(c: float, tuck: float = 0.0) -> Basis:
    var pose := THUMB_POSE.lerp(TUCK_THUMB_POSE, tuck)
    var b := Basis.from_euler(Vector3(deg_to_rad(pose.x), 0.0, deg_to_rad(pose.z))) * Basis(Vector3.UP, deg_to_rad(THUMB_TWIST))
    return _mirror_basis(b, c)

## How far the thumb is drawn in beside the index (0 lying open, 1 tucked).
func _thumb_tuck() -> float:
    if hand_thumb or hand_grace:
        return 1.0
    return _look_w if hand_angle else 0.0

func _pose_fingers() -> void:
    if flat_pose:
        for rig in _rigs:
            var c: float = rig["chir"]
            for i in range(4):
                var f: Array = rig["fingers"][i]
                (f[0] as Node3D).basis = Basis(Vector3.BACK, deg_to_rad(float(FINGERS[i][4]) * 0.5 * c))
                for j in range(1, 3):
                    (f[j] as Node3D).rotation.x = 0.0
            (rig["thumb"][0] as Node3D).basis = _mirror_basis(Basis.from_euler(Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(24.0))) * Basis(Vector3.UP, deg_to_rad(THUMB_TWIST)), c)
            (rig["thumb"][1] as Node3D).rotation_degrees = Vector3(-4, 0, 0)
        return
    for ri in range(mini(_count, _rigs.size())):
        var rig: Dictionary = _rigs[ri]
        var c: float = rig["chir"]
        for i in range(4):
            var f: Array = rig["fingers"][i]
            var k: float = float(f[3]) + float(rig["vary"][i])
            # a slow breath through the fingers, quicker when the being is impatient
            var fidget := sin(_time * lerpf(1.6, 5.0, _mood) + i * 0.9 + ri * 1.7) * lerpf(0.02, 0.05, _mood)
            # hanging fingers trail a little curled until the palm has come up under them
            var cv := lerpf(lerpf(CURL_REST, LOOK_CURL, _look_w), CURL_GRIP, _curl) + fidget + float(rig["lag"])
            if _beg:
                # nothing in it: the fingers open wide and close on the air, over and over
                cv = lerpf(BEG_OPEN, BEG_CLOSE, _beg_grasp(i))
            # the fingers rise softly round the item in the palm (toward +Z)
            var flex := [cv * k * float(JOINT_SHARE[0]), cv * k * float(JOINT_SHARE[1]), cv * k * float(JOINT_SHARE[2])]
            var splay := float(FINGERS[i][4])
            if hand_grace and not _beg:
                # each finger its own height at rest; the grip, the trailing
                # curl and the breath come on top as before
                var rest := lerpf(CURL_REST, LOOK_CURL, _look_w)
                for j in range(3):
                    flex[j] = deg_to_rad(float(GRACE_FLEX[i][j])) * (1.0 + float(rig["vary"][i])) + (cv - rest) * k * float(JOINT_SHARE[j])
                splay = float(GRACE_SPLAY[i])
            if hand_angle and not _beg:
                # up close, lying across the view: each finger its own line
                var rest_a := lerpf(CURL_REST, LOOK_CURL, _look_w)
                for j in range(3):
                    flex[j] = lerpf(float(flex[j]), deg_to_rad(float(ANGLE_FLEX[i][j])) * (1.0 + float(rig["vary"][i])) + (cv - rest_a) * k * float(JOINT_SHARE[j]), _look_w)
                splay = lerpf(splay, float(ANGLE_SPLAY[i]), _look_w)
            (f[0] as Node3D).basis = Basis(Vector3.BACK, deg_to_rad(splay * c)) * Basis(Vector3.RIGHT, -float(flex[0]))
            for j in range(1, 3):
                (f[j] as Node3D).rotation.x = -float(flex[j])
            if rig.has("models"):
                rig["flex%d" % i] = flex
        var th: Array = rig["thumb"]
        var tc := _beg_grasp(0) if _beg else _curl
        var tuck := _thumb_tuck()
        (th[0] as Node3D).basis = _thumb_basis(c, tuck) * Basis(Vector3.RIGHT, -0.5 * tc)
        (th[1] as Node3D).rotation_degrees = Vector3(lerpf(-14.0, TUCK_THUMB_TIP, tuck) - 30.0 * tc, 0, 0)
        if rig.has("models"):
            _pose_model(rig, tc)

func _hand_to(target: float, secs: float, ease_type: Tween.EaseType) -> void:
    if _hand_tw != null:
        _hand_tw.kill()
    _hand_tw = create_tween()
    _hand_tw.tween_method(set_offer_extend, _extend, target, secs).set_trans(Tween.TRANS_SINE).set_ease(ease_type)

func _process(delta: float) -> void:
    _time += delta
    _step_glint()
    _step_jostle(delta)
    if not _spill.is_empty():
        step_spill(delta)
    if _arms != null and _arms.visible:
        _place_hands(delta)
        _pose_fingers()
    else:
        _snap = true

func _eye() -> Vector3:
    var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
    if cam == null:
        return Vector3(0.55, -1.0, 0.55)
    return to_local(cam.global_position)

## Middle of the hand cluster: HAND_AHEAD in front of the eye toward the
## vent and a little above it (higher when standing right under the vent),
## below the ceiling and within the arms' reach.
func _cluster_target(eye: Vector3) -> Vector3:
    var lip := Vector3(0, LIP_Y, 0)
    var h := Vector3(-eye.x, 0.0, -eye.z)
    var hd := h.length()
    var dir := h / hd if hd > 0.05 else Vector3.RIGHT
    var lift := lerpf(HAND_LIFT_UNDER, HAND_LIFT, clampf(hd / 0.9, 0.0, 1.0))
    var ahead := HAND_AHEAD + AHEAD_PER_HAND * float(maxi(_count - 3, 0))
    var t := eye + dir * minf(hd, ahead) + Vector3(0, lift, 0)
    var off := t - lip
    if off.length() > REACH_MAX:
        t = lip + off.normalized() * REACH_MAX
    t.y = minf(t.y, LIP_Y - BELOW_LIP)
    # over the open grate's side the hands hang below its lower edge
    if t.x < -SIZE:
        t.y = minf(t.y, LIP_Y - 0.78)
    return t

# --- the head in under the vent -------------------------------------------------

## Where the eye sits for the look (local: LOOK_BACK out from the vent toward
## where the head came from, LOOK_DOWN below the face) and how far along the
## view the wrists of 3 hands float; each hand past the third pushes them
## LOOK_AHEAD_PER_HAND further up to a full row and LOOK_AHEAD_PAST_ROW past
## it, so 8 still fit. The view rises at LOOK_RISE.
const LOOK_BACK := 0.6
const LOOK_DOWN := 0.84
const LOOK_RISE := 0.3
const LOOK_AHEAD := 0.4
const LOOK_AHEAD_PER_HAND := 0.07
const LOOK_AHEAD_PAST_ROW := 0.02
## The hands reach toward the eye from the wrist: the wrists float this much
## above the middle of the view so the open palms, not the forearms, are in
## the centre.
const LOOK_WRIST_UP := 0.07
## The fan bends round the eye less up close, so the outer hands stay in frame.
const LOOK_ARC := 0.5
## Up close the hands stand this share of SPACING apart.
const LOOK_SPREAD := 0.88
## Up close the items are this much of their real size: the hand shows, not the item.
const LOOK_ITEM_SCALE := 0.47
## The head always comes in from this side of the vent: the open room, with
## the hanging grate edge-on at the side of the view.
const LOOK_FROM := Vector3(0.33, 0.0, 1.0)
## Up close the fingers rise a touch less, so their whole length shows.
const LOOK_CURL := 0.44
var _look_flat := Vector3.ZERO
## 0..1 how far the hands have changed to the close-up hold.
var _look_w := 0.0

## Which way the head comes in from, seen from the vent.
func begin_look(_eye_world: Vector3) -> void:
    _look_flat = LOOK_FROM.normalized()

func end_look() -> void:
    _look_flat = Vector3.ZERO

func looking() -> bool:
    return _look_flat != Vector3.ZERO

func _look_dir() -> Vector3:
    return (Vector3.UP * LOOK_RISE - _look_flat).normalized()

func _look_eye() -> Vector3:
    return _look_flat * LOOK_BACK + Vector3.DOWN * LOOK_DOWN

## The eye of the look, in world space. It never depends on the offer, so
## the head holds still while hands come and go.
func look_pose() -> Transform3D:
    var eye := to_global(_look_eye())
    var at := to_global(_look_eye() + _look_dir())
    return Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)

func _look_cluster() -> Vector3:
    var dir := _look_dir()
    var up := (Vector3.UP - dir * dir.y).normalized()
    var ahead := LOOK_AHEAD + LOOK_AHEAD_PER_HAND * float(clampi(_count - 3, 0, 2)) + LOOK_AHEAD_PAST_ROW * float(maxi(_count - ROW_MAX, 0))
    return _look_eye() + dir * ahead + up * LOOK_WRIST_UP

## The hands follow the player slowly; every hand keeps a neutral wrist on
## the way down and only turns its palm up to the eye as the forearm swings out.
func _place_hands(delta: float) -> void:
    if _count <= 0 or _rigs.is_empty():
        return
    if _skin_mat != null and is_inside_tree():
        (_skin_mat as ShaderMaterial).set_shader_parameter("lip_y", to_global(Vector3(0, LIP_Y, 0)).y)
        for mm in _model_mats:
            (mm as ShaderMaterial).set_shader_parameter("lip_y", to_global(Vector3(0, LIP_Y, 0)).y)
    var eye := _look_eye() if looking() else _eye()
    var target := _look_cluster() if looking() else _cluster_target(eye)
    var k := 1.0 if _snap else 1.0 - exp((-6.0 if looking() else -2.5) * delta)
    _center = _center.lerp(target, k)
    # the row runs across the line of sight, level
    var fwd := _center - eye
    var side := Vector3(fwd.z, 0.0, -fwd.x)
    if side.length() > 0.05:
        _side = _side.slerp(side.normalized(), k) if not _snap else side.normalized()
    _snap = false
    var view_up := _side.cross(fwd.normalized()).normalized()
    if view_up.y < 0.0:
        view_up = -view_up
    _look_w = move_toward(_look_w, 1.0 if looking() else 0.0, delta * 3.0)
    var item_scale := lerpf(ITEM_SCALE, LOOK_ITEM_SCALE, _look_w)
    var rows := int(ceil(float(_count) / float(ROW_MAX)))
    var e := _extend
    for i in range(_count):
        var rig: Dictionary = _rigs[i]
        var row := floori(float(i) / float(ROW_MAX))
        var in_row := mini(ROW_MAX, _count - row * ROW_MAX)
        var col := i % ROW_MAX
        var a := (float(col) - (in_row - 1) * 0.5) * SPACING
        var b := (float(row) - (rows - 1) * 0.5) * ROW_GAP
        # a shallow arc round the eye, and a little life in each hand
        var sway := Vector3(sin(_time * 0.9 + i * 2.3), sin(_time * 0.7 + i * 1.1) * 0.6, cos(_time * 0.8 + i * 1.9)) * 0.006
        # rows stagger by half a hand; the later rows hang higher and further
        # back, between the arms of the front row, clear of the player's hands
        if rows > 1:
            a += SPACING * (0.25 if row % 2 == 1 else -0.25)
        # up close the open palms reach wider than a hanging hand: a little closer together
        a *= lerpf(1.0, LOOK_SPREAD, _look_w)
        var arc := LOOK_ARC if looking() else 1.1
        var w_end := _center + _side * a + view_up * b - fwd.normalized() * (a * a * arc - 0.12 * float(row)) + sway
        if hand_angle:
            var a_max := maxf(float(in_row - 1) * 0.5 * SPACING * LOOK_SPREAD, 0.001)
            var wide := _count > 3
            w_end += (-view_up * (a * minf(ANGLE_STAIR, (ANGLE_RISE_WIDE if wide else ANGLE_RISE) / a_max) + ANGLE_DROP) + _side * (ANGLE_SHIFT_WIDE if wide else ANGLE_SHIFT)) * _look_w
            if wide:
                w_end += fwd.normalized() * ANGLE_AHEAD_WIDE * _look_w
            if _count == 1:
                w_end += (view_up * ANGLE_ONE_LIFT - fwd.normalized() * ANGLE_ONE_NEAR) * _look_w
        if hand_grace:
            # no two neighbours at one height
            w_end += view_up * GRACE_STEP * sin(float(i) * 2.4 + 0.5)
        # where the arm leaves the opening: above its hand, kept inside the frame
        var lip := Vector3(_center.x * 0.3, LIP_Y, _center.z * 0.3) + _side * a * 0.9 + Vector3(view_up.x, 0, view_up.z) * b * 0.6
        lip.x = clampf(lip.x, -SIZE + 0.045, SIZE - 0.045)
        lip.z = clampf(lip.z, -SIZE + 0.045, SIZE - 0.045)
        rig["side_a"] = a
        # the middle hand leads, each one further out follows a beat later
        var off := float(col) - (in_row - 1) * 0.5
        var order := 2.0 * absf(off) - (1.0 if off < 0.0 else 0.0) + float(row)
        var late := minf(HAND_DELAY * maxf(order, 0.0), HAND_DELAY_MAX)
        _pose_arm(rig, lip, w_end, clampf((e - late) / (1.0 - late), 0.0, 1.0), eye, delta)
        var slot: Node3D = rig["slot"]
        slot.scale = Vector3.ONE * item_scale
        if hand_angle:
            var seat := SEAT.lerp(ANGLE_SEAT, _look_w)
            slot.position = Vector3(seat.x * float(rig["chir"]), seat.y, lerpf(_seat_z, _angle_seat_z, _look_w))

## The final arm for a wrist at `w`: a two-bone chain from the shoulder in
## the duct, the forearm FOREARM long, bent to the arm's own elbow angle with
## the elbow pointing away from the eye and outward (kept
## under the lip and, beside the hanging grate, inside its edge so the upper
## arm comes down clear of it), and the hand's basis with the palm up to
## the eye. Returns [elbow, hand basis].
func _arm_target(rig: Dictionary, lip: Vector3, w: Vector3, eye: Vector3) -> Array:
    var out := Vector3(w.x - lip.x, 0.0, w.z - lip.z)
    var flat_eye := Vector3(eye.x - w.x, 0.0, eye.z - w.z)
    if out.length() < 0.03:
        out = flat_eye
    if out.length() < 0.01:
        out = Vector3(-_side.z, 0, _side.x)
    out = out.normalized()
    # toward the eye on the whole, each arm a little its own way
    if flat_eye.length() > 0.01:
        out = out.slerp(flat_eye.normalized(), 0.5)
    # the elbow: a two-bone chain from the shoulder up in the duct, the
    # forearm FOREARM long (shorter only on a short reach), bent to
    # the arm's own inside angle, pointing away from the eye and outward
    var sh := lip + Vector3.UP * SHOULDER_UP
    var sw := sh - w
    var d := sw.length()
    var theta: float = rig["bend"]
    # ANGLE: how far this hand has taken the one shared diagonal
    var slant := _look_w if hand_angle else 0.0
    theta = lerpf(theta, ANGLE_ELBOW + (theta - ELBOW_ANGLE) * 0.5, slant)
    var lf := minf(FOREARM, d * 0.48)
    var ang_s := asin(clampf(lf * sin(theta) / d, -1.0, 1.0))
    var ang_w := PI - theta - ang_s
    var away := (w - eye)
    away.y = maxf(away.y, 0.0)
    away = away.normalized() + _side * lerpf(signf(float(rig.get("side_a", 0.0))) * 0.5, ANGLE_LEAN, slant) + Vector3.UP * 0.2
    away = away.rotated(Vector3.UP, float(rig["yaw"]) * lerpf(1.0, ANGLE_YAW, slant))
    var swn := sw / d
    var perp := away - swn * away.dot(swn)
    perp = perp.normalized() if perp.length() > 0.01 else Vector3.UP.cross(swn).normalized()
    var el := w + (swn * cos(ang_w) + perp * sin(ang_w)) * lf
    el.y = minf(el.y, LIP_Y - 0.09)
    if w.x < -SIZE + 0.02 and el.x < -SIZE + 0.04:
        # beside the hanging grate: the elbow stays inside its edge and below
        # it, the forearm passing under the grate's lower edge
        el.x = -SIZE + 0.04
        el.y = minf(el.y, maxf(w.y + 0.04, LIP_Y - 0.66))
    var fdir := (w - el).normalized()
    # the palm: up and toward the eye; the fingers carry on the forearm's
    # line in that plane, which lifts the hand back a little at the wrist
    var to_eye := (eye - w).normalized()
    var n := (Vector3.UP * lerpf(PALM_UP, ANGLE_PALM_UP, slant) + to_eye).normalized()
    n = n.rotated(out.cross(Vector3.UP).normalized(), float(rig["tilt"]))
    var g := fdir - n * fdir.dot(n)
    if g.length() < 0.05:
        g = out
    g = g.normalized()
    if slant > 0.0:
        # every hand's fingers turn the same way across the view
        g = g.rotated(n, ANGLE_TURN * slant * signf(n.cross(g).dot(-_side))).normalized()
    if hand_grace:
        # a soft line at the wrist: the hand a touch toward its little finger
        # (hand frame: fingers -Y, palm +Z, thumb +X on a right hand)
        g = g.rotated(n, -GRACE_ULNAR * float(rig["chir"])).normalized()
    var ang := fdir.angle_to(g)
    if ang > WRIST_MAX:
        g = fdir.slerp(g, WRIST_MAX / ang).normalized()
        n = (n - g * n.dot(g)).normalized()
    # a little roll about the fingers, each hand its own
    n = n.rotated(g, float(rig["roll"]))
    var y_ax := -g
    var z_ax := n
    var x_ax := y_ax.cross(z_ax).normalized()
    return [el, Basis(x_ax, y_ax, z_ax)]

## Arm and hand for offer progress `e`: first straight down out of the duct
## (fingers hanging, wrist straight), then the elbow comes out and bends, the
## forearm swings out toward the player turning the palm up, and the wrist
## lifts the hand to offer.
func _pose_arm(rig: Dictionary, lip: Vector3, w_end: Vector3, e: float, eye: Vector3, delta: float) -> void:
    var tgt := _arm_target(rig, lip, w_end, eye)
    var el_end: Vector3 = tgt[0]
    var hb_end: Basis = tgt[1]
    # thumbs open outward: a left hand on one side of the fan, a right on the other
    var a: float = rig.get("side_a", 0.0)
    var c := 1.0
    if absf(a) > 0.001 and hb_end.x.dot(_side) * a < 0.0:
        c = -1.0
    if hand_angle:
        # one kind of hand, so they all lie the same way
        c = 1.0
    _set_chirality(rig, c)
    # hanging: fingers straight down. `hang` has the palm toward the player;
    # the hand comes down turned about its fingers, its back and nails to
    # the player, and turns over as the forearm swings out
    var flat := Vector3(eye.x - lip.x, 0.0, eye.z - lip.z)
    flat = flat.normalized() if flat.length() > 0.01 else Vector3(-_side.z, 0, _side.x)
    var hang := Basis(Vector3.UP.cross(flat).normalized(), Vector3.UP, flat)
    var el_drop := lip + Vector3.DOWN * 0.1
    var fore_len := el_end.distance_to(w_end)
    var w: Vector3
    var el: Vector3
    var hb: Basis
    var swing := _swing_of(e)
    var turn := 1.0
    if e < DROP_PHASE:
        var u := smoothstep(0.0, 1.0, e / DROP_PHASE)
        el = (lip + Vector3.UP * (fore_len + 0.45)).lerp(el_drop, u)
        w = el + Vector3.DOWN * fore_len
        hb = hang
    else:
        el = el_drop.lerp(el_end, swing)
        var fdir := Vector3.DOWN.slerp((w_end - el_end).normalized(), swing)
        w = el + fdir * fore_len
        # the item's weight settles into the hand as it arrives
        if not _beg and swing > SETTLE_FROM:
            w.y -= SETTLE_DIP * sin(PI * (swing - SETTLE_FROM) / (1.0 - SETTLE_FROM))
        hb = Basis(hang.get_rotation_quaternion().slerp(hb_end.get_rotation_quaternion(), swing))
        # an empty asking hand stops short: it has turned over by then
        var top := _swing_of(BEG_EXTEND) if _beg else 1.0
        turn = 1.0 - smoothstep(FLIP_FROM * top, FLIP_TO * top, swing)
    if not hand_flip:
        turn = 0.0
    # going back up the hand does not turn over again: it just draws away
    if _retreat:
        turn = minf(turn, float(rig["turn"]))
    rig["turn"] = turn
    rig["lag"] = 0.0 if _beg else FOLLOW_CURL * (1.0 - swing)
    # the fingers' line is the same as before; the thumb leads toward the eye
    hb = hb * Basis(Vector3.UP, -c * PI * turn)
    var q := hb.get_rotation_quaternion()
    var prev: Quaternion = rig["rot"]
    var kq := 1.0 if delta <= 0.0 else 1.0 - exp(-10.0 * delta)
    q = prev.slerp(q, kq) if prev != Quaternion.IDENTITY else q
    rig["rot"] = q
    # the upper arm from the shoulder up in the duct down to the elbow
    var sh := lip + Vector3.UP * SHOULDER_UP
    sh.y = maxf(sh.y, el.y + 0.1)
    var up_v := sh - el
    var upper: MeshInstance3D = rig["upper"]
    upper.transform = Transform3D(_frame(up_v.normalized(), up_v.length()), el)
    var el_mesh: MeshInstance3D = rig["elbow"]
    el_mesh.transform = Transform3D(_frame(up_v.normalized(), 1.0), el)
    var fore: MeshInstance3D = rig["fore"]
    var arm := el - w
    var along := arm.normalized() if arm.length() > 0.001 else Vector3.UP
    fore.transform = Transform3D(_frame(along, arm.length()), w)
    var hand: Node3D = rig["hand"]
    hand.transform = Transform3D(Basis(q), w)
    # the forearm's flat oval turns with the wrist (the palm turning up turns
    # the forearm), so the wrist flows into the back of the hand with no edge
    var hx := Basis(q).x
    hx = hx - along * hx.dot(along)
    if hx.length() > 0.05 and arm.length() > 0.001:
        hx = hx.normalized()
        fore.transform = Transform3D(Basis(hx, along * arm.length(), hx.cross(along).normalized()), w)

## Share of the swing-out done at offer progress `e` (0 while coming down).
static func _swing_of(e: float) -> float:
    return smoothstep(0.0, 1.0, (e - DROP_PHASE) / (1.0 - DROP_PHASE)) if e >= DROP_PHASE else 0.0

## A basis whose Y axis runs along `dir` scaled to `length` (X, Z unit).
static func _frame(dir: Vector3, length: float) -> Basis:
    var ref := Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
    var x := ref.cross(dir).normalized()
    var z := x.cross(dir).normalized()
    return Basis(x, dir * maxf(length, 0.001), z)

func set_open(amount: float) -> void:
    _black_cover.visible = amount < 0.02
    _grate.rotation_degrees.z = -100.0 * clampf(amount, 0.0, 1.0)

func play_open() -> void:
    var tw := create_tween()
    tw.tween_method(set_open, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The being shows no eyes (user 2026-11-03: "환풍구에 눈 항상 보이지 않게").
## Kept so the vent logic and art tests can still call them.
func blink() -> void:
    pass

func set_eyes(_show: bool) -> void:
    pass

func set_eye_mood(frantic: float) -> void:
    _mood = clampf(frantic, 0.0, 1.0)

## Teeth the player put on the lip, waiting to be looked at (one per tooth).
const PILE_MAX := 60
var _pile: MultiMeshInstance3D

func _build_pile() -> void:
    _pile = MultiMeshInstance3D.new()
    _pile.name = "TeethPile"
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    var st := K.begin()
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.004), Vector2(0.0075, -0.003), Vector2(0.009, 0.002), Vector2(0.008, 0.006), Vector2(0.004, 0.0085), Vector2(0.0, 0.007)], 6, [Color(0.9, 0.84, 0.66)])
    mm.mesh = K.finish(st, 60.0)
    mm.instance_count = PILE_MAX
    for i in range(PILE_MAX):
        # a small heap on the near lip, growing in rings
        var ring := int(sqrt(float(i)))
        var a := float(i) * 2.39996
        var r := 0.012 * float(ring)
        var pos := Vector3(cos(a) * r, -0.004 - 0.006 * float(ring % 3), SIZE - 0.05 + sin(a) * r * 0.6)
        mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(K.h(i, 1), K.h(i, 2), K.h(i, 3)) * TAU).scaled(Vector3.ONE * 2.2), pos))
    mm.visible_instance_count = 0
    _pile.multimesh = mm
    _pile.material_override = K.mat("tex_ceramic_64.png", 0.5, false)
    _pile.custom_aabb = AABB(Vector3(-0.2, -0.1, -0.2), Vector3(0.4, 0.2, 0.6))
    add_child(_pile)

func set_pile(n: int) -> void:
    if _pile != null:
        _pile.multimesh.visible_instance_count = clampi(n, 0, PILE_MAX)

func pile_count() -> int:
    return _pile.multimesh.visible_instance_count if _pile != null else 0

## How far the offer is held out now (0 up in the duct, 1 held out).
func offer_extend() -> float:
    return _extend if _wanted else 0.0

## 0 = the arms are up in the black duct, 1 = held out in front of the player.
func set_offer_extend(t: float) -> void:
    t = clampf(t, 0.0, 1.0)
    if t != _extend:
        _retreat = t < _extend
    _extend = t
    _arms.visible = _extend > 0.001 and _count > 0
    if _arms.visible:
        _place_hands(0.0)

func play_offer() -> void:
    if not _wanted:
        return
    _snap = true
    _hand_to(1.0, 1.4, Tween.EASE_IN_OUT)

func play_withdraw() -> void:
    _hand_to(0.0, 0.4, Tween.EASE_IN)

# --- absurd overpay: things spill out -------------------------------------------

## "큭 켘." and early items spill out of the duct (spec 03-restroom §7 거래
## 규칙). They are the player's at once (FPVent grants them before this), so
## each one tumbles out of the black, bounces on the floor under the vent,
## lies there a moment and is then swept to the player's waist, the way a
## taken item goes to the belt. Real size, no collision with the room.
const SPILL_GAP := 0.16
const SPILL_GRAVITY := 9.8
const SPILL_BOUNCE := 0.32
## Seconds an item lies on the floor before it goes to the waist.
const SPILL_REST := 1.5
const SPILL_STOW := 0.45
## The waist below the eye, where the item is swept to.
const SPILL_WAIST := 0.72
## Pitch that lays an item down on the floor: items are modelled to face out
## of the being's palm (+Z), so a knife would otherwise stand on its edge.
const SPILL_LIE := {"knife": -PI * 0.5}
var _spill: Array = []
var _spill_root: Node3D
var _spill_floor := -2.57

## Item kinds as for set_offer_items; `floor_y` is the room floor in this
## node's frame (the vent face is y = 0).
func play_spill(kinds: Array, floor_y: float) -> void:
    _spill_floor = floor_y
    if _spill_root == null:
        _spill_root = K.pivot(self, "Spill")
    var eye := _eye()
    var toward := Vector3(eye.x, 0.0, eye.z)
    toward = toward.normalized() if toward.length() > 0.05 else Vector3(0, 0, 1)
    for i in range(kinds.size()):
        var item := FPItemArt.make(str(kinds[i]), 40 + i)
        item.name = "Spilled%d" % _spill.size()
        _spill_root.add_child(item)
        FPItemArt.set_layers(item, _black_cover.layers)
        item.visible = false
        # out of the dark above the lip, a little apart, each kicked a bit
        # toward the player and to its own side
        var side := Vector3(-toward.z, 0.0, toward.x) * (K.h(i, 7) - 0.5) * 1.4
        var start := Vector3((K.h(i, 3) - 0.5) * 0.24, 0.18, (K.h(i, 5) - 0.5) * 0.24)
        var vel := toward * (0.35 + 0.45 * K.h(i, 9)) + side + Vector3(0, -0.2, 0)
        var spin := Vector3(K.h(i, 11) - 0.5, K.h(i, 13) - 0.5, K.h(i, 17) - 0.5) * 18.0
        item.position = start
        item.rotation = Vector3(K.h(i, 19), K.h(i, 23), K.h(i, 29)) * TAU
        _spill.append({"node": item, "vel": vel, "spin": spin, "wait": float(i) * SPILL_GAP, "state": "fall", "t": 0.0, "bounced": false, "lie": float(SPILL_LIE.get(str(kinds[i]), 0.0))})

## Items still on their way (falling, lying or going to the waist).
func spill_count() -> int:
    return _spill.size()

func spill_nodes() -> Array:
    var out: Array = []
    for s in _spill:
        out.append(s["node"])
    return out

## Advance the spill by `delta` (called from _process; tests call it directly).
func step_spill(delta: float) -> void:
    var rest_y := _spill_floor + 0.03
    for s in _spill:
        var n: Node3D = s["node"]
        if s["wait"] > 0.0:
            s["wait"] = float(s["wait"]) - delta
            continue
        n.visible = true
        match String(s["state"]):
            "fall":
                var v: Vector3 = s["vel"]
                v.y -= SPILL_GRAVITY * delta
                n.position += v * delta
                n.rotation += (s["spin"] as Vector3) * delta
                if n.position.y <= rest_y and v.y < 0.0:
                    n.position.y = rest_y
                    if not s["bounced"] and -v.y > 1.0:
                        s["bounced"] = true
                        v = Vector3(v.x * 0.5, -v.y * SPILL_BOUNCE, v.z * 0.5)
                        s["spin"] = (s["spin"] as Vector3) * 0.4
                    else:
                        # lies flat where it stopped, its own way round
                        s["state"] = "rest"
                        s["t"] = 0.0
                        n.rotation = Vector3(float(s["lie"]), n.rotation.y, 0.0)
                        s["from"] = n.position
                s["vel"] = v
            "rest":
                s["t"] = float(s["t"]) + delta
                if float(s["t"]) >= SPILL_REST:
                    s["state"] = "stow"
                    s["t"] = 0.0
                    s["from"] = n.position
            "stow":
                s["t"] = float(s["t"]) + delta
                var u := clampf(float(s["t"]) / SPILL_STOW, 0.0, 1.0)
                var waist := _eye() - Vector3(0, SPILL_WAIST, 0)
                var e := u * u
                n.position = (s["from"] as Vector3).lerp(waist, e) + Vector3(0, sin(u * PI) * 0.25, 0)
                n.scale = Vector3.ONE * lerpf(1.0, 0.35, e)
                if u >= 1.0:
                    s["state"] = "done"
    for i in range(_spill.size() - 1, -1, -1):
        if String(_spill[i]["state"]) == "done":
            var gone: Node3D = _spill[i]["node"]
            _spill.remove_at(i)
            gone.queue_free()

func capture_setup() -> Dictionary:
    set_open(1.0)
    set_offer_extend(1.0)
    # capture only: the restroom ceiling tiles around the opening
    var st := K.begin()
    for i in range(4):
        var t := K.T(Vector3.ZERO, Vector3(0, 90 * i, 0))
        K.quad(st, t, Vector3(-1.2, 0, -1.2), Vector3(1.2, 0, -1.2), Vector3(SIZE + 0.06, 0, -SIZE - 0.06), Vector3(-SIZE - 0.06, 0, -SIZE - 0.06), Vector3.DOWN, Color(0.9, 0.9, 0.9))
    K.add_mesh(self, "CaptureCeiling", K.finish(st, 2.0), K.mat("tex_tile_wall_64.png", 0.1, false))
    return {"cam_pos": Vector3(0.42, -0.95, 0.68), "look_at": Vector3(0, 0.05, 0), "env": "restroom", "fov": 60.0}

# --- asking for teeth without a word (FPVent.nudge_for) --------------------------

## "beg": one empty hand comes down out of the dark, short of the eye, and
## grasps at the air; "lip": the near lip, where teeth go, glints; "" neither.
const BEG_EXTEND := 0.72
const BEG_OPEN := 0.05
const BEG_CLOSE := 1.25
## Grasps per second, and how far each finger lags the one before.
const BEG_RATE := 0.75
const BEG_LAG := 0.07
var _beg := false
var _nudge := ""
var _glint: MeshInstance3D
var _glint_mat: StandardMaterial3D

func set_nudge(kind: String) -> void:
    _nudge = kind
    _glint.layers = _black_cover.layers
    _glint.visible = kind == "lip"
    var beg := kind == "beg"
    if beg == _beg:
        return
    if beg:
        if _wanted:
            return # an offer is out: its hands stay
        _beg = true
        while _rigs.is_empty():
            _rigs.append(_new_rig(0))
        _offers.clear()
        _count = 1
        for i in range(_rigs.size()):
            var rig: Dictionary = _rigs[i]
            (rig["root"] as Node3D).visible = i == 0
            var slot: Node3D = rig["slot"]
            for ch in slot.get_children():
                slot.remove_child(ch)
                ch.queue_free()
            slot.visible = false
            rig["item_top"] = 0.0
        var lit := _black_cover.layers
        for n in _arms.find_children("*", "VisualInstance3D", true, false):
            (n as VisualInstance3D).layers = lit
        _snap = true
        _hand_to(BEG_EXTEND, 1.1, Tween.EASE_IN_OUT)
    else:
        _beg = false
        if not _wanted:
            _hand_to(0.0, 0.35, Tween.EASE_IN)

func nudge_kind() -> String:
    return _nudge

func begging() -> bool:
    return _beg and hand_count() > 0

## 0 open .. 1 closed, finger `i` a little behind the one before it.
func _beg_grasp(i: int) -> float:
    var s := sin((_time * BEG_RATE - float(i) * BEG_LAG) * TAU)
    return smoothstep(-0.6, 0.9, s)

func _build_glint() -> void:
    _glint = MeshInstance3D.new()
    _glint.name = "LipGlint"
    var sm := SphereMesh.new()
    sm.radius = 0.034
    sm.height = 0.045
    sm.radial_segments = 10
    sm.rings = 5
    _glint.mesh = sm
    _glint_mat = StandardMaterial3D.new()
    # a lit spark of enamel: it shines against the black of the duct
    _glint_mat.albedo_color = Color(0.95, 0.88, 0.66)
    _glint_mat.emission_enabled = true
    _glint_mat.emission = Color(1.0, 0.86, 0.55)
    _glint_mat.emission_energy_multiplier = 0.0
    _glint.material_override = _glint_mat
    _glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # the spot on the near lip where the first teeth land (_build_pile)
    _glint.position = Vector3(0, -0.012, SIZE - 0.05)
    _glint.visible = false
    add_child(_glint)
    _glint.layers = _black_cover.layers

## A slow pulse, brighter and bigger together, like light catching enamel.
func _step_glint() -> void:
    if _glint == null or not _glint.visible:
        return
    var p := 0.5 + 0.5 * sin(_time * TAU * 0.8)
    p = p * p
    _glint_mat.emission_energy_multiplier = lerpf(0.3, 4.0, p)
    _glint.scale = Vector3.ONE * lerpf(0.8, 1.6, p)

func glint_shown() -> bool:
    return _glint != null and _glint.visible

## The shut grate knocks in its frame (teeth in the hand, the grate shut):
## a short tilt on the hinge and back.
const JOSTLE_TIME := 0.42
const JOSTLE_DEG := 5.5
var _jostle_t := -1.0

func jostle() -> void:
    _jostle_t = 0.0

func jostling() -> bool:
    return _jostle_t >= 0.0

func _step_jostle(delta: float) -> void:
    if _jostle_t < 0.0:
        return
    _jostle_t += delta
    if not _black_cover.visible:
        _jostle_t = -1.0 # it was opened: the hinge is the player's now
        return
    if _jostle_t >= JOSTLE_TIME:
        _jostle_t = -1.0
        _grate.rotation_degrees.z = 0.0
        return
    var u := _jostle_t / JOSTLE_TIME
    # two knocks, the second smaller
    _grate.rotation_degrees.z = -JOSTLE_DEG * absf(sin(u * TAU)) * (1.0 - u * 0.6)
