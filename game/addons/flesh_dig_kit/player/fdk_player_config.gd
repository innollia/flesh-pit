class_name FDKPlayerConfig
extends Resource

## Tunable numbers for FDKFirstPersonController.

@export var walk_speed: float = 3.0
@export var crouch_speed: float = 1.5
@export var crouch_height: float = 0.9
@export var stand_height: float = 1.8
## Eye height above the feet when standing (real adult ~1.6 m; the capsule
## top is the crown of the head). Crouching keeps the same proportion.
@export var eye_height: float = 1.6
@export var mouse_sensitivity: float = 0.0025
@export var invert_y: bool = false ## flip vertical look (mouse, keys, stick)
@export var keyboard_look_speed: float = 2.0 ## radians/sec, for keyboard-only look (arrow keys)
@export var climb_speed: float = 2.5 ## vertical speed while digging up/down against a wall
@export var bob_frequency: float = 6.0
@export var bob_amplitude: float = 0.045
@export var head_bob_enabled: bool = true ## camera follows the bob (the signal fires either way)
@export var bob_sway: float = 0.022 ## side-to-side head sway, metres
@export var bob_roll: float = 0.35 ## camera roll per metre of sway
@export var bob_ease_speed: float = 4.0 ## how fast the bob fades in/out on start/stop
@export var pitch_limit_deg: float = 89.0
@export var gravity: float = 9.8 ## downward acceleration when in air / over pits
@export var terminal_velocity: float = 24.0 ## maximum fall speed
