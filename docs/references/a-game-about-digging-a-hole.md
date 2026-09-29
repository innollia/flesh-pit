# Reference: A Game About Digging A Hole

Source role: **primary reference for compact digging-loop structure**

## Sources

- Steam store / official community news: https://steamcommunity.com/app/3244220/allnews/
- CritLab review: https://www.critlabreview.com/articles/a-game-about-digging-a-hole
- Wikipedia gameplay overview: https://en.wikipedia.org/wiki/A_Game_About_Digging_a_Hole
- Community discussion on progression/longevity: https://www.reddit.com/r/GameTheorists/comments/1il8je7/lore_regarding_a_game_about_digging_a_hole_with/

## Why this matters to flesh-pit

This is the clearest modern example of the small-game structure we are targeting:

**dig → capacity/resource pressure → return → improve capability → go deeper**

The project should copy the *clarity and cadence* of that loop, not its ore economy or literal upgrade list.

---

## 1. Loop anatomy

Player starts with:
- weak digging tool
- limited inventory
- limited battery
- shallow, easily readable terrain

Digging produces:
- new space
- sellable ore
- a reason to choose a route

Return to surface allows:
- selling
- recharging
- tool upgrades
- inventory upgrades
- battery upgrades
- utility purchases

The key structural property is that **the same action produces both spatial progress and economic progress**.

Digging is not a chore between rewards. Digging *is* the main reward-producing action.

### Translation for flesh-pit

Our equivalent should remain equally clean:

**eat/tear → stomach fills → return to restroom → empty stomach → spend/notice mutation → go deeper**

Avoid adding a second unrelated economy unless the prototype demonstrates a need for one.

---

## 2. Return cadence

A useful observation from reviews is that the game generally returns the player to the surface before the loop becomes exhausting, and the player often has enough resources to purchase something noticeable on return.

This matters more than the exact upgrade prices.

### Design lesson

For flesh-pit:
- stomach capacity is not merely an inventory stat
- it controls the rhythm of the entire game
- the first few stomach fills should be short
- a restroom return should usually reveal or enable *something*
- early returns must not feel like walking tax

A bad implementation:
- eat for 20 seconds
- spend 40 seconds walking back
- vomit
- nothing changes
- repeat

A better implementation:
- first excursion is short
- first return establishes vomiting
- next excursion exposes mutation accumulation
- following return gives first meaningful mutation/tool change
- later capacity upgrades lengthen expeditions as depth increases

The ratio between **time eating** and **time returning** needs prototype measurement.

---

## 3. Capacity creates route decisions

AGADAH's limited backpack means finding valuable ore while nearly full creates a decision: continue or return.

Its battery adds a second clock.

Our stomach can combine these functions more elegantly:
- capacity is physically understandable
- eating directly fills it
- deeper travel increases the cost of returning

But avoid stacking too many meters immediately.

### Current recommendation

Early game:
- stomach only

Later, biological complications can create situational limits:
- bleeding
- irritation
- pain
- tissue reaction

Do not begin with stomach + stamina + oxygen + health + tool durability + mutation meter all competing for attention.

---

## 4. Upgrade categories

AGADAH mainly improves:
- excavation effectiveness
- carrying capacity
- excursion duration
- traversal
- obstacle removal

That small set is enough for a short game.

### Flesh-pit equivalents

| AGADAH role | flesh-pit equivalent |
| --- | --- |
| shovel power/radius | bite/tear/cut volume and interaction type |
| inventory | stomach capacity |
| battery | potentially digestion/endurance, only if needed |
| jetpack | deeper-return traversal shortcut / anatomy traversal mutation |
| dynamite | destructive tissue bypass tool |
| lamps | visibility / biological sensing utility |

Important: do not mechanically duplicate every category.

The strongest idea is to make upgrades alter **verbs**:
- hand-tear
- bite
- cut
- hook/pull
- saw
- suction
- cautery

A new verb should interact differently with vessels, nerves, tumors, bone, muscle, etc.

---

