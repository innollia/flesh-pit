# Runtime Terrain, Regeneration, and Return Navigation Research

Status: **production research / prototype guidance**  
Updated: 2026-09-30

Purpose: research implementation patterns and failure modes directly relevant to **flesh-pit**'s current Godot prototype, specifically:

1. continuously edited volumetric terrain and collision cost,
2. flesh regeneration / tunnel-closing algorithms,
3. keeping a self-authored, continuously changing 3D tunnel network navigable without turning the game into GPS-following.

This document does **not** replace `design-core.md`. Recommendations below are prototype directions unless already present in canon.

---

# 0. Executive finding

The three problems are one system:

> **digging changes geometry → regeneration changes it again → collision must catch up → the return route loses clearance → the player needs warning before the route becomes unusable.**

The current prototype already has a strong base:
- density-grid chunks,
- surface-nets meshing,
- per-frame remesh budgeting,
- regeneration toward an original density field,
- a player-protection radius,
- biome/tissue-specific regeneration multipliers,
- contractile squeeze,
- barriers that suppress local regeneration,
- permanent spray that clears and seals tissue.

The main technical risk is now **not raw mesh generation alone**. It is that `FDKChunk.remesh()` currently performs all of the following in one synchronous operation:

1. read padded density,
2. construct visual surfaces,
3. construct the full triangle list again,
4. create a new `ArrayMesh`,
5. create a new `ConcavePolygonShape3D`,
6. assign both visual mesh and collision.

That means every visible regenerative change can also trigger collision reconstruction.

This matters because Godot's own documentation describes concave trimesh collision as the slowest 3D collision form, intended mainly for static level geometry, and the mature Godot Voxel Tools project reports that building mesh colliders can cost **roughly 3–5× more than meshing itself** because the physics engine must build an acceleration structure.

The most promising direction is therefore:

> **keep one authoritative density field, but decouple density simulation, visual remesh, and collision refresh into three different cadences.**

For navigation, **the game system**, not the canary, should evaluate the state of the return route. A cheap hidden model is:

> **maintain a coarse free-space / clearance representation around the explored route and derive a return-route danger value from the minimum traversable clearance back to the restroom.**

The canary itself performs no sensing, pathfinding, or route reasoning. It only expresses that hidden danger value through chirping and frightened movement. To the player it remains just a bird reacting to worsening conditions, not a navigation device or GPS.

For flesh regeneration, the current "relax every carved density sample toward its original value" is a good cheap baseline, but used alone it tends to make every tunnel heal in the same way. The best next step is not a full soft-body simulation. It is to add **surface-local growth terms** on top of the existing baseline so different tissues close space differently.

---

# 1. Current implementation: what matters

Relevant current files:

- `game/addons/flesh_dig_kit/terrain/fdk_terrain_field.gd`
- `game/addons/flesh_dig_kit/terrain/fdk_chunk.gd`
- `game/addons/flesh_dig_kit/terrain/fdk_tissue_rules.gd`
- `game/addons/flesh_dig_kit/terrain/fdk_terrain_config.gd`
- `game/STATUS.md`

Current terrain defaults:
- chunk size: **16 cells**
- cell size: **0.5 m**
- isolevel: **0.5**
- base regeneration: **0.02 density units/s**
- protected radius around player: **1.5 cells**
- remesh budget target: **8 ms/frame**
- current measured full remesh has been around **5.8–7.0 ms/chunk** in project validation.

Important implementation details:

### A. Visual mesh and collider are inseparable right now

At the end of `FDKChunk.remesh()`:

```gdscript
_mesh_instance.mesh = mesh
var shape := ConcavePolygonShape3D.new()
shape.set_faces(all_verts)
_collision.shape = shape
```

So a chunk that changes visually also rebuilds the collider immediately.

### B. Regeneration dirties a chunk continuously

`FDKChunk.regenerate()` moves every eligible carved density corner toward `_original_density`; if anything changes, the entire chunk is marked dirty.

