# Image Asset List

Status: **working production list, partly superseded**
Last updated: 2026-09-29
Canon source: [design-core.md](design-core.md), [world-direction.md](world-direction.md), [digging-success-patterns.md](digging-success-patterns.md)

> **Read this first.** This list was written against an earlier `design-core.md`.
> The canon has since added money and a toilet shop, an overfill system, physical
> barriers with four damage states, biosecurity spray, a portable blender, a
> parent-child mutation tree, and has restructured depth from vertical bands into
> nested shells holding multiple biomes. Nothing below covers those, and the rows
> that assumed a no-sell loop or vertical depth bands are now wrong. Treat this as
> the 2D baseline that still holds, not as the current canon.

Scope: every **image** asset the game needs, listed one by one.
Out of scope: 3D meshes, rigging, animation clips, shaders-as-code, audio, video. Where a visual comes from 3D material work rather than a bitmap, this document still specifies the *texture* that feeds it.

---

## 0. How to read this list

### Columns

| Column | Meaning |
| --- | --- |
| ID | Stable asset ID. Never renumber, only retire. |
| Name | Short human name, also the filename stem. |
| Look | What it actually looks like: colour, shape, states. |
| Spec | Pixel size or texture tier. `2K` = 2048x2048, `1K` = 1024, `512` = 512. |
| Format | File format and type of asset (sprite, 9-slice, flipbook, texture map). |
| Pri | `MVP` = needed for the first playable slice. `P1` = needed for a full first run. `P2` = polish, marketing, or edge case. |
| Need | Why it exists, in one line. |

### ID prefixes

| Prefix | Group |
| --- | --- |
| `STO` | Stomach / fullness UI |
| `HND` | First-person hands HUD |
| `DEP` | Depth and anatomical position UI |
| `CMP` | Compass and canary navigation |
| `ICO` | Tissue icons and legend |
| `CDX` | Codex UI |
| `RST` | Restroom UI and clean-white surface art |
| `BAND` | Depth band cards and splash art |
| `MNU` | Menu, settings, flow |
| `DTH` | Death and recovery |
| `TUT` | Tutorial and onboarding |
| `LDG` | Loading screens |
| `TEX` | World textures and maps |
| `VFX` | Frame-sequence / flipbook image assets |
| `BRD` | Brand, store, marketing |
| `ACC` | Accessibility and robustness variants |

### Rules that apply to every row

- No baked text anywhere. All strings come from the font, including numerals.
- Alpha assets are PNG-32. Opaque assets are PNG or TGA source, shipped as PNG.
- Albedo is sRGB. Normal, roughness, mask, and flow maps are linear.
- One normal-map convention only, chosen at project start (Unity: OpenGL `+Y` up). Do not mix.
- Every panel marked `9-slice` needs a border of 12-24 px and a centre region of at least 24 px.
- Every flipbook is a single horizontal strip, power-of-two frame count, with FPS recorded in the accompanying metadata.

---

## 1. Naming and folder convention

### Folder tree

```
assets/
  ui/
    hud/        STO-* CMP-* DEP-*
    panels/     all 9-slice frames and windows
    icons/      ICO-* and all icon sets
    menu/       MNU-*
    codex/      CDX-*
    prompts/    TUT-* in-world prompts and toasts
  art/
    hands/      HND-*
    band-cards/ BAND-*
    codex/      codex portraits and specimen plates
    keyart/     BRD-* large art
  vfx/          VFX-* flipbook strips and atlases
  textures/
    flesh/      per-band albedo / normal / roughness
    tissue/     per-tissue material maps
    restroom/   clean white surfaces
    infra/      embedded human infrastructure
    utility/    noise, flow, gradients, LUTs
  brand/        BRD-* logo, capsules, achievements
```

### Filename grammar

`group_subject_variant_map_state.ext`, all lowercase, underscores only.

| Example | Breaks down as |
| --- | --- |
| `ui_sto_gauge_frame_9s.png` | group / subject / variant / state / type |
| `tex_flesh_b03_albedo_2k.png` | group / band / map / tier |
| `vfx_tear_burst_08f.png` | group / effect / frame-count |
| `ico_nerve_cluster_128.png` | group / subject / resolution |

### Texture tier rule

| Tier | Use for |
| --- | --- |
| `2K` | Anything within roughly 2 m of the camera: tunnel wall the player eats, hands, restroom tile, toilet |
| `1K` | Mid-distance tissue, band cards, codex portraits, VFX atlases |
| `512` | Deep background tissue, decals, particles, far infrastructure |

### Proposed depth bands (PROPOSAL, not canon)

Band names and boundaries are not canon. What **is** canon is that each band changes play, not only visuals. If a band is cut, renumber by letter code (`B03a`) rather than renumbering the ID.

| ID | Band | Depth | Visual identity in one line | Mechanical identity to support |
| --- | --- | --- | --- | --- |
| B01 | Surface Epithelium | 0 to 60 m | Wet pink, hair-follicle pits, thin | Hands are enough. First loop, first return |
| B02 | Dermal Stratum | 60 to 140 m | Yellow fat lobes under red | Bite verb unlocks, chunk size up |
| B03 | Fascia Sheet | 140 to 250 m | Tough white membrane sheets, tight | Requires cut verb, tunnel shape starts to matter |
| B04 | Muscle Sheath | 250 to 400 m | Dark striated red-brown, heavy | Fullness slows movement |
| B05 | Glandular Cluster | 400 to 560 m | Nodular, lumpy, fluid sacs | High chew time, low yield per bite |
| B06 | Nerve Braid | 560 to 760 m | Yellow dominant, wriggling strands | Nerve density, contraction routing matters |
| B07 | Cavity Vault | 760 to 980 m | Near-empty dark volume, faint membrane sheen | Navigation problem, embedded infrastructure |
| B08 | Peristaltic Corridor | 980 m and below | Ridged tube, rhythmic width change | Long committed returns, deepest tissue |

### Proposed tissue types (PROPOSAL, not canon)

| ID | Tissue | Read |
| --- | --- | --- |
| T01 | Muscle Fibre | Red striated, springs back |
| T02 | Fat Lobe | Yellow, soft, high yield |
| T03 | Fascia Sheet | White, tough, tears in strips |
| T04 | Glandular Sac | Translucent, fluid-filled, slow chew |
| T05 | Cartilage Plate | Grey-white, hard, uncuttable by hands |
| T06 | Nerve Cluster | **Yellow, protruding, wriggling** |
| T07 | Tumor Growth | Pale nodular mass, codex target |
| T08 | Mucosa Film | Slippery translucent sheet |
| T09 | Shell Plate | Dense bone-white barrier |
| T10 | Scar Tissue | Fresh regrowth lining an old tunnel |

---

## 2. Stomach and fullness UI (STO)

