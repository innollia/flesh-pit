"""Run-level spray economy: how often the carry cap binds, and how long the
permanent network takes, for different caps / sprays a can / rest loot.
Numbers from the code and tools/economy (09-reward-scale.md D08, D17, D18):
  shells: E per shell 18 / 25 / 21.33 (100 u expeditions), teeth 8 per E
  tumours 4 / 5 / 5, 24 teeth each when settled whole, spread evenly
  one-off tools: knife 16 (core), bag 16 + blender 40 (mantle), saw 80 (surface)
  spray: cheap 8 teeth = n x 0.5 m, deep 24 teeth = n x 1.5 m (deep from
         mantle), n sprays a can (decisions 0005, 0006)
  rest loot: one can on the chair of each rest point, the shell's tier
         (cheap in the core, deep beyond), taken once (decision 0006)
  network: trunk 23.7 m (7.5 / 8.1 / 8.1 m per shell), rest branches
           core 2 x 6 m, mantle 4 x 18 m, surface 6 x 30 m
Policy: rests of a shell are reached evenly over its expeditions. A reached
loot can is taken first (if a belt slot is free) and sprayed; then buy a tool
as soon as it is unlocked and affordable (saving for it), otherwise spend on
spray up to the cap for the nearest unfinished segment of the current shell
(trunk first, then branches). Teeth per trip = 8 x u/100.
"""

E_SHELL = [18.0, 25.0, 21.33]
TUMORS = [4, 5, 5]
TOOLS = [[("knife", 16)], [("bag", 16), ("blender", 40)], [("saw", 80)]]
TRUNK = [7.5, 8.1, 8.1]
BRANCH = [[6.0] * 2, [18.0] * 4, [30.0] * 6]


def run(cap=3, u=100, per_can=6, loot=True):
    teeth = 0.0
    built = 0.0
    binds = 0
    loot_waits = 0
    loot_m = 0.0
    total = sum(TRUNK) + sum(sum(b) for b in BRANCH)
    per_trip = 8.0 * u / 100.0
    for s in range(3):
        n_trips = round(E_SHELL[s] * 100.0 / u)
        tumor_at = set(round((i + 0.5) * n_trips / TUMORS[s]) for i in range(TUMORS[s]))
        rests = len(BRANCH[s])
        reach_at = [round((k + 1) * n_trips / (rests + 1)) for k in range(rests)]
        tools = list(TOOLS[s])
        segs = [TRUNK[s]] + list(BRANCH[s])
        price, depth = (24, 1.5) if s >= 1 else (8, 0.5)
        pending = 0

        def spray(metres):
            nonlocal built
            left = metres
            while left > 1e-9 and segs:
                take = min(left, segs[0])
                segs[0] -= take
                left -= take
                built += take
                if segs[0] <= 1e-6:
                    segs.pop(0)
            return metres - left

        for t in range(n_trips):
            teeth += per_trip
            if t in tumor_at:
                teeth += 24
            if loot:
                pending += reach_at.count(t)
            cans = 0
            while pending and cans < cap and segs:
                pending -= 1
                cans += 1
                loot_m += spray(per_can * depth)
            if pending and cans >= cap:
                loot_waits += 1
            while tools and teeth >= tools[0][1]:
                teeth -= tools[0][1]
                tools.pop(0)
            if tools:
                continue  # saving for the tool
            while cans < cap and teeth >= price and segs:
                teeth -= price
                cans += 1
                spray(per_can * depth)
            if cans == cap and teeth >= price and segs:
                binds += 1
        # unfinished segments of this shell carry no further (player moves on)
    return {'share': built / total, 'teeth_left': teeth, 'binds': binds, 'loot_waits': loot_waits, 'loot_m': loot_m}


print('sprays a can, rest loot -> end-of-run network, teeth left, cap binds (of 64 trips), loot used')
for per_can, loot in ((6, False), (8, False), (6, True), (8, True)):
    r = run(per_can=per_can, loot=loot)
    print('%d a can, loot %-3s: network %5.1f%%, teeth left %5.1f, cap binds %d, loot %4.1f m' % (
        per_can, 'yes' if loot else 'no', r['share'] * 100, r['teeth_left'], r['binds'], r['loot_m']))
print('== carry cap, 6 a can with loot')
for cap in (3, 4, 6, 99):
    r = run(cap=cap)
    print('cap %2d: network %5.1f%%, cap binds %d, loot waited %d' % (cap, r['share'] * 100, r['binds'], r['loot_waits']))