This is desirable for the living-world effect, but it means regeneration can create a steady stream of remesh work even when the visual difference between two frames is tiny.

### C. Contractile tissue also dirties chunks

The contractile system recalculates active surface-adjacent corners and marks the chunk dirty when contraction changes enough.

So normal regeneration + contractile motion can compete for the same remesh queue.

### D. The player-protection sphere prevents burial, not route loss

The protection radius guarantees the tissue does not simply regenerate through the player's current body, which is necessary.

It does **not** guarantee that the route several metres behind the player remains passable. That is exactly the design pressure the canary is meant to communicate.

---

# 2. Runtime terrain: what external implementations teach

## 2.1 Concave collision is correct for this shape, but expensive

Godot describes `ConcavePolygonShape3D` as:
- flexible enough for arbitrary level geometry,
- intended for static bodies,
- the **slowest** 3D collision-shape type.

Godot also recommends separating visual geometry from simpler collision geometry when possible; a collision mesh does not need to reproduce every visual detail.

Sources:
- https://docs.godotengine.org/en/latest/classes/class_concavepolygonshape3d.html
- https://docs.godotengine.org/en/latest/tutorials/physics/collision_shapes_3d.html
- https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html

### flesh-pit translation

Do **not** replace the tunnel collider with many convex shapes. The world is genuinely concave and constantly changing; decomposition would add a large new cost and complexity.

Instead, preserve chunked static concave collision, but update it less often and possibly from a lower-detail representation.

---

## 2.2 Collider construction can be more expensive than meshing

Voxel Tools, a long-running volumetric terrain implementation for Godot, reports:

- terrain collider blocks are static concave mesh colliders,
- collider creation can cost roughly **3–5× the mesh-generation step**,
- the expensive part includes creating the physics acceleration structure,
- because some work cannot be safely pushed into its meshing workers, it spreads collider setup across frames,
- it exposes a main-thread time budget specifically to prevent large update bursts from stalling a frame.

Source:
- https://voxel-tools.readthedocs.io/en/latest/performance/

This is unusually relevant because flesh-pit independently converged on the same architecture:
- 16³ chunks,
- runtime edits,
- static concave chunk colliders,
- a per-frame update budget.

### flesh-pit translation

The existing `remesh_ms_per_frame` idea is sound, but it currently budgets **one combined product**.

Split the product conceptually into:

- **density dirty**
- **visual dirty**
- **collision dirty**

A chunk should be allowed to become visually current before its collision is rebuilt.

Suggested first experiment:

| layer | near player | farther away |
| --- | --- | --- |
| density simulation | normal cadence | reduced cadence |
| visual mesh | fast / budgeted | slow / budgeted |
| collision | only after meaningful topology/clearance change | very slow or none until approached |

Do not choose the final interval from research. Measure it in the prototype.

---

## 2.3 Bulk edits beat repeated random edits

Voxel Tools explicitly warns that repeated single-voxel edits pay repeated lookup/locking/invalidation costs, while region operations and copy-edit-paste patterns can amortize that overhead.

Sources:
- https://voxel-tools.readthedocs.io/en/latest/performance/
- https://voxel-tools.readthedocs.io/en/latest/scripting/
- https://voxel-tools.readthedocs.io/en/latest/api/VoxelTool/

flesh-pit's own code already mostly edits contiguous regions for spray and sphere operations, which is good.

The weaker path is continuous regeneration: every chunk scans its whole corner array every update even when only a small shell around the tunnel surface is relevant.

### flesh-pit translation

A later optimization target should be an **active-regeneration set**.

When a corner is dug below original density:
- insert its index into a compact active list / bitset,
- regeneration iterates only those indices,
- remove it when it returns to original density,
- nearby spray/seal operations invalidate/remove affected indices.

This is lower risk than changing the mesher and directly attacks the cost that scales with "how much world has ever been loaded".

The contractile system already does a related optimization with `_contract_idx`; reuse that idea.