Canon: stomach capacity is the one pressure system. It is a decision boundary, not a punishment. This gauge is the most-read element in the game.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| STO-01 | Stomach gauge frame | Organic ribbed bezel, dark red, wet highlight along the top edge, transparent centre hole | 512x256, 9-slice 32/224/32 | PNG-32 9-slice | MVP | The permanent fullness readout |
| STO-02 | Stomach gauge inner mask | Soft rounded blob mask that clips the fill layers | 512x256 | PNG-32 mask | MVP | Clips fill art to stomach silhouette |
| STO-03 | Fill layer 1, 0 to 33% | Thin pale-pink sliver, vertical fibre grain | 256x256 tileable Y | PNG-32 | MVP | Early fullness, still comfortable |
| STO-04 | Fill layer 2, 34 to 66% | Fuller red mass, visible lumps, oil sheen | 256x256 tileable Y | PNG-32 | MVP | Mid-range pressure, the greedy zone |
| STO-05 | Fill layer 3, 67 to 99% | Dark congested crimson, vein web, sweat beads on top edge | 256x256 tileable Y | PNG-32 | MVP | "One more bite is now a real decision" |
| STO-06 | Overflow state | Force-fed bulge, split seams, cold blue vein overlay, rim glow | 512x256 | PNG-32 9-slice | P1 | Momentary consequence of ignoring the gauge |
| STO-07 | Capacity tick marks | 8 short bone-white notches, one per mutation stage | 128x64 strip | PNG-32 | P1 | Shows how much more can be eaten now |
| STO-08 | Greedy pulse rim | Pulsing gold rim that breathes at 1.4 Hz | 512x256, 9-slice | PNG-32 | P1 | Calls attention once past 80% |
| STO-09 | Nausea vignette | Sickly bile-green corner bleed, soft edges, transparent centre | 1024x1024 | PNG-32 radial | MVP | Fullscreen warning without a number |
| STO-10 | Slosh distortion mask | Two-frame ripple mask, vertical wobble | 256x256 x2 | PNG-32 | P1 | Makes the fill move with the player |
| STO-11 | Digest progress ring | Clockwise wipe ring, pale, ticks every 10% | 256x256 | PNG-32 9-slice | P1 | Stomach emptying after vomiting |
| STO-12 | Empty stomach silhouette | Contracted wrinkled hollow, dim | 256x256 | PNG-32 | P1 | Explicit zero state, matters at low capacity |
| STO-13 | Full block icon | Crossed-out jaw with a swelling belly | 128x128 | PNG-32 | P1 | "Cannot eat another bite" |
| STO-14 | Toilet bowl gauge | White ceramic bowl cross-section that fills with chewed flesh | 512x256, 9-slice | PNG-32 9-slice | MVP | Restroom-only variant of the stomach gauge |
| STO-15 | Vomit stream fill | Coarse chewed-flesh stream, pale with red streaks | 256x256 tileable Y | PNG-32 | MVP | Visualises emptying without value |
| STO-16 | Stage distortion overlays x6 | Per mutation stage: altered organ silhouette, added sacs, cysts, scale patches | 256x256 x6 | PNG-32 | P1 | Stomach UI changes as the body mutates, canon feedback channel |
| STO-17 | Fullness numerals | Digit set 0-9, percent sign, drawn as a thin bone-white stencil | 256x128 atlas | PNG-32 atlas | P1 | Optional exact readout; never required to read the state |
| STO-18 | Overfull screen tint | Deep red pulse overlay, red-to-transparent from edges | 1024x1024 | PNG-32 | P2 | Reinforces overflow without new UI |

---

## 3. First-person hands HUD (HND)

Canon: the player's hands are an in-world HUD. Mutation must be visible here. A major mutation should be perceptible immediately.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| HND-01 | Bare hands idle pair | Clean human hands, forearms cut off at frame edge, soft top-light | 2048x1024 pair sheet | PNG-32 | MVP | Frame zero of the whole game |
| HND-02 | Hands reach pose | Fingers splayed forward, palm down, entering frame from bottom | 2048x1024 | PNG-32 | MVP | Contact anticipation for grabbing |
| HND-03 | Hands bite pose | One hand raised to mouth height holding a torn chunk | 2048x1024 | MVP | Chewing verb made legible without a tutorial |
| HND-04 | Hands tear pose | Both hands gripping, pulling away from the wall, tension in the forearms | 2048x1024 | MVP | Tearing is the identity verb, must read instantly |
| HND-05 | Hands chew hold | Held pose for the chew duration, slight tremor | 2048x1024 | MVP | Chew time needs a visible anchor |
| HND-06 | Stage 1 hands, torn nails | Split nail beds, reddened knuckles, small blood under nails | 2048x1024 | P1 | First mutation read |
| HND-07 | Stage 2 hands, splitting skin | Peeling skin edges, translucent membrane showing through | 2048x1024 | P1 | Second mutation read |
| HND-08 | Stage 3 hands, coated | Mucus-slick sheen, webbing between fingers | 2048x1024 | P1 | Third mutation read |
| HND-09 | Stage 4 hands, keratin plating | Hardened yellow plates over knuckles, calcified look | 2048x1024 | P1 | Fourth mutation read |
| HND-10 | Stage 5 hands, elongated digits | Over-long clawed fingers, wrong joint count feel | 2048x1024 | P1 | Fifth mutation read |
| HND-11 | Stage 6 hands, polyp growths | Pale tumor nodules on the backs of the hands | 2048x1024 | P2 | Sixth mutation read |
| HND-12 | Mutation reveal pose | Arms raised into frame, torso edge creeping in at the bottom, veins lighting up | 2048x1024 | MVP | The instant a major mutation is perceptible |
| HND-13 | Swollen empty hands | Hands pulled in toward the bottom of frame, belly edge visible | 2048x1024 | P1 | Fullness shown on the body, not just the gauge |
| HND-14 | Nerve flinch pose | Arms recoiled, fingers splayed, shoulders raised | 2048x1024 | MVP | Nerve reaction must read as caused by the player |
| HND-15 | Tool grip sockets | Hand poses pre-shaped for each excavation verb: cut, hook, saw, suction, cauterize | 2048x1024 x5 | PNG-32 | P2 | Verb progression is unresolved, so these are drawn as sockets not tools |
| HND-16 | Restroom wrap | White cloth wrap around hands, clinical, clean | 2048x1024 | P1 | White-restroom contrast on the HUD itself |
| HND-17 | Depth grime overlay | Wet red smear decal that sits on top of any hand set | 1024x1024 | PNG-32 decal | P1 | Reusable dirt layer, keeps hand art count down |
| HND-18 | Hand portrait set | Small square portrait of each hand stage, 6 stages, for menus and codex | 256x256 x6 | PNG-32 atlas | P1 | Shows progression in a non-HUD screen |
| HND-19 | Hand stage icons x6 | Simplified silhouette icon per mutation stage | 128x128 x6 | PNG-32 atlas | P1 | Progression display in menu and mutation panel |
| HND-20 | Death hands | Hands hanging limp at the bottom of frame, out of focus | 2048x1024 | P1 | Death screen honesty |
| HND-21 | Stomach bulge frame overlay | Semi-transparent belly silhouette at the frame bottom, swells with fullness | 1024x256 | PNG-32 | P1 | Third fullness channel, purely diegetic |

---

## 4. Depth and anatomical position UI (DEP)

Canon: depth is the objective. Two macro-progress displays must coexist: depth and player capability.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| DEP-01 | Depth meter frame | Vertical brass-and-bone housing, 9-slice, soiled edges | 256x1024, 9-slice 32/960/32 | PNG-32 9-slice | MVP | Constant depth readout |
| DEP-02 | Depth meter fill strip | Vertical gradient bone-white at top to deep red at the bottom, tileable | 64x1024 tileable Y | PNG-32 | MVP | Colour-codes how deep at a glance |
| DEP-03 | Depth tick texture | Ruled minor ticks, 10 m spacing | 64x512 tileable Y | PNG-32 | P1 | Makes depth increments legible |
| DEP-04 | Band divider marker | Bone-white bar with two notches, used eight times | 64x32 | PNG-32 | MVP | Shows band boundaries without text |
| DEP-05 | Band label B01 | "SURFACE EPITHELIUM" on a stained enamel plate | 512x128 | PNG-32 textless plate | MVP | Canon forbids baked text, so this is the plate only; band name is drawn by the font |
| DEP-06 | Band label B02 | "DERMAL STRATUM" plate | 512x128 | PNG-32 | MVP | as above |
| DEP-07 | Band label B03 | "FASCIA SHEET" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-08 | Band label B04 | "MUSCLE SHEATH" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-09 | Band label B05 | "GLANDULAR CLUSTER" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-10 | Band label B06 | "NERVE BRAID" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-11 | Band label B07 | "CAVITY VAULT" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-12 | Band label B08 | "PERISTALTIC CORRIDOR" plate | 512x128 | PNG-32 | P1 | as above |
| DEP-13 | Band change banner frame | Wide torn-flesh banner, dark, 9-slice | 1024x256, 9-slice | PNG-32 9-slice | MVP | Announces a new band on crossing |
| DEP-14 | Banner accent sweep | Soft red-to-white horizontal wipe gradient | 512x64 | PNG-32 | P1 | Motion layer for the banner |
| DEP-15 | Depth milestone frame | Rough-cut bone frame with hanging specimen hooks | 512x256, 9-slice | PNG-32 9-slice | P1 | Reward moment at 100 m intervals |
| DEP-16 | Milestone seal | Wax-red stamp with a generic mark, no text | 256x256 | PNG-32 | P1 | Milestone payoff graphic |
| DEP-17 | Depth numerals | Digit set 0-9 plus `m` and minus, thin stencil | 256x128 | PNG-32 atlas | MVP | Exact depth, essential for a genre where depth is the score |
| DEP-18 | Personal best marker | Small gold flag on the depth meter rail | 64x64 | PNG-32 | P1 | Progress against your own best |
| DEP-19 | Surface direction arrow | Upward chevron, clean white, points to the restroom | 128x128 | PNG-32 | MVP | "Which way is out" at a glance |
| DEP-20 | Home bearing chip | Small rounded chip that shows the restroom bearing, used next to the compass | 256x128, 9-slice | PNG-32 9-slice | P1 | Ties compass to the actual goal |
| DEP-21 | Depth danger hint arrow | Downward chevron in dull yellow, used when something unusual is below | 128x128 | PNG-32 | P1 | Foreshadowing, see Pattern 5 |
| DEP-22 | Band progress ladder | Small vertical ladder showing the eight bands as rungs, current rung highlighted | 128x512 | PNG-32 | P2 | Global progress readout for menus |

