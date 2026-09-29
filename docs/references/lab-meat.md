# Reference: LAB MEAT

Source role: **direct mechanical + technical reference for deformable meat excavation**

## Sources

- Main itch.io page: https://unconscious-a.itch.io/labmeat
- Godot Wild Jam #79 submission/results/comments: https://itch.io/jam/godot-wild-jam-79/rate/3413414
- Developer implementation explanation: https://itch.io/post/12480865
- Public source linked by the jam submission: https://github.com/emilyallerdings/GDWJ-Growing

## Context

LAB MEAT was made in **9 days** for Godot Wild Jam #79.

Official feature list:
- procedurally generated and breakable meat
- audio-based scanning
- inventory
- story/dialog
- three in-game weeks and an ending

The player works for a lab-grown-meat company, locates "High Quality Meat" with a scanner, and carves it out with a harvest tool.

This is one of the closest small-scale references to our **search + destructible flesh + extraction** problem.

---

## 1. Why it matters

LAB MEAT demonstrates that a tiny team/game-jam scope can already achieve:
- 3D deformable meat
- excavation-created traversal
- scanner-guided target discovery
- pulsing/alive visual feedback
- procedural target placement

Therefore "destructible living flesh" is not automatically a scope-killer.

The harder problem is making the interaction remain interesting for longer than a jam-sized experience.

---

## 2. Actual loop

Roughly:

**scan meat → locate high-quality region → dig toward it → recover target → repeat**

The scanner is audio-driven.

The meat itself is both:
- obstacle
- terrain
- resource container

### Relation to flesh-pit

Our loop differs:

**eat → stomach fills → return/vomit → mutate → descend**

But LAB MEAT gives a strong reference for optional **local route selection inside one excursion**.

Possible use:
- mutation sense reveals valuable growths
- auditory pulse indicates dense mutation tissue
- player chooses whether detouring is worth stomach capacity/time

Do not turn the whole game into "follow scanner target."

---

## 3. Player-created terrain matters

Jam feedback reveals players could:
- dig too deeply
- create inaccessible geometry
- need to carve staircase-like routes
- strand targets too high to reach

This is important.

Destructible volume is not only visual destruction.
It becomes a **navigation system**.

### flesh-pit requirement

Prototype must test:
- maximum climb/step height
- whether players can trap themselves
- whether tissue removal creates sharp collision junk
- how easy it is to create ramps/stairs
- how return trips behave through player-created tunnels

Possible safeguards:
- forgiving mantling
- crawl/climb mutation
- limited tissue regeneration smoothing bad geometry
- return shortcut after depth milestones

Do not solve all navigation with invisible walls or teleportation before testing the authored-hole fantasy.

---

## 4. Technical implementation disclosed by developer

The developer publicly described the meat implementation.

### Geometry
- mesh generated with **Marching Cubes**
- surface generation implemented in a **GDExtension using C++**
- chunked generation approach
- performance work was especially important for web builds

### Material
- two flesh PBR materials
- blended using noise based on world-position / UV-world-position logic

### Living motion
- vertex shader pulses vertices along the **vertex normal**
- pulse varies using blended world-position noise
- the developer notes this can occasionally distort geometry, but was sufficient for the jam

### Loading/cache trick
Developer reports rendering geometry/shaders/particles in a very-low-opacity viewport during loading to reduce caching stutter, though some stutter remained.

### Why this is useful

For an early flesh-pit prototype, this provides a concrete precedent:

**scalar field / marching cubes volume + chunking + flesh material + cheap vertex pulsation**

We do not need production-perfect soft-body simulation to prove the game.

---

## 5. Scanner feedback lesson

Several players had trouble understanding the audio scanner:
- scanning too quickly could fail to produce a useful reading
- some expected a visual indicator
- some dug blindly because they did not understand the audio-only system

The developer acknowledged the scanner was rushed and not as responsive as intended.

### flesh-pit lesson

If biological sensing becomes an upgrade:
- signal response must be immediate
- directionality must be learnable
- sound can carry mood, but important route information may need a subtle visual complement

The sensing mechanic should reward skill, not patience with ambiguous feedback.

---

## 6. Meat feels alive through cheap signals

Players repeatedly praised:
- pulsing
- heartbeat
- texture
- squirming
- sound

One comment specifically notes the heartbeat becoming faster after harvesting too much.

This matters because the illusion of life was achieved without a giant simulation stack.

### Cheap high-value signals for flesh-pit

Potentially:
- heartbeat audio tied to local damage
- subtle vertex pulse
- vessel pulse visible through nearby tissue
- local contraction after nerve damage
- wet cutting sounds that differ by tissue
- restroom plumbing responding to organism state

Prioritize **responsive biological feedback** over physically perfect flesh.

---

## 7. Repetition ceiling

Both a player and the developer explicitly acknowledge there is only so much enjoyment available from repeatedly digging the same meat.

The game ends around the moment its central interaction begins losing novelty.

This is a valuable design warning.

### flesh-pit response

We cannot depend on duration alone.
Even a small game needs interaction evolution.

By the time one tissue interaction becomes mastered, introduce:
- a new tissue behavior
- a new tool/verb
- a new organism reaction
- a new traversal condition

This supports our existing depth rule.

---

## 8. Target preservation / quality

LAB MEAT's "High Quality Meat" gives a primitive version of the idea that not all flesh is equally valuable.

Our accepted tumor/growth rule can push this further:
- intact extraction gives more mutation
- careless excavation destroys value
- sensing identifies boundaries
- precise tools preserve tissue
- brute-force tools trade precision for speed

This creates a direct reason for multiple excavation verbs.

---

## 9. Jam ranking signal

At Godot Wild Jam #79, LAB MEAT ranked:
- #6 Originality
- #17 Audio
- #23 Overall
- #29 Graphics
- #43 Fun
- #53 Controls

Do not overinterpret jam rankings, but the pattern is suggestive:
- concept/presentation attracted attention
- interaction/control quality lagged behind

This matches the written feedback.

### flesh-pit takeaway

The gross premise will attract people.
**The excavation feel is where the game must earn them.**

---

## 10. What to steal / what not to steal

### Steal structurally
- breakable volumetric meat
- procedural embedded targets
- biological sensing
- meat visibly pulsing/reacting
- excavation creates navigation
- cheap shader/audio tricks to sell life

### Steal technically for prototype investigation
- marching cubes
- chunked scalar-field terrain
- C++/native extension only if profiling requires it
- two-material noise blend
- vertex-normal pulse shader

### Avoid
- ambiguous scanner feedback
- targets spawning outside comfortable reach
- repeated identical excavation goal
- depending on gross visuals after mechanical novelty expires

---

## Prototype implication

A minimal technical prototype does not need a full world.

Build:
1. one destructible meat volume
2. one hand/tool removal interaction
3. one embedded target
4. one blood-vessel hazard
5. one pulse shader + heartbeat response
6. enough traversal to carve down and climb back out

If that interaction does not feel good, no amount of worldbuilding will rescue the project.

---

## One-line application to flesh-pit

> **LAB MEAT proves we can fake a living, diggable body cheaply; flesh-pit has to spend the saved complexity budget on making each cut matter.**
