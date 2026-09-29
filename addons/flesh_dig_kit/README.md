# Flesh Dig Kit

Godot 4.7 addon: chunked density-grid terrain (dig/regenerate), a
tearing/chewing/stomach system, and a first-person tunneling controller.
Built for organic "eat through terrain" digging games, but the terrain and
eating systems have no flesh-pit-specific assumptions baked in.

License: MIT (see LICENSE). No external code is bundled.

## Requirements

Godot 4.7 or newer. Compatibility renderer is what this kit is tuned for
(low-spec + web-export friendly); Forward+ should also work but is untested.

## Install

Copy `addons/flesh_dig_kit/` into your project's `addons/` folder, then
enable it in Project Settings > Plugins (the plugin itself has no editor
UI; enabling just registers it as present).

## Quick start

See `demo/fdk_demo.tscn` for a complete standalone example. In short:

```gdscript
var terrain := FDKTerrainField.new()
terrain.config = FDKTerrainConfig.new()
add_child(terrain)
terrain.fill_box_uniform(AABB(Vector3(-4,-4,-4), Vector3(8,8,8)), 1.0, 0)
terrain.carve_sphere(Vector3.ZERO, 2.0) # empty starting room

var stomach := FDKStomach.new()
stomach.config = FDKStomachConfig.new()
add_child(stomach)

var chewer := FDKChewer.new()
chewer.terrain = terrain
chewer.stomach = stomach
chewer.config = stomach.config
add_child(chewer)

var player := (load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn") as PackedScene).instantiate()
add_child(player)
```

Each frame, raycast from `player.get_look_ray()`, call
`chewer.try_start(hit_position)` + `chewer.process_chew(delta)` while the
`fdk_eat` action is held, and `chewer.stop()` otherwise. Call
`terrain.regenerate_all(delta, player.global_position, protect_radius)`
every frame to let carved tissue heal back over time.

## 사용법 (간단)

`addons/flesh_dig_kit/`를 프로젝트의 `addons/`에 복사하고 Project Settings >
Plugins에서 활성화한다. `demo/fdk_demo.tscn`이 완전한 예시다. 매 프레임
플레이어 시선으로 레이캐스트해 `chewer.try_start()`/`process_chew()`를
`fdk_eat` 입력이 눌린 동안 호출하고, `terrain.regenerate_all()`을 매 프레임
호출하면 파낸 조직이 서서히 재생된다.

## Modules

- `terrain/` — `FDKTerrainConfig`, `FDKChunk`, `FDKTerrainField`
- `eat/` — `FDKStomachConfig`, `FDKStomach`, `FDKChewer`
- `player/` — `FDKPlayerConfig`, `FDKInputActions`, `FDKFirstPersonController`, `FDKHandsRig`

All `class_name`s use the `FDK` prefix to avoid collisions with a game's own
code. No autoloads. All tunable numbers live on exported Resources.