---

## 2.4 Threading: move data work first, not scene-tree mutation

Godot supports worker threads, but warns that the active scene tree is not thread-safe. Resources and scene nodes require care, and the safest structure is usually:

1. worker reads/copies plain density data,
2. worker computes arrays / vertices,
3. main thread commits mesh/collision resources.

Sources:
- https://docs.godotengine.org/en/latest/tutorials/performance/using_multiple_threads.html
- https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html

### flesh-pit translation

If threading becomes necessary, the first candidate is the pure CPU section of surface-nets generation.

Do **not** begin by threading `_collision.shape = ...` or manipulating chunk nodes from a worker.

Before threading at all, split timing instrumentation into:

- padded-density build,
- surface-net vertex calculation,
- surface emission,
- `ArrayMesh` creation/assignment,
- `ConcavePolygonShape3D.set_faces`,
- collision assignment.

The current single `elapsed_ms` hides which part is actually expensive on the target machine.

---

# 3. Recommended terrain pipeline experiment

This is the highest-value implementation experiment produced by this research.

## Stage 1 — density simulation

Density is canonical.

Every dig/regeneration/contraction updates density immediately according to gameplay simulation.

But density change does not automatically mean both rendered mesh and collider must update in the same frame.

## Stage 2 — visual remesh queue

Prioritize by:
1. chunks intersecting the current chew,
2. chunks very near player/camera,
3. chunks whose isosurface topology changed,
4. other visible chunks,
5. offscreen regeneration.

Use the current time-budget approach.

## Stage 3 — collision refresh queue

Collision can lag visual regeneration slightly, with constraints:

- after **digging away** flesh directly in front of the player, collision must clear quickly enough that the player does not hit invisible flesh,
- when flesh **grows back**, collision may update more slowly because a temporarily permissive tunnel is less frustrating than an invisible wall,
- when the clearance approaches player-body size, prioritize collision refresh,
- never allow stale collision to trap the player inside a region that the density field considers solid.

This implies asymmetric urgency:

> **removal collision updates are urgent; regrowth collision updates can be delayed.**

That asymmetry is particularly well suited to flesh-pit.

## Stage 4 — collision LOD

Prototype a second, simpler collision surface.

Options in increasing complexity:

1. use the same surface-nets output but update collision less often,
2. produce collision from a coarser density sample,
3. simplify only collision triangles after meshing,
4. keep high-resolution collision only in a small radius around the player.

Start with option 1. It requires almost no new geometry algorithm and will reveal whether decoupling alone is enough.

---

# 4. Flesh regeneration algorithms

## 4.1 Existing method: relaxation toward the original field

Current model:

> if current density < original density, add `regen_rate × tissue multiplier × dt` until original is reached.

Advantages:
- deterministic,
- reversible,
- trivial to save,
- local,
- cheap,
- preserves the original large-scale anatomy,
- barriers and permanent spray integrate cleanly.

This should **remain the base layer**.

Its weakness is aesthetic/mechanical uniformity: every carved cavity tends to heal by restoring the exact previous volume.

If all tissues only change the scalar speed, the three biome languages eventually become "same closing tunnel, different timer."

---

## 4.2 Signed-distance offset / dilation: cheap "wall grows inward"

A signed distance field represents the surface as the zero crossing of a scalar distance function. Moving the threshold / adding a constant to the field creates approximately uniform normal motion of the surface.

Voxel Tools uses clamped SDFs specifically because game terrain does not need a mathematically exact distance everywhere; local gradients near the surface are enough.

Sources:
- https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC6129271/

### Useful behavior for flesh-pit

An inward offset makes open space shrink from all sides.

That is ideal as an inspiration for **compressive tissue**:
- rounded bulges,
- passages lose radius,
- narrow sections disappear before wide chambers,
- regrowth visually reads as tissue occupying space rather than individual voxels refilling independently.

### Important caveat

