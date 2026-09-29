# Reference Map

Working reference board for **flesh-pit**.

The point of this document is not to copy whole games. Each reference is attached to a specific design problem we can borrow from, test against, or deliberately avoid.

**Worldbuilding note:** this project uses an original setting. Mystery Flesh Pit National Park and other works below are reference material only, not shared continuity.


## Cross-game research

- [Digging-game success cases](research/digging-success-cases.md) — commercial signals, loop structure, progression failures, and flesh-pit design rules

---

## Detailed reference studies

- [A Game About Digging A Hole](references/a-game-about-digging-a-hole.md) — compact loop, return cadence, tool progression
- [Whale Flesh](references/whale-flesh.md) — direct flesh excavation and its repetition failure modes
- [LAB MEAT](references/lab-meat.md) — deformable meat, scanning, marching-cubes implementation notes
- [LimeFlesh](references/limeflesh.md) — living-wall tunneling and anatomy as progression gates
- [Mystery Flesh Pit method](references/mystery-flesh-pit-method.md) — abstract worldbuilding method only; original setting remains separate

---

## 1. Core progression loop: dig → capacity limit → return → upgrade → dig deeper

### A Game About Digging A Hole
https://store.steampowered.com/app/3244220/A_Game_About_Digging_A_Hole/

**Reference for**
- extremely legible primary loop
- depth as progression
- capacity as a reason to return
- simple upgrade pacing
- keeping a mining game small instead of turning it into survival crafting

**Project translation**
- inventory capacity becomes stomach capacity
- selling is removed
- return-to-surface becomes return-to-restroom
- shop economy becomes mutation progression

### Frankenmine
https://store.steampowered.com/app/4481330/

**Reference for**
- incremental/mining structure mixed with flesh and bone resources
- grotesque materials functioning as progression objects

**Difference from this project**
- flesh is not merely loot; the giant organism itself is the mine

---

## 2. Directly digging through flesh

### Whale Flesh
https://store.steampowered.com/app/3460910/Whale_Flesh/

**Reference for**
- physically carving passages through a gigantic animal
- flesh as destructible level geometry
- X-ray / hidden-object searching
- explosives as an alternate excavation verb
- short-form horror scale

**Important distinction**
- exploration/horror rather than a repeatable capacity-return-mutation loop

### LAB MEAT
https://unconscious-a.itch.io/labmeat

**Reference for**
- searching a mass of flesh for higher-value biological material
- destructible/procedural meat
- scanner + excavation relationship
- tissue quality affecting where the player chooses to dig

**Especially useful**
This sits close to the project's tissue-selection problem, but not its stomach/return/mutation progression structure.

### LimeFlesh
https://store.steampowered.com/app/5008330/LimeFlesh/

**Reference for**
- living flesh as traversable/diggable environment
- tunneling through biological matter
- extracting biological resources

**Important distinction**
- currently useful mainly as a material/world reference; the target loop here is more compact and incremental

---

## 3. Giant-organism / flesh-world design language

### Mystery Flesh Pit National Park
https://www.mysteryfleshpitnationalpark.com/

**Reference for abstract principles only**
- gigantic organism treated as geography
- anatomical regions functioning like named terrain
- mundane infrastructure embedded in impossible biology
- humans normalizing and exploiting a colossal living body
- scale communicated through maps, signage, engineering and institutional artifacts

**Do not import directly**
- lore
- names
- organizations
- locations
- attractions
- creatures
- maps
- historical events
- proprietary terminology

The goal is to learn from the *design logic* while maintaining an original setting.

### Scorn
https://store.steampowered.com/app/698670/Scorn/

**Reference for**
- biomechanical material language
- tools and environment sharing a biological vocabulary
- hard/soft tissue contrast

**Do not inherit**
- slow puzzle-adventure pacing
- visual density that harms excavation readability

### Golden Light
https://store.steampowered.com/app/1245430/Golden_Light/

**Reference for**
- flesh interiors functioning as ordinary navigable space
- grotesque biology becoming mechanically routine through repetition

---

## 4. Flesh-specific mining rules already accepted

### Blood vessels
Cutting can create bleeding that obscures vision or complicates navigation.

### Nerves
Damage can make surrounding tissue contract, shift, or temporarily close routes.

### Tumors / valuable growths
Careless destruction lowers quality or mutation yield.

These are important because they make flesh mechanically different from dirt rather than merely visually different.

---

## 5. Biological mine vocabulary

| Mining-game concept | Flesh-pit equivalent |
| --- | --- |
| inventory | stomach |
| surface/base | restroom |
| empty inventory | vomit |
| upgrade currency | mutation points |
| soil | fat / soft connective tissue |
| stone | dense muscle / cartilage |
| hard rock | bone / calcified growth |
| ore vein | vascular cluster / mineral deposit / tumor / foreign body |
| cave | organ cavity |
| underground water | blood / lymph / digestive fluid |
| gas pocket | pressurized cavity |
| depth zone | anatomical layer / organ system |
| tool tier | hands / cutting / tearing / sawing / suction / cautery |

---

## 6. Mechanical research targets

Need strong references for:
- satisfying deformable/destructible digging
- tearing flesh by hand
- tactile cutting/sawing/suction interactions
- tools that change excavation verbs rather than only speed
- games with intentionally tiny progression economies
- risk/reward excavation where damaging surroundings lowers payoff
- return loops built around capacity rather than money

---

## 7. Biological reference targets

Need visual/technical references for:
- tissue layers at game-readable scale
- muscle fiber direction
- fascia
- cartilage
- cancellous vs cortical bone
- vessels embedded in tissue
- benign/malignant masses
- scar tissue and calcification

Goal: **stylized mechanical plausibility**, not medical simulation.

---

## 8. Presentation reference targets

Need examples for:
- mundane infrastructure surrounded by impossible biology
- compact mutation/upgrade interfaces
- depth/anatomy maps readable at a glance
- restroom/base spaces that accumulate environmental storytelling
- industrial labels and signage that normalize grotesque surroundings

---

## 9. Prior-art status

Working conclusion from the initial survey:

- digging through flesh: **already done**
- giant-organism exploration: **already done**
- capacity → return → upgrade → deeper: **already done in adjacent mining games**
- flesh/bone as resources: **already done**
- **eat flesh → stomach fills → vomit/reset → mutation → deeper anatomy inside a giant organism:** no close finished example found in the initial search

Treat that last line as a working hypothesis, not a permanent claim.