---

## 5. Compass and canary navigation (CMP)

Canon: compass and canary are the accepted navigation aids. The canary's exact function is undecided.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| CMP-01 | Compass frame | Brass rim, bone inlay, cracked glass, 9-slice | 512x512, 9-slice 48/416/48 | PNG-32 9-slice | MVP | The navigation instrument |
| CMP-02 | Compass rose face | Worn degree markings, no letters baked, 12 major marks | 512x512 | PNG-32 | MVP | Bearing readability |
| CMP-03 | North needle | Dark iron needle with a pale tip | 128x256 | PNG-32 | MVP | Standard heading |
| CMP-04 | Restroom needle | Clean white needle, visually distinct from north | 128x256 | PNG-32 | MVP | The goal is not north, it is the toilet |
| CMP-05 | Depth tick ring | Inner ring with 100 m ticks, faint | 512x512 | PNG-32 | P1 | Second function on the same instrument |
| CMP-06 | Compass glass grime | Wipe-clean transparent layer with fingerprint haze | 512x512 | PNG-32 | P1 | Keeps the compass readable over busy backgrounds |
| CMP-07 | Cracked glass state | Visible crack web across the upper-left quadrant | 512x512 | PNG-32 | P1 | Shows compass damage from a bad excursion |
| CMP-08 | Compass bracket mount | Short metal arm so the compass sits on-screen without floating | 256x128 | PNG-32 | P2 | Presentation polish |
| CMP-09 | Canary cage frame | Small domed brass cage, 9-slice | 256x256, 9-slice 32/192/32 | PNG-32 9-slice | MVP | Second navigation channel |
| CMP-10 | Canary idle portrait | Calm yellow bird, feathers smooth, on a perch | 256x256 | PNG-32 | MVP | Baseline companion state |
| CMP-11 | Canary alert portrait | Wings half-raised, head turned, eye wide | 256x256 | PNG-32 | MVP | Warning state |
| CMP-12 | Canary distress portrait | Motion-blurred, dishevelled, feathers puffed | 256x256 | PNG-32 | P1 | Serious warning state |
| CMP-13 | Canary status icon | Tiny 64 px version of the idle and alert states for the HUD corner | 64x64 x2 | PNG-32 atlas | P1 | Compact readout |
| CMP-14 | Canary world sprite | Small yellow bird in flight, seen from behind and above, 6-frame wing cycle | 256x256 x6 | PNG-32 flipbook | MVP | The canary exists in the 3D world, not only the HUD |
| CMP-15 | Canary tether line | Thin translucent filament from bird to player, dashed | 64x256 tileable Y | PNG-32 | P2 | Reads as a companion, not a projectile |
| CMP-16 | Off-route warning icon | Compass with a slash and a question mark, no text | 128x128 | PNG-32 | P1 | Lost-state prompt |
| CMP-17 | Canary report popup | Torn-paper card frame, 9-slice, room for font-rendered lines | 512x256, 9-slice | PNG-32 9-slice | TBD | Depends on the canary's undecided function |
| CMP-18 | Canary placeholder badge | Neutral grey bird mark used while the function is undefined | 64x64 | PNG-32 | P1 | Lets the UI ship before the design is decided |

---

## 6. Tissue icons and legend (ICO)

Canon: the player must recognise tissue before interacting. Nerves are the loudest language in the game: yellow, protruding, wriggling.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| ICO-01 | Legend panel frame | Wet dark-red card, 9-sliced, plenty of empty space for font text | 1024x512, 9-slice | PNG-32 9-slice | MVP | Where tissue literacy is taught |
| ICO-02 | Legend tab, normal | Low-contrast tab strip | 256x64 | PNG-32 | P1 | Tabs for the four legend categories |
| ICO-03 | Legend tab, hover | Raised, brighter edge | 256x64 | PNG-32 | P1 | Hover state |
| ICO-04 | Legend tab, selected | White underline bar, clean | 256x64 | PNG-32 | P1 | Selection state |
| ICO-05 | Unknown tissue icon | Question mark carved into a lump of generic flesh, deliberately low contrast | 128x128 | PNG-32 | MVP | Unknowns must not read as identified |
| ICO-06 | Muscle Fibre icon T01 | Red striated wedge, layered bands | 128x128 | PNG-32 | MVP | Tissue literacy |
| ICO-07 | Fat Lobe icon T02 | Soft yellow lobes, glossy | 128x128 | PNG-32 | MVP | Tissue literacy |
| ICO-08 | Fascia Sheet icon T03 | White torn strip, fibrous ends | 128x128 | PNG-32 | MVP | Tissue literacy |
| ICO-09 | Glandular Sac icon T04 | Translucent sac with fluid highlight | 128x128 | PNG-32 | MVP | Tissue literacy |
| ICO-10 | Cartilage Plate icon T05 | Grey-white smooth plate with a rim | 128x128 | PNG-32 | MVP | Tissue literacy |
| ICO-11 | Nerve Cluster icon T06 | **Bright yellow, thick outline, three strands, small wriggle ticks** | 128x128 | PNG-32 | MVP | Highest-contrast element in the whole icon set, canon requirement |
| ICO-12 | Tumor Growth icon T07 | Pale nodular mass with clustered bulbs | 128x128 | PNG-32 | MVP | Codex target marker |
| ICO-13 | Mucosa Film icon T08 | Translucent rippled sheet with a wet highlight | 128x128 | PNG-32 | P1 | Tissue literacy |
| ICO-14 | Shell Plate icon T09 | Dense bone-white barrier plate, heavy shadow | 128x128 | PNG-32 | P1 | Blocked-route marker |
| ICO-15 | Scar Tissue icon T10 | Fresh pink seam lines, healing grain | 128x128 | PNG-32 | P1 | Regrowth marker, teaches that your route is changing |
| ICO-16 | Legend card, muscle | Full-width card with the icon, a swatch bar, and blank ruled lines for font text | 512x256, 9-slice | PNG-32 9-slice | MVP | Per-tissue explanation |
| ICO-17 | Legend card, fat | as above | 512x256, 9-slice | PNG-32 9-slice | MVP | Per-tissue explanation |
| ICO-18 | Legend card, fascia | as above | 512x256, 9-slice | PNG-32 9-slice | MVP | Per-tissue explanation |
| ICO-19 | Legend card, glandular | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-20 | Legend card, cartilage | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-21 | Legend card, nerve | as above, yellow accent bar, no graphic detail | 512x256, 9-slice | PNG-32 9-slice | MVP | Per-tissue explanation |
| ICO-22 | Legend card, tumor | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-23 | Legend card, mucosa | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-24 | Legend card, shell | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-25 | Legend card, scar | as above | 512x256, 9-slice | PNG-32 9-slice | P1 | Per-tissue explanation |
| ICO-26 | Legend tooltip bubble | Small pointed bubble, 9-sliced, for one-line font text | 512x128, 9-slice | PNG-32 9-slice | MVP | Hover explanations for every icon |
| ICO-27 | Colour-blind safe icon atlas | The ten tissue icons redrawn using shape and pattern, not colour, 128 px each | 1280x256 | PNG-32 atlas | P1 | Accessibility without losing the yellow nerve language |
| ICO-28 | High-contrast nerve icon | Nerve icon with a white halo and a hard black keyline | 128x128 | PNG-32 | P1 | Nerve readability on any background |