The current density values are occupancy-like 0..1 values, not a true SDF.

Do not rewrite the entire terrain representation just to get this effect.

Approximate it locally:
- identify empty/solid boundary corners,
- add density faster to empty corners that are close to multiple solid neighbors,
- optionally blur/average one narrow surface band before thresholding,
- keep `_original_density` as the hard upper bound.

This creates dilation-like closure while preserving the current storage model.

---

## 4.3 Morphological closing: useful as a diagnostic, dangerous as the main simulation

Mathematical morphology's **closing** operation is dilation followed by erosion. In volumetric data it preferentially fills small gaps/tunnels while preserving larger-scale object extent.

Sources:
- https://doi.org/10.1016/j.cad.2023.103608
- https://discourse.itk.org/t/create-a-mask-filling-holes-of-the-image/4116

That maps suspiciously well to "small return tunnel gets swallowed."

However, using binary closing directly every frame would:
- produce thresholdy changes,
- aggressively erase small passages,
- be expensive if run over a large volume,
- fight the deliberate gradual pressure fantasy.

### flesh-pit translation

Use morphological closing as a **test oracle**, not the live algorithm.

Offline/debug use:
- copy a local occupancy volume,
- perform closing with a radius approximately equal to player clearance,
- detect which parts of the tunnel are about to become "topologically fragile."

That information can feed:
- canary danger tests,
- automated regression tests,
- route-clearance visualization.

---

## 4.4 Mean-curvature flow: good visual inspiration, too much for the first implementation

Level-set mean-curvature flow smooths surfaces while moving them according to curvature.

Sources:
- https://www.sciencedirect.com/science/article/abs/pii/S0007850608000619
- https://www.jstage.jst.go.jp/article/jsiamt/10/2/10_KJ00002977560/_article/-char/en
- https://pmc.ncbi.nlm.nih.gov/articles/PMC6129271/

For flesh-pit it suggests an important visual rule:

> thin spikes and tight concavities should disappear faster than broad smooth walls.

That would make healing look biological instead of like a uniform opacity slider.

But a correct level-set solver and SDF reinitialization are unnecessary scope for the prototype.

### cheap approximation

For compressive tissue, compute a local neighbor term:

```text
growth = base_regen
       + closure_bias * solid_neighbor_fraction
       + small_noise
```

For a carved surface corner:
- more surrounding solid neighbors → faster return,
- isolated broad cavity → slower return,
- clamp to original density.

This imitates some curvature-sensitive behavior with a tiny implementation cost.

---

# 5. Three tissue languages from one density system

The research supports keeping **one terrain representation** and varying the evolution rule.

## 5.1 Compressive tissue

Target feeling:
- soft mass slowly reoccupies void,
- narrow passages pinch first,
- wall surfaces bulge.

Prototype rule:
- existing original-field relaxation,
- plus neighbor/clearance-biased growth,
- low-frequency spatial noise in rate,
- no fixed global pulse.

Mechanical result:
- player can read "this tunnel is becoming thin" continuously.

## 5.2 Contractile tissue

Current project already has the right conceptual distinction:
- directional/periodic squeeze,
- warning before movement,
- local wave phase.

Keep it **temporally coherent** rather than making its normal regeneration simply faster.

Research implication:
- contractile tissue should create a moving clearance bottleneck, not merely refill deleted density more quickly.

The existing `contract_phase()` and envelope structure is therefore more valuable than another regeneration multiplier.

## 5.3 Nerve-dense tissue

Do not make it the fastest healer.

Its identity is causality:
- player touches/damages conspicuous nerves,
- local contraction follows,
- the environment visibly reacts to the player's action.

Use ordinary/slower passive regeneration and strong **event-driven local closure**.

That keeps the three biomes mechanically distinct:

| tissue | dominant change |
| --- | --- |
| compressive | continuous inward creep |
| contractile | recurring directional squeeze |
| nerve-dense | triggered local reaction |

---

# 6. Navigation research: what actually helps people

