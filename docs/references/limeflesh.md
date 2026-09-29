# Reference: LimeFlesh

Source role: **adjacent unreleased reference for living-wall tunneling and biological-resource gating**

## Sources

- Steam store: https://store.steampowered.com/app/5008330/LimeFlesh/
- SteamDB: https://steamdb.info/app/5008330/info/

## Reliability note

As of 2026-09-29, LimeFlesh is **unreleased / coming soon**.

Use it only for:
- publicly described mechanics
- visible design direction
- prior-art awareness

Do not treat store-page features as proof that the final implementation is fun or polished.

---

## 1. Publicly described loop

The developer describes:
- pushing through flexible bloody walls
- carving player-made tunnels
- gathering biological resources
- tearing turquoise nerve webs
- collecting raw flesh
- constructing large pumps
- using pumps to open major veins
- avoiding roaming hostile entities
- hiding in tunnels
- escaping the organism

This is already closer than Whale Flesh to **biological material as both terrain and progression gate**.

---

## 2. Important overlap with flesh-pit

Shared territory:
- living walls
- player-created tunnel paths
- raw flesh as an interactable resource
- nerves as mechanically distinct material
- large anatomical structures functioning as gates
- short first-person indie scope

Therefore these elements alone are not enough to differentiate flesh-pit.

Our distinct center remains:
- literal eating
- stomach capacity
- restroom/vomit return loop
- mutation progression
- depth-first incremental structure

---

## 3. Biological infrastructure as progression gates

The most interesting disclosed LimeFlesh idea is not the horror.
It is:

**harvest biological resources → construct pumps → open major veins → continue**

This treats anatomy as an infrastructure puzzle.

### flesh-pit adaptation

We do not need crafting pumps, but the principle is useful:

> major anatomical systems can behave like progression gates rather than ordinary walls

Examples:
- sphincter-like muscular gate that requires force or nerve manipulation
- bone plate requiring sawing
- vessel network that must be crossed without catastrophic bleeding
- dense fascia requiring a cutting mutation
- contracting tissue that requires nerve suppression

This is stronger than:
- "layer 4 has 400 HP"

---

## 4. Nerves as a distinct resource/material

LimeFlesh publicly identifies turquoise nerve webs as a harvestable element.

This reinforces that nerve tissue has already appeared as visually/mechanically special biological material in adjacent games.

Our current nerve rule is different:
- disturbing nerves changes/deforms surrounding tissue

Keep that distinction strong.

### Design requirement

Nerves in flesh-pit should primarily be **world-control hazards/interfaces**, not generic collectible ore.

Possible interactions:
- cut nerve → contraction
- stimulate nerve → open/close passage
- sever nerve → permanently disable local reaction
- sense nerve → route planning

---

## 5. Flexible walls vs destructible volume

Store wording emphasizes **pushing through flexible walls** as well as carving tunnels.

That suggests another useful axis:
- terrain need not only disappear
- terrain can deform

### flesh-pit opportunity

Different tissues may respond differently:
- fat compresses
- muscle contracts
- membrane stretches
- cartilage bends little
- bone fractures

A prototype does not need full soft-body simulation.

Even simple state changes can communicate material identity:
- shader displacement
- vertex animation
- temporary collider movement
- pre-authored deformation

---

## 6. Tunnel-as-hiding-place is not our direction

LimeFlesh combines excavation with stealth:
- enemy detects player
- player retreats/hides in tunnels

This is a clear scope fork.

### flesh-pit guardrail

Do not let the project drift into:
- enemy patrol AI
- stealth meters
- chase sequences
- combat

unless later prototyping proves one tiny encounter materially improves the loop.

Our tunnel geometry should serve:
- route planning
- return traversal
- tissue choice
- organism response

not stealth gameplay by default.

---

## 7. Resource gathering is already occupied territory

Because LimeFlesh explicitly includes biological-resource gathering, "mine flesh resources" is not a unique pitch.

This strengthens the current choice to avoid a conventional resource-selling economy.

The distinctive economy is:
- **the player consumes the mine**
- consumption fills stomach
- consumption mutates player

This is more integrated than carrying biological ore in a backpack.

---

## 8. Short-game convergence

Like Whale Flesh, LimeFlesh is pitched as a short experience.

This suggests the "dig through flesh" premise naturally attracts compact horror projects.

Our differentiation should therefore be visible in a trailer within seconds:

1. player tears/eats wall
2. stomach visibly fills
3. player runs to restroom and vomits
4. mutation unlock/change
5. player returns with a new bodily/tool capability

That sequence communicates the actual game better than generic body-horror footage.

---

## 9. What to steal / what not to steal

### Steal structurally
- major anatomy as progression gates
- nerves as special material/system
- flexible/deforming tissue concept
- biological resource logic embedded in world
- tunnels as player-authored geometry

### Avoid
- crafting-heavy biological-resource chains
- stealth/chase focus
- generic escape narrative becoming main motivation
- treating every biological object as collectible material

---

## One-line application to flesh-pit

> **Use anatomy to gate new excavation verbs; do not use flesh merely as crafting ore.**
