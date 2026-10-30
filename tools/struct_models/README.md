# 바이옴 구조물 모델 (로우폴리 + 그림 한 장)

바이옴 구조물 10종(`game/main/art/fp_struct_<kind>.gd`)은 hwapongstuy 레포 `texture3d` 방식으로 만든다. 폴리곤은 최소로 하고, 디테일(문, 글자 없는 경고판, 녹, 살 덩어리 무늬)과 빛은 모두 그림에 칠한다.

- 모델: 구조물 하나에 삼각형 100~300개. 상자는 앞면(입구 쪽 +Z) 중심 십자 전개도, 둥근 부품은 옆면 띠 + 뚜껑, 같은 부품(세탁기, 다리, 살 덩어리)은 그림의 한 칸을 같이 쓴다.
- 그림: 모델 하나에 1024 한 장. 게임에는 512로 줄여 넣는다(PS1 재질, 최근접 필터).
- 게임: `fp_struct_model.gd`가 `main/art/structures/<kind>.glb`에 `<kind>.png`를 `FDKPs1Material`로 입힌다. 등만 코드로 만든다(빛나는 상자 하나와 OmniLight).

## 순서

```bash
B='/c/Program Files/Blender Foundation/Blender 5.2/blender.exe'
H=/c/projects/hwapongstuy
# 1. 모델과 전개도 (hwapongstuy texture3d/out/fp_<kind>/model.glb, layout.json)
"$B" --background --python tools/struct_models/build_struct_models.py -- "$(cygpath -w $H/texture3d/out)" [kind ...]
# 2. 선 그림과 GPT 메시지 (hwapongstuy 도구 그대로)
(cd $H/texture3d && python tools/make_guides.py out && python tools/build_message.py out fp_<kind>)
# 3. 그림 한 장 (Codex gpt-6-luna high, 프롬프트는 Codex가 쓰고 클린룸 서브에이전트가 한 번만 그린다)
(cd $H && python texture3d/tools/run_codex_texture.py fp_<kind> --force)
# 4. 게임으로 옮기기 (glb + 512 png, 미리보기 확인)
python tools/struct_models/install.py <kind>
```

- 프롬프트는 우리가 쓰지 않는다. 메시지는 `TEXTURE_META.md`와 `build_message.py`가 조립하고, 구조물마다 다른 것은 `build_struct_models.py`의 칸 설명(hint)뿐이다.
- 그림 한 장마다 프롬프트 원문은 `game/main/art/structures/<kind>.prompt.txt`에 같이 둔다.
- 칸 설명을 바꾸면 1~4를 다시 한다. 모델 모양만 바꿔도 전개도가 바뀌므로 그림을 다시 그려야 한다.
