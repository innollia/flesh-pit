# Reference: SteamWorld Dig

Source role: **foundational design reference for dig → return → upgrade and player-authored tunnel design**

## Sources

- Game Developer deep dive: https://www.gamedeveloper.com/design/game-design-deep-dive-the-digging-mechanic-in-i-steamworld-dig-i-
- Game Developer postmortem: https://www.gamedeveloper.com/design/video-postmortem-the-successes-and-failures-of-i-steamworld-dig-i-
- Steam store: https://store.steampowered.com/app/252410/SteamWorld_Dig/
- SteamWorld Dig 2 Steam store: https://store.steampowered.com/app/571310/SteamWorld_Dig_2/

## Success signal

SteamWorld Dig became an indie hit and was ported across multiple platforms. Its developer later gave a public postmortem specifically about its launch and design. As of 2026, the original still holds roughly 93% positive English Steam reviews across about 3,000 reviews, while SteamWorld Dig 2 sits around 95% positive across about 3,000 English reviews.

Review counts are not sales counts, but they show unusually durable reception for a 2013/2017 digging series.

---

## 1. The original intended design failed in playtests

The designers originally wanted digging to be a route-planning puzzle:
- every removed tile mattered
- players risked getting stuck underground
- returning safely with ore was supposed to create tension

What happened in tests:
- players dug straight downward
- many got stuck
- they failed to bring resources back
- they then could not afford upgrades
- they were not having fun

This is one of the most useful digging-game lessons available.

### flesh-pit lesson

Do not design around what a "smart" player *should* do.

Players will:
- eat straight down
- create terrible tunnels
- ignore safe routes
- fill their stomach at the worst location
- destroy useful tissue

Therefore the first prototype must support the stupidest obvious action.

If straight-down eating produces a soft-lock or tedious return, the design is wrong before the tutorial is wrong.

---

## 2. Accessibility beat the original purity

Image & Form added movement mechanics to compensate for player behavior rather than forcing players to learn the intended strict digging puzzle.

The developer explicitly describes this as a compromise that made the game more accessible and fun.

### flesh-pit application

Potential recovery tools:
- forgiving climb/mantle
- wall-grip mutation
- temporary route markers
- later shortcut growth
- tissue deformation that creates footholds

Do not build a long tutorial explaining "proper tunnel architecture" unless that is genuinely the fantasy.

---

## 3. Digging does three jobs simultaneously

In SteamWorld Dig, digging:
1. creates the route
2. reveals resources
3. progresses downward

This is efficient design.

### flesh-pit target

Eating should likewise do several jobs at once:
1. removes terrain
2. fills stomach
3. generates mutation progression
4. reveals deeper anatomy
5. creates the player's return route

The fewer parallel unrelated systems required, the stronger the small-game scope.

---

## 4. Resource return makes tunnels meaningful

Ore has value only if the player successfully returns with it.

That makes the geometry the player created matter twice:
- once while descending
- again while returning

### flesh-pit equivalent

Stomach capacity makes the same geometry matter.

The player does not need to sell meat.

Instead:
- eating creates depth
- stomach reaches limit
- player must traverse their own hole back to the restroom
- vomiting resets the cycle

This may be a cleaner integration than conventional inventory/ore.

---

## 5. The strongest tension is self-created

The threat of getting stuck was not an enemy.
It was the consequence of the player's own excavation.

Even after accessibility changes, this remains an important design property:
**the hole is both progress and problem.**

### flesh-pit extension

Biology can make the hole react:
- muscle contracts
- wounds swell
- blood obscures old passages
- nerve damage closes a route
- regeneration partially changes geometry

Use carefully.
The player must still feel ownership of the tunnel.

---

## 6. Sequel lesson: digging can support a larger exploration game

SteamWorld Dig 2 keeps mining but expands:
- movement
- authored areas
- Metroidvania progression
- caves/challenges
- ability gating

This proves digging can remain central while stronger authored variety surrounds it.

### Scope warning

Our project is much smaller.

Do not imitate Dig 2's content volume.

Take only the principle:
**a new ability should open a new way to traverse/dig, not only increase a number.**

---

## 7. Direct application

Prototype test:
- tell a new player nothing except "eat"
- watch whether they go straight down
- let them fill the stomach
- see whether they can naturally return
- observe whether the tunnel is readable on the way back

If the loop survives that test, then add biological hazards.

---

## One-line application to flesh-pit

> **Assume the player will eat straight down like an idiot; build a system where even that creates an interesting, recoverable hole.**
