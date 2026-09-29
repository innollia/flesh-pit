# flesh-pit

Small indie digging/incremental game about **eating through a gigantic living organism**.

## Canonical loop

**eat flesh → stomach fills → return through a tunnel that is slowly growing shut → vomit in the clean restroom → mutate → go deeper**

Important:
- no sell loop
- vomit has no resource value
- flesh regenerates and gradually narrows old routes
- stomach capacity + regeneration speed define the return pressure
- death drops belongings at the death location, but losing them is not catastrophic

## Identity

The player does not simply mine red blocks.

Eating has:
- tissue elasticity
- chewing time
- visible tearing/deformation

Mutation is communicated through:
- sound
- footstep/camera shake
- visible hands/HUD
- stomach UI

Nerves are yellow, protruding, wriggling structures that can deform nearby tissue when disturbed.

Cancer/tumor growths are currently a collectible codex system rather than a required upgrade resource.

The restroom is intentionally **clean and white**: the safe visual exception inside an otherwise red, dirty biological world.

Navigation uses a **compass and canary**.

## World direction

Original setting only. Mystery Flesh Pit National Park is a design reference, not canon.

Depth itself is the objective. The open design problem is making each anatomical depth band create new play rather than just tougher flesh.

See:
- [docs/design-core.md](docs/design-core.md)
- [docs/asset-list.md](docs/asset-list.md) — every required image asset, one by one, UI included
- [tools/artgen](tools/artgen/README.md) — procedural generator that renders that list into `assets/`
- [docs/todo.md](docs/todo.md)
- [docs/reference-map.md](docs/reference-map.md)
- [docs/world-direction.md](docs/world-direction.md)