## 6.1 Landmarks improve wayfinding

Controlled virtual-environment studies repeatedly find that distinctive landmarks help route learning and wayfinding.

Particularly useful observations:
- landmarks provide fine-grained location anchors,
- landmarks associated with **decision points / turns** are especially useful,
- route knowledge and global survey knowledge are not the same thing,
- local landmarks help route-following while more global/distal cues can help integrate separated local spaces.

Sources:
- https://pubmed.ncbi.nlm.nih.gov/16955726/
- https://pubmed.ncbi.nlm.nih.gov/25667573/
- https://www.sciencedirect.com/science/article/pii/S0272494425001446
- https://doi.org/10.1016/j.jenvp.2024.102391

### flesh-pit translation

Do not make every metre of tunnel equally red and interchangeable.

At meaningful junctions, allow strong local identity through existing world vocabulary:
- dense yellow nerve clump,
- embedded pipe/valve/inspection plate,
- membrane seam,
- different tissue motion,
- a cavity with a recognizable silhouette,
- a rare human fixture embedded in flesh.

These are not arrows. They are memory anchors.

The best place to spend rare infrastructure props is therefore **route decision areas**, not uniformly random decoration.

---

## 6.2 Deep Rock Galactic deliberately reduced cave complexity

Ghost Ship Games has repeatedly described navigation as a constraint on procedural cave generation.

In a 2017 interview, the team said underground caves proved difficult to navigate, so cave systems ended up relatively simple.

In later official cave-generation material, their designer describes three core concerns:
- traversal,
- natural wayfinding,
- dramatic experience.

Individual rooms are shaped to "funnel" players toward exits and are repeatedly tested under procedural variation.

Sources:
- https://gamingbolt.com/deep-rock-galactic-interview-heigh-ho-off-to-plunder-we-go
- https://store.steampowered.com/news/posts/?appgroupname=Deep+Rock+Galactic&appids=548430&enddate=1730296516&feed=steam_community_announcements
- https://unwinnable.com/2018/08/28/deep-rock-galactic/

### flesh-pit translation

The fact that flesh-pit lets the player dig anywhere does **not** mean all generated anatomy should be maximally labyrinthine.

Complexity is already created by the player.

Therefore:
- large-scale biome/anatomy generation should supply readable macro-structure,
- player excavation supplies local complexity,
- regeneration supplies temporal complexity.

Do not ask procedural generation to supply all three simultaneously.

---

## 6.3 Player-made marks work because they encode direction, not just position

Minecraft cave players commonly use side-specific torch placement or deliberately different blocks as return-route markers.

Source:
- https://minecraft.wiki/w/Tutorial%3AExploring_caves

The important principle is not "add torches."

It is:

> a marker is much more useful when it carries **route semantics** ("I came from that side") instead of merely being recognizable.

### flesh-pit translation

The project does not need a breadcrumb item immediately.

First exploit traces the core verb already creates:
- bite direction,
- asymmetrical wound surfaces,
- severed tissue orientation,
- tool-specific scars,
- sprayed permanent surfaces.

If later playtests show players still cannot reconstruct routes, a deliberate marker tool can be added, but do not start there.

Permanent biosecurity spray is already a natural high-cost landmark because it creates a lasting non-regenerating surface.

---

# 7. The game should compute route clearance; the canary only expresses the result

This is the strongest navigation implementation recommendation from the research.

Robotics and path-planning literature commonly uses an occupancy grid plus a distance/clearance field:
- each free location stores distance to the nearest obstacle,
- path planners can penalize low-clearance routes,
- narrow passages can be detected explicitly,
- local 3D voxel maps can keep the computation bounded.

Examples:
- subterranean navigation using an Euclidean signed-distance field: https://onlinelibrary.wiley.com/doi/full/10.4218/etrij.2021-0087
- 3D voxel path planning using distance transforms: https://www.sciencedirect.com/science/article/abs/pii/S0926580517311184
- clearance fields for grid paths: https://www.mdpi.com/2076-3417/16/7/3512