---

## 7. Codex UI (CDX)

Canon: cancer and tumors are a codex and collectible system. No reward economy is attached.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| CDX-01 | Codex cover | Water-warped field notebook, stained cover, no title text | 1024x1024 | PNG-32 | MVP | The codex object |
| CDX-02 | Codex page base | Aged paper with damp edges and faint tissue stains | 1024x1024 | PNG-32 | MVP | Entry page background |
| CDX-03 | Page inner panel | Cleaner inset rectangle, 9-sliced, for font text | 896x960, 9-slice | PNG-32 9-slice | MVP | Text area |
| CDX-04 | Category tab icon, growths | Nodule cluster | 128x128 | PNG-32 | MVP | Four codex categories |
| CDX-05 | Category tab icon, nerves | Yellow strand knot | 128x128 | PNG-32 | MVP | Four codex categories |
| CDX-06 | Category tab icon, tissues | Layered tissue slice | 128x128 | PNG-32 | P1 | Four codex categories |
| CDX-07 | Category tab icon, infrastructure | Rusted plate and bolt | 128x128 | PNG-32 | P1 | Four codex categories |
| CDX-08 | Tab state, normal | Flat dark tab | 128x128 | PNG-32 | P1 | Tab states |
| CDX-09 | Tab state, hover | Lifted tab, brighter edge | 128x128 | PNG-32 | P1 | Tab states |
| CDX-10 | Tab state, selected | White underline, clean | 128x128 | PNG-32 | P1 | Tab states |
| CDX-11 | Slot, unknown | Blank card with a faint question mark | 256x256 | PNG-32 | MVP | Fog of war for uncollected entries |
| CDX-12 | Slot, discovered | Card with a black silhouette of the specimen | 256x256 | PNG-32 | MVP | Found but not catalogued |
| CDX-13 | Slot, catalogued | Card with the full portrait and a corner tick | 256x256 | PNG-32 | MVP | Complete entry |
| CDX-14 | Entry portrait frame | Organic specimen window, irregular inner mask, 9-sliced | 512x512, 9-slice | PNG-32 9-slice | MVP | Frames each specimen image |
| CDX-15 | Entry detail card | Wide card, 9-sliced, for stats and font text | 1024x512, 9-slice | PNG-32 9-slice | MVP | Detail layout |
| CDX-16 | Newly catalogued stamp | Ink stamp, rotated, no readable words, generic seal shape | 256x256 | PNG-32 | MVP | Payoff moment on first log of a specimen |
| CDX-17 | Completeness arc gauge | Partial ring wipe, pale, ticks every 10 entries | 256x256 | PNG-32 | P1 | Codex progress without numbers |
| CDX-18 | Codex complete stamp | Large pale seal across the page | 512x512 | PNG-32 | P2 | Terminal codex state |
| CDX-19 | List row highlight | Full-width soft highlight bar | 1024x64 | PNG-32 | P1 | Entry list selection |
| CDX-20 | Page turn wipe | Torn-edge page transition, two halves | 1024x1024 x2 | PNG-32 | P2 | Open and close feel |
| CDX-21 | Specimen portrait pack, tier 1 | 12 simple 512 px specimen portraits, generic nodules and growths | 512x512 x12 | PNG-32 | P1 | Fills early codex slots |
| CDX-22 | Specimen portrait pack, tier 2 | 12 detailed 512 px specimen portraits, unusual forms | 512x512 x12 | PNG-32 | P2 | Fills late codex slots |
| CDX-23 | Infrastructure photo pack | 8 photos of embedded human fittings, wet, crooked, no text | 512x512 x8 | PNG-32 | P2 | Codex category, and pure foreshadowing |

---

## 8. Restroom UI and clean-white art (RST)

Canon: the restroom is deliberately clean and white, a genuine safe exception, and it must not turn filthy. It is the visual reset between excursions.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| RST-01 | Toilet interaction prompt | Clean white outline icon of a toilet, no text, arrow above it | 128x128 | PNG-32 | MVP | The single most important interaction prompt |
| RST-02 | Bowl fill gauge | Bowl cross-section that fills with pale chewed flesh, 9-sliced | 512x256, 9-slice | PNG-32 9-slice | MVP | Emptying the stomach is the loop reset |
| RST-03 | Bowl overflow puff | Soft white puff, clean not slimy | 256x256 | PNG-32 | P1 | Overfill feedback |
| RST-04 | White wall tile albedo | Clean glazed white tile, faint grout variation, a few chips | 2K | PNG | MVP | The one clean surface in the game |
| RST-05 | Tile grout normal | Recessed grout lines, slightly uneven | 2K | PNG | MVP | Grout reads as depth |
| RST-06 | Tile roughness | Near-uniform gloss, faint dulling near the floor | 2K | PNG | P1 | Cleanliness has to be a material property, not just a colour |
| RST-07 | Floor tile albedo | Smaller pale grey tile, matte | 2K | PNG | MVP | Floor contrast against walls |
| RST-08 | Stainless fixture albedo | Brushed steel taps and flush lever, faint water marks | 1K | PNG | MVP | Restroom fixtures |
| RST-09 | Flush lever icon | Clean close-up of the flush handle, 9-sliced for UI use | 256x256, 9-slice | PNG-32 9-slice | P1 | Flush as the explicit "trip end" button |
| RST-10 | Restroom sign plate | White enamel pictogram plate, deliberately symbol-only so no text is baked | 512x256 | PNG-32 | P1 | Wayfinding inside the base |
| RST-11 | Door gap bleed | Red flesh light spilling through a closed door gap, narrow strip | 256x512 | PNG-32 | MVP | Reminds you the world is still there |
| RST-12 | Safe-zone white bloom | Soft white radial glow, warm centre, transparent edge | 1024x1024 | PNG-32 | MVP | Safe-space feedback |
| RST-13 | Clean vignette | Bright clean corners, tight falloff | 1024x1024 | PNG-32 | P1 | Inverts the dirty-world vignette |
| RST-14 | Ceiling light fixture | Fluorescent panel, clean, slight bloom halo in the texture | 1K | PNG | P1 | Light source read |
| RST-15 | Mirror plate | Clean mirror surface with a faint green tint and one smudge | 1K | PNG | P1 | Lets the player see their own mutation |
| RST-16 | Paper towel and dryer signage | Pictogram plates | 256x256 x2 | PNG-32 | P2 | Detail dressing |
| RST-17 | Progress wall board | Corkboard with pinned specimen cards and a hand-drawn depth ladder, no readable words | 2K | PNG | P1 | Restroom accumulating evidence of progress, canon requirement |
| RST-18 | Progress wall pin set | Push pins, string, and a small brass depth marker, 4 states | 256x256 x4 | PNG-32 | P1 | The board changes as the player goes deeper |
| RST-19 | Restroom clean transition overlay | White wash that fills the screen on entering the base | 1024x1024 | PNG-32 | MVP | The strongest colour event in the game |

---

## 9. Depth band cards and splash art (BAND)

Canon: deeper must be stranger, not tougher. Band cards are the promise made to the player before they commit.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| BAND-01 | Band card frame | Torn dark plate, 9-sliced, top band reserved for font text | 1920x1080, 9-slice | PNG-32 9-slice | MVP | Shared frame for all eight cards |
| BAND-02 | B01 Surface Epithelium art | Wet pink surface, follicle pits, shallow depth, a hint of daylight absence | 1920x1080 | PNG | MVP | First promise |
| BAND-03 | B02 Dermal Stratum art | Yellow fat lobes under torn red skin | 1920x1080 | PNG | MVP | New material promise |
| BAND-04 | B03 Fascia Sheet art | White membrane sheets stretched like sailcloth, tight gaps | 1920x1080 | PNG | P1 | New verb promise |
| BAND-05 | B04 Muscle Sheath art | Dark striated mass, huge scale, low visibility | 1920x1080 | PNG | P1 | New pressure promise |
| BAND-06 | B05 Glandular Cluster art | Nodular field of fluid sacs, soft focus | 1920x1080 | PNG | P1 | New rhythm promise |
| BAND-07 | B06 Nerve Braid art | Yellow strand thickets, motion-blurred, one clear silhouette | 1920x1080 | PNG | P1 | New hazard promise |
| BAND-08 | B07 Cavity Vault art | Vast dark empty volume, faint membrane sheen, tiny human ladder for scale | 1920x1080 | PNG | P1 | New navigation promise |
| BAND-09 | B08 Peristaltic Corridor art | Ridged tube receding into darkness, rhythmic ribs, terminal darkness | 1920x1080 | PNG | P1 | The bottom promise |
| BAND-10 | Band divider flourish | Organic horizontal rule, subtle, sits under band names | 1024x64 | PNG-32 | P2 | Typography support |

