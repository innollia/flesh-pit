# Design Core

Status: **current working canon**
Last updated: 2026-09-29

## 1. Core loop

1. leave the restroom through its door and tear / chew / eat into the flesh blocking the way
2. stomach fills
3. return toward the clean restroom
4. vomit into the toilet to empty stomach capacity
5. mutation progress accumulates and becomes visible
6. go back out and eat deeper

There is no sell loop. Vomit has no resource or crafting value.

The target rhythm should borrow from successful compact digging games: stomach capacity and early refill timing should be tuned so returns happen often enough to teach the loop without becoming constant interruption.

## 2. Regenerating flesh is a core pressure

Excavated flesh **grows back**.

This is not just world flavor. It changes the return trip:
- the tunnel gradually narrows behind the player
- old routes become less comfortable or partially obstructed
- deeper excursions increase return pressure

Early-game stomach capacity and flesh-regeneration speed should be intentionally tuned so the player notices regeneration during the first few loops without needing explicit explanation.

The first version should make the phenomenon obvious but recoverable rather than punitive.

## 3. Eating feel

Eating is not abstract block deletion.

Required physical signals:
- tissue elasticity
- chewing / consumption time
- visible tearing/deformation before removal

Start:
- bare hands
- tearing
- eating

Tool progression is unresolved and must preserve the identity of **eating through the organism**, not turn the player into an ordinary miner.

One tool role is already expected: the player can eventually use a tool or device that **suppresses or prevents flesh regeneration locally**, allowing selected routes or areas to remain open longer.

See TODOs.

## 4. Mutation feedback

Mutation should be felt through the player's body and presentation, not only numbers.

Accepted feedback channels:
- sound changes
- heavier / altered footstep shake
- the player's hands as an in-world HUD
- stomach UI changing with mutation

Major mutations should be perceptible immediately.

## 5. Tissue-specific rules

### Blood vessels
**Cancelled as a core mechanic for now.**

Do not assume bleeding/vascular avoidance is part of the core design unless reintroduced later.

### Nerves
Nerves are intentionally conspicuous:
- yellow
- protrude from walls
- wriggle like garden eels

The player should recognize them before interacting.

Their current mechanical role remains:
- touching/damaging them can cause local tissue contraction, shifting, or deformation

The reaction must read as caused by the player's action rather than arbitrary punishment.

### Cancer / tumors
Cancerous growths are primarily a **collection/codex element**.

Current canon:
- collect/discover entries for a cancer/tumor codex
- additional direct gameplay benefit is undecided

Do not force a reward system onto them until there is a reason.

## 6. Death and recovery

Death exists.

On death:
- dropped belongings remain at the death location
- the player can return and recover them
- failing to recover them should not create a severe long-term penalty

Death should create a small recovery objective, not wipe progression.

## 7. Navigation

Accepted navigation aids:
- compass
- canary

Biome-finding should use a **mixed information model**:
- long-range information is vague rather than exact
- the canary or another lightweight cue may indicate that something different exists in a broad direction, without acting like a GPS arrow
- at close range, the tissue itself gives stronger readable precursors such as changes in color, texture, motion, sound, elasticity, embedded structures, or other biome-specific signals
- the final route choice should still come from reading the flesh rather than following a perfect sensor

The exact canary behavior is still open, but if it contributes to biome finding it should provide ambiguous long-range foreshadowing rather than exact destination tracking.

Biome geography is not fully static. As flesh regenerates, biome boundaries drift and reshape continuously during play rather than only between expeditions.

The world can shift enough that, on return, the restroom doorway and previously excavated tunnel may be slightly misaligned with where the player remembers them. This should read as living tissue moving and regrowing, not as a discrete map reroll.

This drift should preserve the sense that the organism is alive and changing, but it must not make navigation or recovery objectives arbitrarily impossible.

The game must remain navigable despite player-made tunnels, continuous flesh regeneration, and biome-boundary drift.

## 8. Restroom

The game starts inside the restroom.

Opening the door does not reveal a normal corridor or open exterior. The doorway is blocked immediately by a wall of flesh, establishing the first required act of excavation.

From that doorway, excavation is volumetric rather than a fixed downward shaft. The player can eat into the flesh:
- forward
- upward
- downward
- left
- right

The restroom is deliberately **clean and white**.

Visual rule:
- the flesh world is dirty/red/organic
- the restroom is the safe white exception

It should feel genuinely safe and clean rather than secretly disgusting.

Primary functions:
- empty stomach by vomiting
- mark the end of one expedition cycle
- expose mutation/progression
- provide a strong visual reset between excursions

The restroom already serves as the game's emotional contrast space.

Additional restroom content is TODO.

## 9. Depth

Going deeper is the core-loop objective and does not require a conventional quest justification.

Because excavation can proceed in multiple directions from the restroom doorway, **deeper does not automatically mean downward on the world Y-axis**. The exact rule that defines progression depth is unresolved.

Current working structure:
- the restroom sits near the center of multiple nested roughly spherical layers
- crossing outward through shells defines increasing depth regardless of excavation direction
- **Primary target:** each shell contains multiple biome regions, so different excavation directions can encounter different tissue environments at the same depth
- **Scope fallback:** if production cost becomes too high, reduce to one dominant biome per shell rather than expanding scope
- shell boundaries use a **hybrid transition**: tissue composition changes gradually as the player approaches the next shell, followed by a clearer boundary signal / membrane / distinctive transition feature near the actual crossing
- the transition should preserve an organic continuous-body feeling while still making a new depth band legible

Depth must change play, not only HP/resistance values.

**TODO:** use Mystery Flesh Pit and adjacent references only as brainstorming material for distinct depth/anatomy zones in the original world.

## 10. Ending ideas — not canon

Current possibilities, all unconfirmed:
- mutation escalates until a biological singularity / irreversible transformation
- the restroom is located inside a large intestine; the player eventually digs through and exits via the anus
- the player is actually a parasite moving through a human/organism body
- other endings may replace all of the above

Do not build the project around any of these yet.

## 11. Scope

This is a small indie game.

Protect:
- digging/eating core loop
- stomach pressure
- regeneration pressure
- restroom reset
- mutation feedback
- strong depth milestones

Avoid accidental expansion into:
- survival crafting
- large combat systems
- base building
- park management
- sprawling narrative adventure