## 5. Major upgrade should feel physically different

The shovel-to-drill transition is valuable because it is not only a number increase. Continuous drilling changes:
- input behavior
- sound
- removal rate
- shape/cleanliness of excavation

This is a strong reference for flesh-pit.

### Required equivalent

At least several progression milestones should produce a visible/tactile transition such as:

**hands → cutting tool**
- no longer tearing chunks
- cleaner incision
- safer around valuable structures
- new sound and animation vocabulary

**cutting → powered sawing**
- handles cartilage/bone
- higher speed
- greater risk around vessels/nerves

**raw cutting → suction/cautery**
- changes how bleeding affects excavation
- turns an existing hazard into something manageable

Do not let the mutation tree become "+15% eat speed" repeated ten times.

---

## 6. Depth must introduce qualitative changes

A recurring criticism/community wish around AGADAH is that after the initial novelty, players want:
- more biome changes
- more tools
- more discoveries
- more reasons to replay or keep digging

This is highly relevant because flesh-pit can solve that problem naturally through anatomy.

### Depth should change at least one of

- material behavior
- excavation verb
- navigation
- hazard
- visual grammar
- sound
- organism response
- mutation possibility
- environmental infrastructure

Bad depth progression:
- red flesh with 100 HP
- darker red flesh with 200 HP
- purple flesh with 400 HP

Better:
- soft fat: broad hand excavation
- directional muscle: tears differently along/across fibers
- vascular layer: speed competes with bleeding risk
- nerve-rich layer: careless damage changes the level
- cartilage/bone: demands tool transition
- cavity/organ region: excavation becomes navigation through moving empty space

Exact anatomy/order is not yet canon.

---

## 7. The hole itself is player-authored navigation

One of AGADAH's subtle strengths is that excavation creates the player's route.

The player later has to navigate the geometry they personally produced.

This becomes stronger as depth increases.

### Flesh-pit opportunity

The organism can react to the player's tunnel:
- tissue slowly contracts
- cut surfaces swell
- bleeding fills/marks routes
- nerves cause sections to close
- regeneration partially erases old passages

This turns ordinary self-authored tunnel navigation into something uniquely biological.

Do not overuse this early; permanent enough tunnels are needed for the player to mentally map progress.

---

## 8. Mystery / destination

AGADAH uses the promise of treasure and occasional underground structures to create curiosity beyond pure optimization.

The final narrative payoff is not the part to imitate.

### Flesh-pit lesson

The player does not need a strong narrative reason to go deeper, but should periodically encounter **proof that deeper space contains qualitatively new things**.

Possible forms:
- glimpse of a new organ cavity
- unknown artificial structure embedded in tissue
- enormous moving anatomical feature
- strange object visible behind a currently uncuttable layer
- restroom/infrastructure reacting to depth milestones

This is a curiosity hook, not a quest system.

---

## 9. Scope lesson

Official updates describe the game as having originated from a small experimental digging feature separated from a larger survival project. The resulting game stayed focused enough to become a standalone hit.

This is directly relevant.

### Scope rule for flesh-pit

If a feature does not strengthen one of these, be suspicious:
1. eating/digging feel
2. stomach-return rhythm
3. mutation/tool progression
4. depth variation
5. giant-organism atmosphere

Do not grow:
- crafting
- elaborate combat
- large NPC systems
- survival meters
- branching narrative
just because the setting could support them.

---

## 10. What to steal / what not to steal

### Steal structurally
- instantly understandable loop
- short early return cycle
- visible progress almost every return
- tiny upgrade set
- one or more major tactile tool transitions
- player-authored tunnel geometry
- depth as sufficient motivation
- occasional curiosity objects/areas

### Do not inherit
- conventional sell economy
- generic ore tiers
- upgrades dominated by percentage/stat scaling
- late-game depth with little qualitative change
- long return traversal becoming friction

---

## One-line application to flesh-pit

> **Make every stomach cycle short enough to promise another mutation, and make every major depth band force a new way of eating through the organism.**