## Proposed hidden model

Maintain a coarse occupancy grid only for the explored corridor around:
- player,
- known restroom position,
- recently traversed route.

Example resolution for prototype:
- **1.0 m cells**, not the terrain's 0.5 m density corners.

For each coarse free cell, estimate clearance:
- nearest solid distance,
- or a cheaper local radius classification.

Run a low-frequency path query from player to restroom.

The hidden return-route danger value should not be based on path length alone.

Use:

```text
route_margin = minimum_clearance_along_best_return_path
```

or a weighted form that also accounts for:
- number of critically narrow cells,
- rate at which those cells are shrinking,
- whether a route disappeared since the last sample.

Then pass only that hidden danger scalar to the canary presentation logic. The bird does not receive the route, bottleneck position, or direction home; it merely becomes more vocal/agitated as the scalar worsens.

Example **structure**, not final tuning:

| hidden condition | presentation |
| --- | --- |
| route comfortably wide | quiet |
| one section trending narrow | occasional chirp |
| return path contains sustained low-clearance segment | repeated urgent chirps |
| no passable path at player body radius but nearby emergency widening exists | panic |

This satisfies the canon:
- the **system** detects worsening return conditions,
- the **canary** only chirps/reacts,
- no direction, path, bottleneck position, or exact geometry is revealed to the player,
- the bird's behavior becomes meaningful because tissue physically narrows.

---

# 8. Why clearance is better than "distance from restroom"

Euclidean distance fails in the exact cases flesh-pit cares about:

- player may be physically near the restroom but separated by regenerated tissue,
- a long route may be perfectly safe,
- a short route can contain one fatal bottleneck,
- a shifted tunnel can remain connected but lose enough width to become practically unusable.

A clearance-aware graph distinguishes these.

It also gives the game a reusable measurement for:
- canary warning,
- death-drop recoverability tests,
- barrier usefulness,
- whether spray trivializes route pressure,
- automated map-generation validation.

---

# 9. Cheap prototype of the clearance system

Do **not** build a full NavigationServer solution for deforming geometry first.

The terrain already owns the authoritative occupancy information.

Prototype:

1. Define a coarse grid around explored space.
2. A cell is "free" if several sample points are below the terrain isolevel.
3. Inflate solids by approximate player radius, or equivalently require clearance > player radius.
4. Flood-fill / A* from restroom coarse cell to player coarse cell.
5. Record:
   - reachable?
   - minimum clearance,
   - path length,
   - smallest-clearance position,
   - change since previous sample.
6. Recompute at low frequency, e.g. when:
   - player moves into another coarse cell,
   - enough density chunks changed,
   - every fixed fraction of a second while regeneration is active.

The path itself is never rendered and never given to the player.

This is an **instrumentation and warning model**, not a navigation UI.

If A* becomes unnecessary overhead, flood-fill reachability plus a distance transform is already useful.

---

# 10. Collision scheduling and canary output can consume the same hidden route-risk metric

A useful architectural consequence appears here.

If a chunk contains the current return route's narrowest passage:
- prioritize its density sampling,
- prioritize visual remesh,
- prioritize collision refresh,
- raise the hidden danger state so the canary presentation becomes more urgent.

Thus the navigation model can also help schedule terrain work.

Instead of:
> all dirty chunks are equally important

use:
> chunks affecting the player or the return bottleneck are urgent.

This is particularly valuable because regeneration can dirty many chunks continuously.

---

# 11. Prototype tests worth adding

These produce real answers; searching the web for exact balance numbers will not.

## Performance instrumentation

### T1 — separate remesh timings
Measure independently:
- density/padded build,
- surface-net calculation,
- mesh resource creation,
- collider `set_faces`,
- collider assignment.

Record p50 / p95 / max over a 60-second continuous dig/regrow session.