---

## 10. Menu, settings, and flow UI (MNU)

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| MNU-01 | Main menu background | Red flesh foreground on the right, clean white restroom light spilling from the left, empty centre for a menu list | 1920x1080 | PNG | MVP | The contrast is the pitch |
| MNU-02 | Menu logo plate | The wordmark lockup on transparent, no baked tagline | 2048x512 | PNG-32 | MVP | Main menu identity |
| MNU-03 | Menu panel frame | Frosted clean panel with a thin dark border, 9-sliced | 1024x1024, 9-slice | PNG-32 9-slice | MVP | Menu list container |
| MNU-04 | Menu button states | Four states in one sheet: normal, hover, pressed, disabled | 512x128 x4 | PNG-32 atlas | MVP | All buttons in the game |
| MNU-05 | Settings panel frame | Same family as MNU-03, colder white, 9-sliced | 1024x1024, 9-slice | PNG-32 9-slice | MVP | Settings |
| MNU-06 | Settings category tabs | Five tabs: game, audio, video, controls, accessibility, normal and selected states | 256x64 x10 | PNG-32 atlas | P1 | Settings structure |
| MNU-07 | Checkbox states | Empty box, hovered box, ticked box with a hand-drawn tick | 64x64 x3 | PNG-32 atlas | MVP | Every toggle |
| MNU-08 | Toggle switch states | Off, off-hover, on, on-hover, disabled | 96x48 x5 | PNG-32 atlas | P1 | Binary settings |
| MNU-09 | Slider track and fill | Thin track plus a bright fill, 9-sliced, no thumb | 64x16, 9-slice | PNG-32 9-slice | MVP | Volume, sensitivity, UI scale |
| MNU-10 | Slider knob states | Normal, hover, dragging, 4 knob shapes so each row feels different | 48x48 x4 | PNG-32 atlas | P1 | Slider interaction |
| MNU-11 | Dropdown arrow states | Closed, open, disabled | 48x48 x3 | PNG-32 atlas | P1 | Resolution and mode selection |
| MNU-12 | Pause overlay | Desaturated red wash with a clear centre | 1920x1080 | PNG-32 | MVP | Pause |
| MNU-13 | Controls rebind panel | Keycap grid frame, blank, no key art baked, 9-sliced | 1024x512, 9-slice | PNG-32 9-slice | P1 | Rebinding |
| MNU-14 | Input glyph set | Keyboard and mouse glyphs, controller glyphs, drawn line-art style | 512x512 atlas | PNG-32 atlas | P1 | Control prompts |
| MNU-15 | Save slot indicator | Bone tab marker, filled and empty states | 128x64 x2 | PNG-32 | P1 | Save feedback |
| MNU-16 | Confirm dialog frame | Small clean white card, 9-sliced, symmetric for two buttons | 768x384, 9-slice | PNG-32 9-slice | MVP | Quit and reset confirmations |
| MNU-17 | Credits background | Faded tissue wall with a clean strip for text | 1920x1080 | PNG | P2 | Credits |
| MNU-18 | UI font bitmap set | One bitmap font, uppercase and digits, licensed or original, no third-party IP | 512x512 atlas | PNG-32 atlas | MVP | All UI text |
| MNU-19 | Title screen backdrop | Same composition as MNU-01 but emptier and darker, logo appears over it | 1920x1080 | PNG | MVP | First impression |
| MNU-20 | First-run card | Plain white card with a blank lined area, for the original-setting note | 1024x512, 9-slice | PNG-32 9-slice | P2 | Disclaimer about the original setting |

---

## 11. Death and recovery (DTH)

Canon: death drops belongings at the death location, recovery is a small objective, and losing them is not catastrophic.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| DTH-01 | Death vignette | Dark red inward blur, wet edges, warm centre glow | 1024x1024 | PNG-32 | MVP | Death moment |
| DTH-02 | Death screen card | Torn card, low contrast, empty space for font text | 1024x512, 9-slice | PNG-32 9-slice | MVP | "You left something behind" |
| DTH-03 | Drop beacon world icon | A small pale glow with a bone spike, visible through tissue from a distance | 256x256 | PNG-32 | MVP | Marks the drop location |
| DTH-04 | Beacon HUD chip | Small diamond chip that appears once the beacon is in range | 128x64 | PNG-32 | P1 | Approach feedback |
| DTH-05 | Recover objective card | Compact card, icon plus a blank ruled line, 9-sliced | 512x128, 9-slice | PNG-32 9-slice | MVP | Recovery objective, not a punishment |
| DTH-06 | Items recovered flash | Bright white burst with a thin ring, clean | 512x512 | PNG-32 | MVP | Retrieval payoff |
| DTH-07 | Respawn white fade | White wash that fills the screen, clean direction | 1024x1024 | PNG-32 | MVP | Respawn in the restroom |
| DTH-08 | Belongings cache marker | Small cloth-wrapped bundle icon | 128x128 | PNG-32 | P1 | What the player goes back for |
| DTH-09 | Death heartbeat overlay | Slow red pulse vignette, low contrast, loops calmly | 1024x1024 | PNG-32 | P2 | Death-state atmosphere, not a danger meter |

---

## 12. Tutorial and onboarding (TUT)

Canon: the verb must be instantly legible. If the first interaction needs a tutorial panel, the design is too complex.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| TUT-01 | First contact prompt | Minimal hand-outline ring over the target tissue, icon only, no text | 256x256 | PNG-32 | MVP | Teaches the verb with a shape, not a panel |
| TUT-02 | Chew hold ring | Circular progress ring drawn around the held bite, thin and clean | 256x256 | PNG-32 | MVP | Chew time needs a visible timer |
| TUT-03 | Swallow prompt | Simple throat-down chevron | 128x128 | PNG-32 | MVP | Confirms the bite was consumed |
| TUT-04 | First full stomach prompt | Gauge-shaped outline with a hand pointing at the fill, icon only | 512x256 | PNG-32 | MVP | Teaches capacity without a word |
| TUT-05 | Return home hand-off | Compass outline with an arrow leaving it toward the surface, icon only | 512x256 | PNG-32 | MVP | Hands off to the compass as the first real system |
| TUT-06 | First vomit prompt | Toilet outline with an arrow into the bowl, icon only | 256x256 | PNG-32 | MVP | The loop must be learned physically |
| TUT-07 | First mutation reveal card | Wide card with a hand silhouette in the centre, 9-sliced | 1024x512, 9-slice | PNG-32 9-slice | MVP | The first transformation is the first reward |
| TUT-08 | First nerve contact prompt | Nerve icon plus a shock line, deliberately the loudest prompt in the set | 256x256 | PNG-32 | MVP | Nerves must be recognised before interaction |
| TUT-09 | First codex pickup prompt | Notebook outline with a small specimen dot, icon only | 256x256 | PNG-32 | P1 | Introduces the codex |
| TUT-10 | First death prompt | Limp hand icon over a dark card, 9-sliced | 512x256, 9-slice | PNG-32 9-slice | P1 | Death is not catastrophic, say so with the art |
| TUT-11 | Highlight overlay | Soft-edged dark mask with a transparent hole, used to spotlight one element | 1920x1080 | PNG-32 | P1 | Focus attention without a popup |
| TUT-12 | Tooltip bubble | Reuse the ICO-26 frame, this row documents the layout | 512x128, 9-slice | PNG-32 9-slice | P1 | Consistent tooltips |
| TUT-13 | Objective toast frame | Short horizontal toast, clean, 9-sliced, right-aligned for the stack | 768x128, 9-slice | PNG-32 9-slice | P1 | Transient goals |
| TUT-14 | Help overlay background | Darkened frozen gameplay frame with a clean panel, 9-sliced | 1920x1080 | PNG-32 9-slice | P1 | Controls reference without leaving the game |

