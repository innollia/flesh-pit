# Reference Map

Working reference board for **flesh-pit**.

The point of this document is not to copy whole games. Each reference is attached to a specific design problem we can borrow from, test against, or deliberately avoid.

---

## 1. Core progression loop: dig → earn → upgrade → dig deeper

### A Game About Digging A Hole
https://store.steampowered.com/app/3244220/A_Game_About_Digging_A_Hole/

**Reference for**
- extremely legible primary loop
- depth as progression
- converting recovered material into upgrades
- battery / inventory / tool capacity as simple gates
- keeping a mining game small instead of turning it into a survival-crafting game

**Do not copy blindly**
- ordinary soil/ore structure
- upgrade pacing should react to biological layers rather than just numerical depth

### Frankenmine
https://store.steampowered.com/app/4481330/

**Reference for**
- incremental/mining structure mixed with flesh and bone resources
- grotesque materials functioning as progression resources

**Difference from this project**
- flesh is primarily loot/material rather than the mine itself

---

## 2. Directly digging through flesh

### Whale Flesh
https://store.steampowered.com/app/3460910/Whale_Flesh/

**Reference for**
- physically carving passages through a gigantic animal
- flesh as destructible level geometry
- X-ray / hidden-object searching
- explosives as a different excavation verb
- short-form horror scale

**Important distinction**
- its loop is exploration/horror, not sell → upgrade → deeper excavation

### LAB MEAT
https://unconscious-a.itch.io/labmeat

**Reference for**
- searching a mass of flesh for higher-value biological material
- destructible/procedural meat
- scanner + excavation relationship
- turning meat quality into a reason to choose where to dig

**Especially useful**
This sits very close to the project's resource-discovery problem, but does not appear to build a full equipment economy around it.

### LimeFlesh
https://store.steampowered.com/app/5008330/LimeFlesh/

**Reference for**
- living flesh as traversable/diggable environment
- tunneling through biological matter
- extracting biological resources

**Important distinction**
- currently useful mainly as a world/material reference; the target loop here is much more compact and upgrade-driven

---

## 3. Giant-organism / flesh-world visual language

### Mystery Flesh Pit National Park
https://www.mysteryfleshpitnationalpark.com/

**Reference for**
- gigantic organism treated as geography
- recognizable anatomical regions becoming named places
- industrial exploitation of living biology
- mundane infrastructure placed inside impossible anatomy
- scale communicated through maps, diagrams, signage, equipment and institutional language

**Use carefully**
The project should borrow the *design logic*—biology behaving like terrain and resource strata—not depend on Mystery Flesh Pit lore or copyrighted setting details.

### Scorn
https://store.steampowered.com/app/698670/Scorn/

**Reference for**
- biomechanical material language
- tools and environment sharing one biological design vocabulary
- readable hard/soft tissue contrast

**Do not inherit**
- slow puzzle-adventure pacing
- uniformly oppressive visual density if it hurts mining readability

### Golden Light
https://store.steampowered.com/app/1245430/Golden_Light/

**Reference for**
- flesh interiors behaving as a game world rather than a single monster room
- grotesque biological matter becoming mechanically ordinary through repetition

---

## 4. What the biological mine can replace

Instead of conventional:

| Mining-game concept | Flesh-pit equivalent |
| --- | --- |
| soil | fat / soft connective tissue |
| stone | dense muscle / cartilage |
| hard rock | bone / calcified growth |
| ore vein | vascular cluster / mineral deposit / tumor / foreign body |
| cave | organ cavity |
| underground water | blood / lymph / digestive fluid |
| gas pocket | pressurized organ gas / infected cavity |
| rare gem | pathological or symbiotic biological material |
| depth zone | anatomical layer / organ system |
| drill tier | cutting, cautery, sawing, suction, chemical or thermal tool tier |

The useful design question is not “how do we reskin ore?” but:

> **What properties of living tissue can create different digging decisions?**

Candidate properties:
- regenerates after being cut
- bleeds and obscures vision
- contracts or moves
- transmits vibration
- becomes dangerous when overheated
- is valuable only while fresh
- contains vessels/nerves that punish careless excavation
- changes resistance with heartbeat or breathing cycle

---

## 5. Small-game scope guardrails

Current direction:
- short indie game
- one dominant interaction: excavation
- very small economy
- few upgrade axes
- biological depth tiers provide most of the novelty
- horror emerges from the job/material rather than long narrative sequences

Avoid scope drift into:
- open-world survival
- crafting trees
- base building
- full park management
- combat-heavy survival horror
- dozens of resource types with no distinct digging behavior

---

## 6. Research gaps to fill next

### Mechanical references
Need examples for:
- satisfying deformable/destructible digging
- tactile cutting/sawing/suction interactions
- upgrades that alter *how* material is removed, not only speed
- games with intentionally tiny economies
- risk/reward mining where damaging surrounding material reduces value

### Biological references
Need visual/technical references for:
- tissue layers at human-readable scale
- muscle fiber direction
- fascia
- cartilage
- cancellous vs cortical bone
- vessels embedded in tissue
- benign/malignant masses
- scar tissue and calcification

The goal is **stylized mechanical plausibility**, not medical simulation.

### Presentation references
Need examples for:
- selling grotesque material through mundane industrial UI
- compact upgrade shop presentation
- depth/anatomy map readable at a glance
- corporate/mining labels that make absurd biology feel routine

---

## 7. Prior-art status

Working conclusion from the initial survey:

- digging through flesh: **already done**
- giant-organism exploration: **already done**
- dig → sell → upgrade → deeper: **already done**
- flesh/bone as resources: **already done**
- **giant living organism as the mine + compact dig/sell/tool-upgrade/deeper loop:** no close finished example found in the initial search

Treat that last line as a **working prior-art hypothesis**, not a permanent claim. Keep checking as development continues.