### T2 — decoupled collision cadence
Compare:
- collision every visual remesh,
- collision every 2nd visual remesh,
- collision every 4th visual remesh,
- event-prioritized collision.

Measure:
- frame-time spikes,
- invisible-wall incidents after digging,
- player clipping during regrowth.

### T3 — regeneration stress scene
Create a long pre-dug tunnel across many chunks and enable regeneration simultaneously.

This is more representative than timing one isolated remesh.

### T4 — contractile burst scene
Force several nearby contractile chunks into overlapping dirty windows and verify the queue does not produce a visible multi-second lag.

---

## Navigation / design tests

### N1 — return clearance
Generate a known tunnel and gradually close one neck.

Assert that the hidden return margin monotonically approaches danger before connectivity is lost.

### N2 — alternate route
Create:
- one short narrow route,
- one longer wide route.

The hidden route-risk model should classify the longer wide route as safer if it remains traversable; the canary only reflects the resulting danger level.

### N3 — barrier
Place a barrier across the critical narrowing point.

Verify hidden return margin stabilizes while barrier holds, then collapses rapidly when it fails.

### N4 — permanent spray
Open a permanent bypass.

Verify:
- route safety becomes stable,
- edible material on that route is lost,
- navigation pressure is reduced exactly as intended.

### N5 — moving death drop
Use the same coarse map to determine whether a displaced dropped item remains in the same reachable free-space component.

Do not reveal this to the player; use it to identify impossible recovery states during playtests.

---

# 12. What not to build yet

## A. Full soft-body flesh

The design needs changing topology and readable pressure, not physically correct biomechanics.

A soft-body simulation introduces:
- solver instability,
- collision complexity,
- save/load complexity,
- synchronization with digging,
without directly solving the core loop.

## B. Full true-SDF rewrite

True SDFs make elegant surface operations possible, but the current 0..1 density field already supports the game.

Approximate surface-local growth first.

## C. Dynamic navmesh rebuilds for player navigation

The player is not an AI agent following generated paths.

A coarse hidden occupancy/clearance model is cheaper and better aligned with the canary.

## D. Every-frame global pathfinding

Route pressure changes slowly enough to sample.

Update on dirty-region events / coarse movement / a low fixed cadence.

## E. Exact GPS arrow

Wayfinding research supports landmarks and multiple kinds of spatial cues, but the current design explicitly wants the player to read the tissue rather than obey a perfect sensor.

Use hidden exact computation to drive **inexact diegetic feedback**.

---

# 13. Recommended implementation order

## P0 — instrument before changing architecture

Add split timing around `FDKChunk.remesh()`.

Without this, optimization will be guessing.

## P1 — decouple visual and collision dirty states

This is the single highest-value engineering experiment.

Keep the current mesh algorithm.

Test asymmetric collision urgency:
- dig/removal = urgent,
- regrowth = delayed/budgeted.

## P2 — active regeneration indices

Stop scanning fully healed corners every regeneration update.

Reuse the conceptual pattern already present in `_contract_idx`.

## P3 — coarse return-clearance prototype

Build it first as debug output only.

Display:
- reachable,
- path length,
- min clearance,
- bottleneck world position.

Once it behaves reliably, feed only the danger level to the canary.

## P4 — compressive tissue surface bias

Add a very small neighborhood-based growth term.

Goal:
- narrow tunnels close before broad rooms,
- visible bulges,
- no full SDF rewrite.

## P5 — playtest navigation landmark density

Before creating a marker system, test whether:
- biome transitions,
- rare infrastructure,
- nerves,
- membranes,
- permanent spray scars

are enough to create memorable decision points.

---

# 14. Concrete conclusions for flesh-pit

### Keep
- 16³ chunking for now.
- surface nets.
- original-density restoration as the regeneration backbone.
- static concave chunk collision.
- per-frame time budgeting.
- player no-regeneration protection.
- contractile tissue as a distinct wave/event system.
- canary as qualitative feedback only.

