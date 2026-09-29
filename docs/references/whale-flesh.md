# Reference: Whale Flesh

Source role: **closest direct reference for digging through a gigantic animal; major negative-design reference**

## Sources

- Steam store: https://store.steampowered.com/app/3460910/Whale_Flesh/
- Steam top reviews: https://steamcommunity.com/app/3460910/reviews/?browsefilter=toprated
- Steam community: https://steamcommunity.com/app/3460910

## Why this matters to flesh-pit

Whale Flesh proves that the basic image works:

> enter an impossibly large organism and physically carve your own route through meat

It also demonstrates the largest danger in the concept:

> **flesh is not automatically an interesting mining material**

If every wall looks and behaves the same, biological novelty burns off extremely fast.

---

## 1. Actual loop

The game is deliberately short, officially described as under an hour.

The practical loop is roughly:

**dig through flesh → follow locator/beacon → reach point of interest → repeat**

Tools/interactions include:
- pickaxe excavation
- locator / x-ray-like searching
- limited dynamite
- flashlight / lantern tradeoff
- occasional hidden objects and events

There is no meaningful upgrade economy.

### Implication

This is almost the opposite half of our design:
- Whale Flesh has the **material fantasy**
- flesh-pit needs the **progression machinery**

Our project should not assume the environment alone can carry repeated digging.

---

## 2. Biggest failure: uniform flesh

Multiple player reviews independently complain that:
- digging is slow
- walls look too similar
- traversal is repetitive
- points of interest lack variation
- curiosity loses against excavation tedium

This is the single most important lesson from the game.

### Hard rule for flesh-pit

Do not build one generic "flesh voxel" with more HP at depth.

At minimum, major tissue families need distinct:
- appearance
- sound
- removal animation
- resistance pattern
- hazard
- optimal tool/verb

Potential tissue families:
- fat
- fascia
- muscle
- vessel-rich tissue
- nerve-rich tissue
- cartilage
- cortical bone
- cancellous bone
- pathological growth
- organ membrane

The exact list and order remain non-canon until prototyped.

---

## 3. Digging speed vs digging interest

Whale Flesh criticism is not simply "digging is too slow."

The deeper problem is:

**slow action + low decision density = tedium**

Slow excavation can still work if the player is deciding:
- where to cut
- how deep to cut
- what to avoid
- which tool to use
- whether to preserve a structure
- whether to accept a hazard

### flesh-pit response

Even the earliest hand-eating stage should create micro-decisions.

Examples:
- tear along muscle fibers for speed
- avoid a visible vessel
- bite through a shortcut but trigger bleeding
- preserve a growth for mutation yield
- choose soft tissue route vs short dense route

The player should not merely hold input against a wall.

---

## 4. Locator / x-ray lesson

Whale Flesh uses a locator/search device to direct the player toward hidden points.

The concept is useful because opaque flesh naturally creates an information problem.

### Possible flesh-pit adaptation

Later mutations/tools could reveal:
- blood vessels
- nerves
- high-mutation tissue
- cavities
- foreign objects
- structural weak points

This turns sensing into a route-planning mechanic.

Do not make sensing a mandatory "follow the dot" objective chain.
It is more useful as **player-controlled information** for choosing where to eat.

---

## 5. Dynamite lesson

Explosives create a second excavation verb:
- large-volume destruction
- low precision
- limited supply

The important thing is not dynamite specifically.
It is the existence of **high-throughput / high-collateral excavation**.

### flesh-pit equivalent

Potential destructive tools/mutations:
- powered saw
- chemical digestion
- corrosive secretion
- high-force tearing
- rotary cutter

These should become dangerous around:
- blood vessels
- nerves
- intact valuable growths

This creates a meaningful contrast with precise cutting.

---

## 6. Equipment-slot friction

A positive review notes that a better lantern competes with the pickaxe in hand/equipment use.

This is useful as a design pattern:
- information/visibility can compete with excavation efficiency

### Possible flesh-pit use

Examples:
- one hand holds tissue apart while the other cuts
- sensor must replace the main tool temporarily
- suction occupies a hand but controls bleeding
- cautery prevents bleeding but removes edible/mutation value

This is more interesting than generic inventory-slot limits because it changes the immediate action.

---

## 7. Horror pacing lesson

Whale Flesh tries to use repetitive labor as a focus task so horror events can interrupt it.

Reviews suggest this fails when the labor itself is not engaging enough.

### flesh-pit implication

Horror should not be the reward for tolerating boring excavation.

The eating/digging loop must work even if:
- no monster appears
- no jumpscare occurs
- no lore note is found

Then strange biological events can interrupt an already satisfying routine.

---

## 8. Curiosity needs visible promises

Blindly digging through homogeneous material creates weak exploration.

### Better pattern for flesh-pit

Give the player partial information:
- pulse or sound through a wall
- a vessel direction suggesting a cavity
- visible embedded artificial structure
- scanner silhouette
- tissue color/texture transition
- restroom map indicating approximate anatomy

Curiosity should answer:
**"what is over there?"**

not:
**"maybe something exists somewhere in this identical meat."**

---

## 9. Short-game lesson

Whale Flesh demonstrates that even an under-hour game can feel repetitive if the core action lacks evolution.

Therefore our small scope does **not** excuse shallow progression.

A 60–120 minute game can still require:
- several tissue families
- at least a few strong verb/tool transitions
- environmental escalation
- clear depth milestones

The number of systems can remain tiny.

---

## 10. What to steal / what not to steal

### Steal structurally
- organism is directly destructible
- player-authored tunnels through flesh
- opaque tissue creating information problems
- sensor/x-ray as excavation aid
- high-collateral alternate excavation verb
- very compact total runtime

### Avoid
- one universal wall material
- one repetitive excavation animation
- blindly following objective markers
- horror events compensating for weak digging
- points of interest that all look mechanically identical

---

## One-line application to flesh-pit

> **Whale Flesh proves the fantasy; our job is to make every new tissue ask a different question before the player puts their mouth or tool into it.**
