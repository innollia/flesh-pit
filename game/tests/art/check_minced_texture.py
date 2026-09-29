# Checks the ending sphere texture reads as raw meatball, not white pepper noise:
# fat must form a few large clumps and the red meat must have brightness mottling.
import sys, numpy as np
from PIL import Image
im = np.asarray(Image.open(r"C:\Users\fixme\Desktop\flesh-pit-main\game\main\art\textures\tex_minced_meat_128.png").convert("RGB")).astype(float) / 255
fat = (im.min(axis=2) > 0.6)
lab = np.zeros(fat.shape, int); n = 0; sizes = []
for y, x in zip(*np.nonzero(fat)):
    if lab[y, x]: continue
    n += 1; stack = [(y, x)]; lab[y, x] = n; c = 0
    while stack:
        a, b = stack.pop(); c += 1
        for da, db in ((1,0),(-1,0),(0,1),(0,-1)):
            p, q = (a+da) % 128, (b+db) % 128
            if fat[p, q] and not lab[p, q]: lab[p, q] = n; stack.append((p, q))
    sizes.append(c)
sizes = np.array(sizes)
meat = im[~fat].mean(axis=1)
big = (sizes >= 30).sum(); frac = sizes[sizes >= 30].sum() / max(sizes.sum(), 1)
print(f"fat blobs {len(sizes)} big {big} big_frac {frac:.2f} meat_lum_std {meat.std():.3f}")
ok = big >= 6 and frac >= 0.8 and meat.std() >= 0.07 and 0.05 <= fat.mean() <= 0.2
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)