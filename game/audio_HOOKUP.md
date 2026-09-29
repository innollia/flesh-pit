
## W04~W06 (세션 B)
- FPToiletSettlement.tank_rattle_started(duration, tumor): 물탱크 달그락 소리. 길이는 duration(종양이면 훨씬 김).
- FPVent.line_spoken(line_id): 환풍구 존재 음성/자막. id와 한국어 문장은 game/main/data/vent_lines.json.

- (세션 D) 수축 조직 조임 경고: FDKTerrainField.contraction_warning(world_pos: Vector3) 신호가 조이기 1초 전에 청크마다 한 번 뜬다. 여기에 조임 소리를 연결해 달라.