---

## 13. Loading screens (LDG)

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| LDG-01 | Loading frame | Clean white tile grid on top, red flesh rising from the bottom, centre kept empty | 1920x1080 | PNG | MVP | Shared loading layout |
| LDG-02 | Band tip art, B01 to B08 | One small detail crop per band, no text, 8 variants | 1920x1080 x8 | PNG | P1 | Loading variety that also teaches the world |
| LDG-03 | Loading spinner, clean | Thin white rotating ring, six frames | 128x128 x6 | PNG-32 flipbook | MVP | Base spinner |
| LDG-04 | Loading spinner, flesh | Red organic pulsing blob, six frames | 128x128 x6 | PNG-32 flipbook | P1 | Flesh-world spinner |
| LDG-05 | Loading tip card | Small blank card, 9-sliced, for font-rendered tips | 768x192, 9-slice | PNG-32 9-slice | P1 | Tips in the restroom visual language |
| LDG-06 | Loading progress track | Thin bone-white track plus a fill, 9-sliced | 64x16, 9-slice | PNG-32 9-slice | P1 | Progress without a percentage |
| LDG-07 | Legal and rating plate | Neutral plate, no third-party logos | 512x128 | PNG-32 | P2 | Store requirements |

---

## 14. World textures (TEX)

### 14.1 Flesh per band

Each band needs albedo, normal, and roughness. Same tier per band as noted.

| ID | Name | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- |
| TEX-B01-A / N / R | B01 Surface Epithelium: pink wet skin, follicle pits, subsurface reddening | 2K | PNG | MVP | Closest surface the player touches |
| TEX-B02-A / N / R | B02 Dermal Stratum: yellow fat lobes, glossy caps, deep pits | 2K | PNG | MVP | First material change |
| TEX-B03-A / N / R | B03 Fascia Sheet: white fibrous membrane, crosshatch grain, tight weave | 2K | PNG | P1 | Tough, stringy, refuses to tear cleanly |
| TEX-B04-A / N / R | B04 Muscle Sheath: dark striated red-brown, coarse fibre, low reflectance | 2K | PNG | P1 | Heavy, absorbing sound in fiction |
| TEX-B05-A / N / R | B05 Glandular Cluster: nodular translucent sacs, fluid highlights | 1K | PNG | P1 | Wet, lumpy, soft |
| TEX-B06-A / N / R | B06 Nerve Braid: yellow strand mass, high-frequency fibre, glow in the crevices | 2K | PNG | P1 | Most visually distinct band |
| TEX-B07-A / N / R | B07 Cavity Vault: near-black membrane with a faint sheen, large smooth areas | 1K | PNG | P1 | Negative space, hard to light |
| TEX-B08-A / N / R | B08 Peristaltic Corridor: ridged tube interior, rhythmic ribs, damp folds | 2K | PNG | P1 | Deepest band, longest commitment |

### 14.2 Tissue detail

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| TEX-101 | Muscle fibre detail | Striated red fibres, strong directional grain | 1K | PNG | MVP | Overlay on B04 walls |
| TEX-102 | Fat lobe detail | Yellow lobules with a wet meniscus | 1K | PNG | MVP | Overlay on B02 |
| TEX-103 | Fascia sheet detail | White crosshatch, torn filament ends | 1K | PNG | P1 | Overlay on B03 |
| TEX-104 | Glandular sac detail | Translucent sacs with inner fluid | 1K | PNG | P1 | Overlay on B05 |
| TEX-105 | Cartilage plate detail | Grey-white smooth with a fine rim | 1K | PNG | P1 | Uncuttable early barrier |
| TEX-106 | Nerve cluster detail | Yellow strands, high detail, used close up | 2K | PNG | MVP | The canon nerve language, must survive close inspection |
| TEX-107 | Nerve emissive mask | Which parts glow, greyscale | 1K | PNG | P1 | Drives the wriggle highlight |
| TEX-108 | Nerve flow map | Directional flow for strand motion | 1K | PNG | P1 | Wriggle, garden-eel style |
| TEX-109 | Tumor surface A | Pale nodular cluster | 1K | PNG | MVP | Codex specimen A |
| TEX-110 | Tumor surface B | Lobulated, darker, veined | 1K | PNG | MVP | Codex specimen B |
| TEX-111 | Tumor surface C | Dense bulb cluster, almost cauliflower | 1K | PNG | P1 | Codex specimen C |
| TEX-112 | Mucosa film | Translucent rippled sheet with a wet highlight | 1K | PNG | P1 | Slippery surfaces |
| TEX-113 | Shell plate detail | Dense bone-white, subtle porosity | 1K | PNG | P1 | Hard barrier |
| TEX-114 | Scar tissue lining | Fresh pink seam grain for a healing tunnel wall | 1K | PNG | MVP | Makes regeneration visible |
| TEX-115 | Regrowth edge alpha | Soft growth front used to blend healed tissue into old tissue | 512 | PNG | MVP | The regeneration effect's core texture |
| TEX-116 | Vascular detail, cosmetic only | Faint blue-grey surface veins | 1K | PNG | P2 | **Cosmetic only.** Blood vessels are cancelled as a mechanic, so this is background detail with no gameplay meaning |
| TEX-117 | Mucus film overlay | Wet coating layer with a sharp specular | 512 | PNG | P1 | Makes surfaces read as wet |

### 14.3 Restroom and infrastructure

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| TEX-201 | Embedded enamel sign | Peeling white enamel with a pictogram only, no words | 1K | PNG | P1 | Foreshadowing, who built this |
| TEX-202 | Rusted ladder | Corroded rungs, wet, embedded in tissue | 2K | PNG | P1 | First infrastructure promise |
| TEX-203 | Steel hatch | Riveted plate with a wheel handle, rust streaks | 1K | PNG | P1 | Shortcut or checkpoint candidate |
| TEX-204 | Conduit run | Plastic conduit partly swallowed by growth, split ends | 1K | PNG | P1 | Scale reference |
| TEX-205 | Old service lift panel | Button panel, pictograms only, three buttons | 1K | PNG | P1 | Late-game traversal candidate, canon says undecided |
| TEX-206 | Garbled tile wall | The restroom's dirtier cousin: tile smeared with old growth, for embedded ruins, not the safe room | 1K | PNG | P1 | Must stay visually distinct from RST-04 |
| TEX-207 | Caution stripe | Worn yellow-black diagonal, pictographic not textual | 512 | PNG | P2 | Industrial detail |
| TEX-208 | Deep tissue shell | Dense outer flesh, the bottom of the world | 1K | PNG | P1 | Terminal look |

### 14.4 Utility maps and particles

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| TEX-301 | Noise base, organic | Tileable organic noise, greyscale | 1K | PNG | MVP | Base for every procedural breakup |
| TEX-302 | Flow map, flesh | Directional flow for tissue pulse | 1K | PNG | P1 | Subtle living movement |
| TEX-303 | Grunge mask | Dirt and stain overlay, alpha | 1K | PNG | MVP | Unifies surfaces, keeps texture count down |
| TEX-304 | Flesh chunk particle | Irregular torn chunk, red with a pale fat core, 4 random rotations | 128x128 x4 | PNG-32 | MVP | The thing that actually gets eaten |
| TEX-305 | Saliva droplet | Clear droplet with a soft highlight | 64x64 | PNG-32 | MVP | Chew feedback |
| TEX-306 | Mucus strand | Ropey translucent strand, 4 frames of stretch | 128x128 x4 | PNG-32 flipbook | P1 | Chew and drip |
| TEX-307 | Spark particle | Small warm-white flash, 3 frames | 64x64 x3 | PNG-32 flipbook | P1 | Generic accent |
| TEX-308 | Ambient mote | Slow drifting fleck, 4 frames | 32x32 x4 | PNG-32 flipbook | P1 | Depth atmosphere |
| TEX-309 | Tooth mark decal | Paired bite impressions with torn edges | 256x256 | PNG-32 decal | MVP | Shows where the player has been |
| TEX-310 | Claw scratch decal | Four parallel gouges | 256x256 | PNG-32 decal | P1 | Mutation sign on the world |
| TEX-311 | Handprint decal | Smeared palm print, wet | 256x256 | PNG-32 decal | P1 | Player authorship of space |
| TEX-312 | Scuff decal | Heel and knee marks on a tunnel wall | 256x256 | PNG-32 decal | P2 | Trail readability on return trips |
| TEX-313 | Blood decal, cosmetic only | Dark smear, low saturation, no gameplay meaning | 256x256 | PNG-32 decal | P2 | Cosmetic only, matches the cancelled-vessel stance |
| TEX-314 | Wipe gradient | Soft black-to-transparent wipe, used for wipes and fades | 256x256 | PNG-32 | MVP | UI transitions |
| TEX-315 | Glow radial | Soft round glow, for highlights and safe bloom | 256x256 | PNG-32 | MVP | UI and VFX reuse |

