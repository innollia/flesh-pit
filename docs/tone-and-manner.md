# Tone and Manner

Status: **current working canon**
Last updated: 2026-09-29

## 1. One-line definition

**Serious body horror in a PS1-era look: crude low-poly shapes wearing real, too-close photographic textures of flesh, inside a body that treats you as food it has not finished digesting yet.**

Primary visual/tone reference: *Revenge Of The Colon* (PS1-style body horror). Reference for look and mood only. Its story, characters, procedures, patients and any content are not used. Game systems come from compact digging games (see `reference-map.md`), so system and art never come from the same work.

## 2. Emotional target

- Dread and disgust first, never jump scares. Horror comes from closeness, texture, sound and the body reacting to you.
- The body is indifferent, not evil. It regrows, shifts and closes routes because that is what living tissue does.
- The player is alone. No narrator, no jokes addressed to the player, no winking.
- The restroom is relief. After the flesh, the clean white room should feel like breathing out.

Existing odd elements stay, but are played **straight**, never as gags:
- the canary's strange cry is unsettling, not cute
- paying by throwing a coin into the toilet is a ritual; presented quietly, without comic timing
- ending hypotheses remain non-canon and must not push the tone toward comedy

## 3. Visual rules (3D)

Low-poly is kept, but the look is **textured PS1**, not flat-shaded vertex color.

- Geometry: crude primitives and few polygons. Silhouettes can be blunt and slightly wrong.
- Textures: low resolution (64-256 px), nearest-neighbour filtering, no mipmap blur. Flesh uses photographic or photo-like surfaces (wet skin, mucosa, fat, teeth, eyes) that feel uncomfortably real against the crude geometry.
- Rendering: vertex snapping (slight wobble), affine texture warping, reduced colour depth with ordered dithering, low internal resolution scaled up, subtle grain / colour noise, short fog distance.
- Lighting: few lights, strong falloff. The flesh world is lit mainly by what the player carries; wet highlights are small and sharp.
- Palette, flesh world: deep reds, bruise purples, bile yellow-greens, fat ochre, dark near-black recesses. Saturated but dirty.
- Palette, restroom: white and pale grey tiles, cold fluorescent light, clean chrome. Same PS1 rendering (dither, low-res textures) so it belongs to the same game, but **clean**: no stains, no flesh, no rot.
- Hands: ordinary human hands, neutral skin, PS1 textured (not flat colour). Mutation changes them visibly over time.
- Infrastructure outside the restroom: 1930s-1990s public/industrial parts, rusted, partly swallowed by tissue.

## 4. 2D / UI

- As little on screen as possible. No persistent HUD text; the body (hands, stomach mass, throat) is the HUD.
- When text is needed it is short, flat and clinical, like a label or an instruction plate. No exclamation marks, no personality.
  - good: `Stomach capacity exceeded.`  `Vomit.`
  - bad: `Whoa, you're stuffed!`
- UI elements share the PS1 treatment: low-res, dithered, slightly noisy. Victorian encyclopaedic engravings are used for codex / specimen plates, printed and aged, never decorative filigree.
- Numbers in the toilet settlement keep the agreed format (dark grey total + green gain), rendered in a plain low-res font.

## 5. Sound

- Close, wet, physical: tearing, chewing, swallowing, gurgling, tissue stretching. Loud and near.
- The body is always audible: low heartbeat-like pressure, distant digestion, creaks when tissue shifts or regrows.
- Mutation changes the player's own sounds (heavier steps, different chewing) before any number changes.
- Restroom: fluorescent hum, water, echo on tiles. Quiet enough that the player hears their own breathing.
- No music during excavation by default; low drones only. Music, if any, belongs to depth milestones and the restroom.

## 6. Do / Don't

Do:
- make the player feel the texture before they understand it
- let the body react to the player's actions
- keep the restroom genuinely safe and clean
- use crude geometry plus realistic texture as the core contrast

Don't:
- jump scares, screaming faces, sudden loud stingers
- comedy, memes, fourth-wall jokes
- glossy modern PBR realism or smooth high-poly models
- flat-shaded vertex-colour-only low-poly (the earlier prototype look)
- import content, characters or scenes from the reference work
