"""Run-level spray economy: how often the carry cap binds, and how long the
permanent network takes, for different caps / prices. Numbers from the code
and tools/economy (09-reward-scale.md D08, D17, D18):
  shells: E per shell 18 / 25 / 21.33 (100 u expeditions), teeth 8 per E
  tumours 4 / 5 / 5, 24 teeth each when settled whole, spread evenly
  one-off tools: knife 16 (core), bag 16 + blender 40 (mantle), saw 80 (surface)
  spray: cheap 8 teeth = n x 0.5 m, deep 24 teeth = n x 1.5 m (deep from
         mantle), n sprays a can (6 before 2026-10-20, 8 now; decision 0005)
  network: trunk 23.7 m (7.5 / 8.1 / 8.1 m per shell), rest branches
           core 2 x 6 m, mantle 4 x 18 m, surface 6 x 30 m
Policy: buy a tool as soon as it is unlocked and affordable (saving for it),
otherwise spend on spray up to the cap for the nearest unfinished segment of
the current shell (trunk first, then branches). Teeth per trip = 8 x u/100.
"""
import itertools

E_SHELL = [18.0, 25.0, 21.33]
TUMORS = [4, 5, 5]
TOOLS = [[("knife", 16)], [("bag", 16), ("blender", 40)], [("saw", 80)]]
TRUNK = [7.5, 8.1, 8.1]
BRANCH = [[6.0] * 2, [18.0] * 4, [30.0] * 6]


def run(cap, u=100, cheap=(8, 3.0), deep=(24, 9.0), sprays_scale=1.0, label=''):
    """cheap/deep: (teeth, metres a can at 6 sprays); sprays_scale = n / 6."""
    teeth = 0.0
    trips = 0
    binds = 0
    leftover_trips = 0
    built = 0.0
    total = sum(TRUNK) + sum(sum(b) for b in BRANCH)
    done_trip = None
    per_trip = 8.0 * u / 100.0
    for s in range(3):
        n_trips = round(E_SHELL[s] * 100.0 / u)
        tumor_at = set(round((i + 0.5) * n_trips / TUMORS[s]) for i in range(TUMORS[s]))
        tools = list(TOOLS[s])
        segs = [TRUNK[s]] + list(BRANCH[s])
        for t in range(n_trips):
            trips += 1
            teeth += per_trip
            if t in tumor_at:
                teeth += 24
            while tools and teeth >= tools[0][1]:
                teeth -= tools[0][1]
                tools.pop(0)
            if tools:
                continue  # saving for the tool
            price, metres = deep if s >= 1 else cheap
            metres *= sprays_scale
            cans = 0
            while cans < cap and teeth >= price and segs:
                teeth -= price
                cans += 1
                left = metres
                while left > 0 and segs:
                    take = min(left, segs[0])
                    segs[0] -= take
                    left -= take
                    built += take
                    if segs[0] <= 1e-6:
                        segs.pop(0)
            if cans == cap and teeth >= price and segs:
                binds += 1
            if teeth >= price and not segs:
                leftover_trips += 1
            if done_trip is None and built >= total - 1e-6:
                done_trip = trips
        # unfinished segments of this shell carry no further (player moves on)
    return {'label': label, 'cap': cap, 'trips': trips, 'binds': binds, 'built_m': built, 'total_m': total,
            'share': built / total, 'teeth_left': teeth, 'done_trip': done_trip, 'idle_trips': leftover_trips}


for u in (100, 160):
    print('== 6 sprays a can (before), expedition %d u' % u)
    for cap in (3, 4, 6, 99):
        r = run(cap, u)
        print('cap %2d: trips %d, cap binds on %d trips, network %.0f / %.0f m (%.0f%%), teeth left %.0f' % (
            cap, r['trips'], r['binds'], r['built_m'], r['total_m'], r['share'] * 100, r['teeth_left']))
print('== 8 sprays a can (now), 100 u')
for cap in (3, 4):
    r = run(cap, 100, sprays_scale=8 / 6)
    print('cap %2d: binds %d, network %.0f%%, teeth left %.0f' % (cap, r['binds'], r['share'] * 100, r['teeth_left']))