---

## 15. VFX image assets (VFX)

All flipbooks are horizontal strips with a power-of-two frame count. FPS noted here and in metadata.

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| VFX-01 | Flesh tear burst, 8f | Radial spray of red and pale fat streaks, fast | 256x256 x8 | PNG-32 flipbook | MVP | The single most important game-feel effect |
| VFX-02 | Chew burst, 6f | Small compression puff with chunks flying | 256x256 x6 | PNG-32 flipbook | MVP | Chewing made visible |
| VFX-03 | Tearing strand, 10f | Elastic filament stretching then snapping | 256x256 x10 | PNG-32 flipbook | MVP | Tissue elasticity, canon requirement |
| VFX-04 | Saliva arc, 8f | Drip arc from hand to mouth, glinting | 128x128 x8 | PNG-32 flipbook | P1 | Wet feedback |
| VFX-05 | Mucosal splatter, 12f | Wet sheet impact, spreads and settles | 512x512 x12 | PNG-32 flipbook | P1 | Wet-world punctuation |
| VFX-06 | Nerve contraction shockwave, 10f | Radial compression ripple with yellow dust | 512x512 x10 | PNG-32 flipbook | MVP | Nerve reaction reads as caused by the player |
| VFX-07 | Nerve recoil spark, 6f | Short yellow spark and snap-back | 128x128 x6 | PNG-32 flipbook | MVP | Nerve interaction confirmation |
| VFX-08 | Tumor reveal shimmer, 12f | Slow travelling highlight over a nodular surface | 512x512 x12 | PNG-32 flipbook | P1 | Codex discovery moment |
| VFX-09 | Vomit stream, 24f | Coarse stream into the bowl, continuous loop | 256x512 x24 | PNG-32 flipbook | MVP | The loop reset, played every single trip |
| VFX-10 | Toilet flush swirl, 16f | Whirlpool in pale water, clean, not slimy | 256x256 x16 | PNG-32 flipbook | MVP | Trip end punctuation |
| VFX-11 | Regrowth shimmer, 14f | Soft growth front creeping over old tunnel edges | 512x512 x14 | PNG-32 flipbook | MVP | Regeneration made visible, canon core pressure |
| VFX-12 | Tunnel close vignette, 10f | Flesh creeping in from screen edges, narrowing view | 1024x1024 x10 | PNG-32 flipbook | P1 | Return pressure |
| VFX-13 | Room transition bloom, 8f | White bloom blooming outward, clean | 1024x1024 x8 | PNG-32 flipbook | MVP | The colour contrast event |
| VFX-14 | Heartbeat pulse, 6f | Soft red whole-screen pulse | 1024x1024 x6 | PNG-32 flipbook | P1 | Organism awareness |
| VFX-15 | Cosmetic vein pulse, 10f | Faint surface-vein travel, no mechanical meaning | 1024x1024 x10 | PNG-32 flipbook | P2 | Cosmetic only, see TEX-116 |
| VFX-16 | Digest bubbles, 12f | Bubbles rising in the stomach fill, internal to the HUD | 256x256 x12 | PNG-32 flipbook | P1 | Stomach UI feels alive |
| VFX-17 | Mutation surge, 12f | Body-wide red surge with a white core, from the player outward | 1024x1024 x12 | PNG-32 flipbook | MVP | The transformation moment |
| VFX-18 | Band entry shockwave, 10f | Wide low shockwave plus a colour shift, per band, 8 variants | 1024x1024 x80 | PNG-32 flipbook | P1 | One per band, makes each depth band an event |
| VFX-19 | Ambient drip, 6f | Single droplet falling, 6 loops | 64x128 x6 | PNG-32 flipbook | P1 | Wet-world background motion |
| VFX-20 | Flesh heal flash, 8f | Quick pale flash where tissue has just regrown | 512x512 x8 | PNG-32 flipbook | P1 | Confirms regeneration actually happened |
| VFX-21 | Screen wipe red, 12f | Red organic wipe, both directions | 1024x1024 x12 | PNG-32 flipbook | P2 | Scene transitions into flesh space |
| VFX-22 | Screen wipe white, 12f | Clean white wipe, both directions | 1024x1024 x12 | PNG-32 flipbook | P2 | Scene transitions into the restroom |

---

## 16. Brand, store, and marketing (BRD)

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| BRD-01 | Logo lockup | Wordmark with a bite taken out of one letter, red on transparent | 2048x512 | PNG-32 | MVP | Identity |
| BRD-02 | Wordmark only | Same lettering without the bite motif, single colour | 2048x512 | PNG-32 | MVP | Small sizes |
| BRD-03 | App icon | Key art crop, readable at 32 px, one bright yellow accent | 512x512 | PNG | MVP | Store icon |
| BRD-04 | Key art, main | 16:9 tunnel perspective with a hand in frame, red depth, a white glow far away | 1920x1080 | PNG | MVP | Store front page |
| BRD-05 | Key art, close-up | Extreme close-up of teeth in flesh, high detail, unsettling but not gory | 1920x1080 | PNG | P1 | Secondary art |
| BRD-06 | Key art, contrast | Split composition, red flesh left, white restroom right, the tunnel between | 1920x1080 | PNG | P1 | Sells the central contrast |
| BRD-07 | Capsule, main 1232x706 | 16:9 key art crop, text kept clear of the centre | 1232x706 | PNG | MVP | Steam store |
| BRD-08 | Capsule, small 462x174 | Reduced detail crop, still readable | 462x174 | PNG | MVP | Steam store |
| BRD-09 | Capsule, vertical 600x900 | Portrait crop, tall tunnel, hand at the top | 600x900 | PNG | MVP | Steam library |
| BRD-10 | Header 460x215 | Wide banner crop | 460x215 | PNG | MVP | Steam header |
| BRD-11 | Library hero 3840x1240 | Ultra-wide tunnel with a white distant point | 3840x1240 | PNG | P1 | Steam library hero |
| BRD-12 | Page background 1438x810 | Blurred tissue with a clear centre band | 1438x810 | PNG | P1 | Steam page background |
| BRD-13 | Screenshot frame clean | White frame with a thin dark border for presentation shots | 1920x1080 | PNG-32 | P1 | Store screenshots |
| BRD-14 | Screenshot frame caption bar | Empty bar for font-rendered captions | 1920x120 | PNG-32 | P1 | Store screenshots |
| BRD-15 | Achievement, first bite | Bone-white plate with a torn flesh mark | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-16 | Achievement, first return | Toilet outline on a clean plate | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-17 | Achievement, first mutation | Split hand silhouette | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-18 | Achievement, 1000 m | Depth ruler mark | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-19 | Achievement, codex complete | Notebook with a full grid | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-20 | Achievement, nerve first touch | Yellow strand with a spark | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-21 | Achievement, belongings recovered | Cloth bundle with a white flash | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-22 | Achievement, deepest band | Generic band marker, band name is font text | 128x128 | PNG-32 | P1 | Store achievement |
| BRD-23 | Trailer end card | Logo on a clean white field with red bleed at the edges | 1920x1080 | PNG | P2 | Trailer |
| BRD-24 | Press kit logo on transparent | White and red logo variants | 2048x512 x2 | PNG-32 | P2 | Press and streamkit |
| BRD-25 | Favicon | 64x64 simplified bite-mark mark | 64x64 | PNG-32 | P2 | Browser |
| BRD-26 | Stream overlay frame | Two thin side bars, one red one white | 1920x1080 | PNG-32 | P2 | Streaming |