### Change / test
- split visual remesh from collider rebuild.
- profile collider creation separately.
- iterate only active damaged density where possible.
- prioritize updates by player + return-bottleneck relevance.
- compute return danger from route **clearance**, not restroom distance.
- give compressive tissue a surface-neighborhood closing bias.

### Avoid
- treating different tissue as only different `REGEN` numbers.
- increasing procedural maze complexity merely because free digging exists.
- solving navigation with a perfect arrow.
- a full soft-body or full SDF rewrite before these cheaper experiments fail.

---

# 15. Sources

## Godot / voxel implementation

- Godot — ConcavePolygonShape3D  
  https://docs.godotengine.org/en/latest/classes/class_concavepolygonshape3d.html
- Godot — Collision shapes 3D  
  https://docs.godotengine.org/en/latest/tutorials/physics/collision_shapes_3d.html
- Godot — 3D import collision separation  
  https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- Godot — Using multiple threads  
  https://docs.godotengine.org/en/latest/tutorials/performance/using_multiple_threads.html
- Godot — Thread-safe APIs  
  https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html
- Voxel Tools — Performance  
  https://voxel-tools.readthedocs.io/en/latest/performance/
- Voxel Tools — Scripting / editing  
  https://voxel-tools.readthedocs.io/en/latest/scripting/
- Voxel Tools — VoxelTool bulk operations  
  https://voxel-tools.readthedocs.io/en/latest/api/VoxelTool/
- Voxel Tools — Smooth terrain / SDF  
  https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/

## Surface evolution / morphology

- Zhang & Leu — Virtual sculpting with surface smoothing based on level set method  
  https://www.sciencedirect.com/science/article/abs/pii/S0007850608000619
- Kimura & Notsu — Signed-distance level set method for mean-curvature flow  
  https://www.jstage.jst.go.jp/article/jsiamt/10/2/10_KJ00002977560/_article/-char/en
- Wang et al. — signed-distance / curvature-flow surface evolution discussion  
  https://pmc.ncbi.nlm.nih.gov/articles/PMC6129271/
- Morphological closing / offset discussion in volumetric geometry  
  https://doi.org/10.1016/j.cad.2023.103608
- ITK discussion — morphology via signed distance maps  
  https://discourse.itk.org/t/create-a-mask-filling-holes-of-the-image/4116

## Wayfinding / cave design

- Jansen-Osmann & Fuchs — landmarks and virtual-environment wayfinding  
  https://pubmed.ncbi.nlm.nih.gov/16955726/
- Piccardi et al. — landmark + direction knowledge at route decisions  
  https://pubmed.ncbi.nlm.nih.gov/25667573/
- Landmark type × route/survey strategy study (2025)  
  https://www.sciencedirect.com/science/article/pii/S0272494425001446
- Distal landmarks and global spatial representation (2024)  
  https://doi.org/10.1016/j.jenvp.2024.102391
- Deep Rock Galactic interview — caves deliberately kept navigable  
  https://gamingbolt.com/deep-rock-galactic-interview-heigh-ho-off-to-plunder-we-go
- Ghost Ship official cave-generation feature  
  https://store.steampowered.com/news/posts/?appgroupname=Deep+Rock+Galactic&appids=548430&enddate=1730296516&feed=steam_community_announcements
- Deep Rock Galactic procedural navigation discussion  
  https://unwinnable.com/2018/08/28/deep-rock-galactic/
- Minecraft cave navigation strategies  
  https://minecraft.wiki/w/Tutorial%3AExploring_caves

## Clearance / subterranean navigation

- Collision-free local planner for unknown subterranean navigation  
  https://onlinelibrary.wiley.com/doi/full/10.4218/etrij.2021-0087
- 3D voxel indoor path planning using distance transform  
  https://www.sciencedirect.com/science/article/abs/pii/S0926580517311184
- Clearance cost shaping from Euclidean distance transform  
  https://www.mdpi.com/2076-3417/16/7/3512