---

## 17. Accessibility and robustness variants (ACC)

| ID | Name | Look | Spec | Format | Pri | Need |
| --- | --- | --- | --- | --- | --- | --- |
| ACC-01 | Colour-blind safe icon atlas | Ten tissue icons redrawn with pattern and shape differences, nerve keeps the highest contrast | 1280x256 | PNG-32 atlas | P1 | Accessibility |
| ACC-02 | High contrast nerve icon set | Nerve icons with white halo and hard keyline, 3 sizes | 128x128, 64x64, 32x32 | PNG-32 atlas | P1 | Nerve readability on any background |
| ACC-03 | Reduced-motion shake replacement | Static edge vignette instead of camera shake | 1024x1024 | PNG-32 | P1 | Mutation feedback without motion |
| ACC-04 | Reduced-motion flash removal | Solid single-colour overlays to replace flashing effects | 1024x1024 x4 | PNG-32 | P1 | Photosensitivity safety |
| ACC-05 | Low-amplitude heartbeat | Same loop as VFX-14 but visually near-static | 1024x1024 x6 | PNG-32 flipbook | P1 | Motion comfort |
| ACC-06 | UI scale 125% exports | Every 9-slice panel re-exported with adjusted borders | matched | PNG-32 | P1 | Larger UI support |
| ACC-07 | UI scale 150% exports | As above | matched | PNG-32 | P2 | Larger UI support |
| ACC-08 | Localisation-safe text plates | Empty panels sized for the longest plausible string, 9-sliced with a wide fixed centre | 1024x256, 9-slice | PNG-32 9-slice | P1 | Text must never clip |
| ACC-09 | Subtitle plate | Dark translucent bar, 9-sliced, high contrast | 1024x128, 9-slice | PNG-32 9-slice | P2 | Subtitle support |
| ACC-10 | Focus and selection ring | Bright white ring, 2 px, works on any background | 64x64 | PNG-32 | P1 | Keyboard and controller navigation |
| ACC-11 | High-contrast UI frame set | White and black frame variants for the main panels | 1024x1024 x6 | PNG-32 9-slice | P2 | Contrast accessibility |
| ACC-12 | Low-resolution fallback set | 1K and 512 versions of the six hero textures | 1K, 512 | PNG | P2 | Performance fallback |

---

## 18. Counts

Counting rule: every table row is one asset, **except** the eight per-band rows in section 14.1, where `TEX-Bxx-A / N / R` is three files. `VFX-18` is one entry covering eight band variants.

| Section | Assets | MVP | P1 | P2 | TBD |
| --- | --- | --- | --- | --- | --- |
| 2. Stomach UI (STO) | 18 | 8 | 9 | 1 | 0 |
| 3. Hands HUD (HND) | 21 | 7 | 12 | 2 | 0 |
| 4. Depth UI (DEP) | 22 | 8 | 13 | 1 | 0 |
| 5. Compass and canary (CMP) | 18 | 8 | 7 | 2 | 1 |
| 6. Tissue icons (ICO) | 28 | 14 | 14 | 0 | 0 |
| 7. Codex (CDX) | 23 | 11 | 8 | 4 | 0 |
| 8. Restroom (RST) | 19 | 9 | 9 | 1 | 0 |
| 9. Band cards (BAND) | 10 | 3 | 6 | 1 | 0 |
| 10. Menu and settings (MNU) | 20 | 11 | 7 | 2 | 0 |
| 11. Death and recovery (DTH) | 9 | 6 | 2 | 1 | 0 |
| 12. Tutorial (TUT) | 14 | 8 | 6 | 0 | 0 |
| 13. Loading (LDG) | 7 | 2 | 4 | 1 | 0 |
| 14. World textures (TEX) | 64 | 20 | 40 | 4 | 0 |
| 15. VFX (VFX) | 22 | 10 | 9 | 3 | 0 |
| 16. Brand and store (BRD) | 26 | 8 | 14 | 4 | 0 |
| 17. Accessibility (ACC) | 12 | 0 | 8 | 4 | 0 |
| **Total** | **333** | **133** | **168** | **31** | **1** |

---

## 19. MVP slice, shortest path to a playable loop

The order that gets the first bite, the first return, and the first mutation on screen.

1. `STO-01` to `STO-05` gauge and its three fill layers
2. `HND-01`, `HND-03`, `HND-04`, `HND-05` bare hands and the three eating poses
3. `VFX-01`, `VFX-02`, `VFX-03`, `VFX-06` tear, chew, elasticity, nerve reaction
4. `TEX-B01-A/N/R`, `TEX-106`, `TEX-301`, `TEX-303`, `TEX-304` first band plus the nerve detail
5. `DEP-01`, `DEP-04`, `DEP-17`, `DEP-19` depth readout and up arrow
6. `CMP-01` to `CMP-04`, `CMP-09` to `CMP-11`, `CMP-14` compass and canary
7. `RST-01`, `RST-02`, `RST-04` to `RST-08`, `RST-19` restroom, toilet, and the white transition
8. `VFX-09`, `VFX-10`, `VFX-13` vomit, flush, bloom
9. `HND-12`, `VFX-17`, `STO-16` the first mutation
10. `TUT-01` to `TUT-08` the tutorial row
11. `MNU-01` to `MNU-04`, `MNU-07`, `MNU-09`, `MNU-18` menu, buttons, toggles, font
12. `ICO-06` to `ICO-12`, `ICO-26` tissue icons and the tooltip frame

That is 69 assets, which is a realistic first-scope image budget for a small game. It is the set that makes the core loop land: bite, fill, return, vomit, mutate.

---

## 20. TBD and non-canon dependencies

| Item | Depends on | What the art must flex for |
| --- | --- | --- |
| `CMP-17` canary report popup | The canary's exact function, still undecided | Card frame stays neutral so content can be anything |
| `CMP-18` canary placeholder badge | Same | Deliberately generic grey mark |
| `HND-15` tool grip sockets | Tool progression, unresolved | Sockets are drawn without tools so any verb can be inserted |
| Band names in `DEP-05` to `DEP-12` | Depth band design, not canon | Plates are textless, only the enamel plate art is fixed |
| `BAND-02` to `BAND-09` | Same | Each card is a promise, art can be reshot if a band is cut or moved |
| `VFX-18` per-band shockwave | Same | 8 variants are cheap to regenerate |
| `CDX-21`, `CDX-22` specimen portraits | Whether codex completion grants any benefit, undecided | Portraits are collectible art, they do not imply a reward |
| `TEX-205` service lift panel | Late traversal solutions, explicitly undecided | Stays a background prop, not a usable lift until decided |
| `MNU-18` bitmap font | Localisation plan | Keep one Latin set now, add sets later rather than shipping baked strings |
| Ending-related art | No ending is canon | Deliberately absent from this list |

---

## 21. Deliberately not needed

Things a reader might expect that this game does not have, and why.

| Not making | Reason |
| --- | --- |
| Shop, currency, or sell UI | Canon: no sell loop, vomit has no resource value |
| Crafting icons, recipe cards, workbench | Canon: avoid survival crafting expansion |
| Base building icons, furniture, room planner | Canon: avoid base building, the restroom is a fixed safe room |
| Combat HUD, weapon icons, enemy health bars | Canon: eating is the verb, not fighting |
| Blood gauges, bleed warnings, vascular hazard markers | Canon: blood vessels are cancelled as a core mechanic, only cosmetic detail is kept |
| Hunger, thirst, or stamina bars | Canon: one pressure system only, and it is stomach capacity |
| Skill tree, talent grid, perk icons | Canon: mutations are physical verb changes, not percentage trees |
| Minimap or large map screen | Canon: navigation is compass plus canary, and the tunnels are player-authored |
| Food item icons | Canon: the thing being eaten is the terrain |
| Quest log, journal of objectives | Canon: avoid narrative adventure, depth is the objective |
| Any park, company, or reference-work name or logo | Canon: original setting, references are design input only |
